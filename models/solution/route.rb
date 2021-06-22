# Copyright © Mapotempo, 2021
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require './models/base'

module Models
  class SolutionRoute < Base
    field :geometry

    has_many :activities, class_name: 'Models::RouteActivity'
    has_many :initial_loads, class_name: 'Models::Load'

    belongs_to :cost_details, class_name: 'Models::CostDetails', default: Models::CostDetails.new({})
    belongs_to :detail, class_name: 'Models::RouteDetail'
    belongs_to :vehicle, class_name: 'Models::Vehicle'

    def as_json(options = {})
      hash = super(options)
      hash.delete('detail')
      hash.merge(detail.as_json(options))
    end

    def activities=(_acts)
      compute_route_waiting_times
    end

    def fill_missing_route_data(vrp, matrix)
      details = compute_route_travel_distances(vrp, matrix)
      compute_route_waiting_times unless activities.empty?

      if detail.end_time && detail.start_time
        detail.total_time = detail.end_time - detail.start_time
      end

      compute_route_total_dimensions(matrix)

      return unless ([:polylines, :encoded_polylines] & vrp.restitution_geometry).any? &&
                    activities.any?(&:service_id)

      details ||= route_details(vrp)
      geometry = details&.map(&:last)
    end

    def compute_route_total_dimensions(matrix)
      previous_index = nil
      dimensions = []
      dimensions << :time if matrix&.time
      dimensions << :distance if matrix&.distance
      dimensions << :value if matrix&.value

      total = dimensions.collect.with_object({}) { |dimension, hash| hash[dimension] = 0 }
      activities.each{ |activity|
        matrix_index = activity.detail.point&.matrix_index
        if previous_index && matrix_index
          dimensions.each{ |dimension|
            activity.timing.send("travel_#{dimension}=", matrix&.send(dimension)[previous_index][matrix_index])
            total[dimension] += activity.timing.send("travel_#{dimension}".to_sym).round
            activity.timing.current_distance ||= total[dimension].round if dimension == :distance
          }
        end

        previous_index = matrix_index
      }

      if detail.end_time && detail.start_time
        detail.total_time = detail.end_time - detail.start_time
      end
      detail.total_travel_time = total[:time].round if dimensions.include?(:time)
      detail.total_distance = total[:distance].round if dimensions.include?(:distance)
      detail.total_travel_value = total[:value].round if dimensions.include?(:value)

      return unless activities.all?{ |a| a.timing.waiting_time }

      detail.total_waiting_time = activities.collect{ |a| a.timing.waiting_time }.sum.round
    end

    def compute_route_waiting_times
      previous_end = activities.first.timing.begin_time
      loc_index = nil
      consumed_travel_time = 0
      consumed_setup_time = 0
      activities.each.with_index{ |act, index|
        used_travel_time = 0
        if act.type == :rest
          if loc_index.nil?
            next_index = activities[index..-1].index{ |a| a.type != :rest }
            loc_index = index + next_index if next_index
            consumed_travel_time = 0
          end
          shared_travel_time = loc_index && activities[loc_index].timing.travel_time || 0
          potential_setup = shared_travel_time > 0 && activities[loc_index].detail.setup_duration || 0
          left_travel_time = shared_travel_time - consumed_travel_time
          used_travel_time = [act.timing.begin_time - previous_end, left_travel_time].min
          consumed_travel_time += used_travel_time
          # As setup is considered as a transit value, it may be performed before a rest
          consumed_setup_time  += act.timing.begin_time - previous_end - [used_travel_time, potential_setup].min
        else
          used_travel_time = (act.timing.travel_time || 0) - consumed_travel_time - consumed_setup_time
          consumed_travel_time = 0
          consumed_setup_time = 0
          loc_index = nil
        end
        considered_setup = act.timing.travel_time&.positive? && (act.detail.setup_duration.to_i - consumed_setup_time) || 0
        arrival_time = previous_end + used_travel_time + considered_setup + consumed_setup_time
        act.timing.waiting_time = act.timing.begin_time - arrival_time
        previous_end = act.timing.end_time || act.timing.begin_time
      }
    end

    def compute_route_travel_distances(vrp, matrix)
      return nil unless matrix&.distance.nil? && activities.size > 1 && activities.all?{ |act| act.detail.point.location }

      details = route_details(vrp)

      return nil unless details && !details.empty?

      activities[1..-1].each_with_index{ |activity, index|
        activity.timing.travel_distance = details[index]&.first
      }

      details
    end

    def route_details(vrp)
      previous = nil
      details = nil
      segments = activities.reverse.collect{ |activity|
        current =
          if activity.type == :rest
            previous
          else
            activity.detail.point
          end
        segment =
          if previous && current
            [current.location.lat, current.location.lon, previous.location.lat, previous.location.lon]
          end
        previous = current
        segment
      }.reverse.compact

      unless segments.empty?
        details = OptimizerWrapper.router.compute_batch(OptimizerWrapper.config[:router][:url],
                                                        vehicle.router_mode.to_sym, vehicle.router_dimension,
                                                        segments, vrp.restitution_geometry.include?(:encoded_polylines),
                                                        vehicle.router_options)
        raise RouterError.new('Route details cannot be received') unless details
      end

      details&.each{ |d| d[0] = (d[0] / 1000.0).round(4) if d[0] }
      details
    end


  end
end
