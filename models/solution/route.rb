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
require './models/solution/route_detail'

module Models
  class SolutionRoute < Base
    field :geometry

    has_many :activities, class_name: 'Models::RouteActivity'
    has_many :initial_loads, class_name: 'Models::Load'

    belongs_to :cost_details, class_name: 'Models::CostDetails'
    belongs_to :detail, class_name: 'Models::RouteDetail'
    belongs_to :vehicle, class_name: 'Models::Vehicle'

    def initialize(options = {})
      super(options)
      self.detail = Models::RouteDetail.new({}) unless options.key? :detail
      self.cost_details = Models::CostDetails.new({}) unless options.key? :cost_details
    end

    def vrp_result(options = {})
      hash = super(options)
      hash.delete('detail')
      hash.merge!(detail.vrp_result(options))
      hash.delete('vehicle')
      hash.merge!(vehicle.vrp_result(options))
      hash.delete_if{ |_k, v| v.nil? }
      hash
    end

    def count_services
      activities.count(&:service_id)
    end

    def compute_total_time
      return if activities.empty?

      detail.end_time = activities.last.timing.end_time || activities.last.timing.begin_time
      detail.start_time = activities.first.timing.begin_time
      return unless detail.end_time && detail.start_time

      detail.total_time = detail.end_time - detail.start_time
    end

    def fill_missing_route_data(vrp, matrix, options = {})
      return if activities.empty?

      compute_missing_dimensions(matrix) if options[:compute_dimensions]
      compute_route_waiting_times
      route_data = compute_route_travel_distances(vrp, matrix)
      compute_total_time
      compute_route_waiting_times unless activities.empty?
      compute_route_total_dimensions(matrix)
      return unless ([:polylines, :encoded_polylines] & vrp.restitution_geometry).any? &&
                         activities.any?(&:service_id)

      route_data ||= route_details(vrp)
      self.geometry = route_data&.map(&:last)
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
            activity.timing.current_distance = total[dimension].round if dimension == :distance
          }
        end

        previous_index = matrix_index
      }

      if self.detail.end_time && self.detail.start_time
        self.detail.total_time = self.detail.end_time - self.detail.start_time
      end
      self.detail.total_travel_time = total[:time].round if dimensions.include?(:time)
      self.detail.total_distance = total[:distance].round if dimensions.include?(:distance)
      self.detail.total_travel_value = total[:value].round if dimensions.include?(:value)

      return unless activities.all?{ |a| a.timing.waiting_time }

      self.detail.total_waiting_time = activities.collect{ |a| a.timing.waiting_time }.sum.round
    end

    def compute_missing_dimensions(matrix)
      dimensions = %i[time distance value]
      dimensions.each{ |dimension|
        next unless matrix&.send(dimension)&.any?

        next if activities.any?{ |activity| activity.timing.send("travel_#{dimension}") > 0 }

        previous_departure = dimension == :time ? activities.first.timing.begin_time : 0
        previous_index = nil
        activities.each{ |activity|
          current_index = activity.detail.point&.matrix_index
          if previous_index && current_index
            activity.timing.send("travel_#{dimension}=",
                                 matrix.send(dimension)[previous_index][current_index])
          end
          case dimension
          when :time
            previous_departure = compute_time_timing(
              activity,
              previous_departure,
              previous_index && current_index && matrix.send(dimension)[previous_index][current_index] || 0
            )
          when :distance
            activity.timing.current_distance = previous_departure
            if previous_index && current_index
              previous_departure += matrix.send(dimension)[previous_index][current_index]
            end
          end

          previous_index = current_index unless activity.type == :rest
        }
      }
    end

    def compute_time_timing(activity, previous_departure, travel_time)
      earliest_arrival =
        [
          activity.detail.timewindows&.find{ |tw| (tw.end || 2**32) > previous_departure }&.start || 0,
          previous_departure + travel_time
        ].max || 0
      if travel_time > 0
        earliest_arrival += activity.detail.setup_duration * vehicle.coef_setup + vehicle.additional_setup
      end
      activity.timing.begin_time = earliest_arrival
      activity.timing.end_time = earliest_arrival +
                                 (activity.detail.duration * vehicle.coef_service + vehicle.additional_service)
      activity.timing.departure_time = activity.timing.end_time
      earliest_arrival
    end

    def compute_route_waiting_times
      return if activities.empty?

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
      return nil unless matrix&.distance.nil? && activities.size > 1 &&
                        activities.reject{ |act| act.type == :rest }.all?{ |act| act.detail.point.location }

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
