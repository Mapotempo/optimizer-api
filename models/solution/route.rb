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
  class Solution < Base
    class Route < Base
      field :geometry

      has_many :steps, class_name: 'Models::Solution::Step'
      has_many :initial_loads, class_name: 'Models::Solution::Load'

      belongs_to :cost_info, class_name: 'Models::Solution::CostInfo'
      belongs_to :info, class_name: 'Models::Solution::Route::Info'
      belongs_to :vehicle, class_name: 'Models::Vehicle'

      def initialize(options = {})
        options = { info: {}, cost_info: {} }.merge(options)
        super(options)
      end

      def vrp_result(options = {})
        hash = super(options)
        hash.delete('vehicle')
        hash['cost_details'] = hash['cost_info']
        hash.delete('cost_info')
        hash['activities'] = hash['steps']
        hash.merge!(info.vrp_result(options))
        hash['detail'] = hash['info']
        hash.delete('info')
        hash.delete('steps')
        hash.merge!(vehicle.vrp_result(options))
        hash.delete_if{ |_k, v| v.nil? }
        hash
      end

      def count_services
        steps.count(&:service_id)
      end

      def compute_total_time
        return if steps.empty?

        info.end_time = steps.last.info.end_time || steps.last.info.begin_time
        info.start_time = steps.first.info.begin_time
        return unless info.end_time && info.start_time

        info.total_time = info.end_time - info.start_time
      end

      def fill_missing_route_data(vrp, matrix, options = {})
        return if steps.empty?

        compute_missing_dimensions(matrix) if options[:compute_dimensions]
        compute_route_waiting_times
        route_data = compute_route_travel_distances(vrp, matrix)
        compute_total_time
        compute_route_waiting_times unless steps.empty?
        compute_route_total_dimensions(matrix)
        return unless ([:polylines, :encoded_polylines] & vrp.restitution_geometry).any? &&
                           steps.any?(&:service_id)

        route_data ||= route_info(vrp)
        self.geometry = route_data&.map(&:last)
      end

      def compute_route_total_dimensions(matrix)
        previous_index = nil
        dimensions = []
        dimensions << :time if matrix&.time
        dimensions << :distance if matrix&.distance
        dimensions << :value if matrix&.value

        total = dimensions.collect.with_object({}) { |dimension, hash| hash[dimension] = 0 }
        steps.each{ |activity|
          matrix_index = activity.activity.point&.matrix_index
          if previous_index && matrix_index
            dimensions.each{ |dimension|
              activity.info.send("travel_#{dimension}=", matrix&.send(dimension)[previous_index][matrix_index])
              total[dimension] += activity.info.send("travel_#{dimension}".to_sym).round
              activity.info.current_distance = total[dimension].round if dimension == :distance
            }
          end

          previous_index = matrix_index
        }

        if self.info.end_time && self.info.start_time
          self.info.total_time = self.info.end_time - self.info.start_time
        end
        self.info.total_travel_time = total[:time].round if dimensions.include?(:time)
        self.info.total_distance = total[:distance].round if dimensions.include?(:distance)
        self.info.total_travel_value = total[:value].round if dimensions.include?(:value)

        return unless steps.all?{ |a| a.info.waiting_time }

        self.info.total_waiting_time = steps.collect{ |a| a.info.waiting_time }.sum.round
      end

      def compute_missing_dimensions(matrix)
        dimensions = %i[time distance value]
        dimensions.each{ |dimension|
          next unless matrix&.send(dimension)&.any?

          next if steps.any?{ |step| step.info.send("travel_#{dimension}") > 0 }

          previous_departure = dimension == :time ? steps.first.info.begin_time : 0
          previous_index = nil
          steps.each{ |step|
            current_index = step.activity.point&.matrix_index
            if previous_index && current_index
              step.info.send("travel_#{dimension}=",
                               matrix.send(dimension)[previous_index][current_index])
            end
            case dimension
            when :time
              previous_departure = compute_time_info(
                step,
                previous_departure,
                previous_index && current_index && matrix.send(dimension)[previous_index][current_index] || 0
              )
            when :distance
              step.info.current_distance = previous_departure
              if previous_index && current_index
                previous_departure += matrix.send(dimension)[previous_index][current_index]
              end
            end

            previous_index = current_index unless step.type == :rest
          }
        }
      end

      def compute_time_info(step, previous_departure, travel_time)
        earliest_arrival =
          [
            step.activity.timewindows&.find{ |tw| (tw.end || 2**32) > previous_departure }&.start || 0,
            previous_departure + travel_time
          ].max || 0
        if travel_time > 0
          earliest_arrival += step.activity.setup_duration * vehicle.coef_setup + vehicle.additional_setup
        end
        step.info.begin_time = earliest_arrival
        step.info.end_time = earliest_arrival +
                                   (step.activity.duration * vehicle.coef_service + vehicle.additional_service)
        step.info.departure_time = step.info.end_time
        earliest_arrival
      end

      def compute_route_waiting_times
        return if steps.empty?

        previous_end = steps.first.info.begin_time
        loc_index = nil
        consumed_travel_time = 0
        consumed_setup_time = 0
        steps.each.with_index{ |step, index|
          used_travel_time = 0
          if step.type == :rest
            if loc_index.nil?
              next_index = steps[index..-1].index{ |a| a.type != :rest }
              loc_index = index + next_index if next_index
              consumed_travel_time = 0
            end
            shared_travel_time = loc_index && steps[loc_index].info.travel_time || 0
            potential_setup = shared_travel_time > 0 && steps[loc_index].activity.setup_duration || 0
            left_travel_time = shared_travel_time - consumed_travel_time
            used_travel_time = [step.info.begin_time - previous_end, left_travel_time].min
            consumed_travel_time += used_travel_time
            # As setup is considered as a transit value, it may be performed before a rest
            consumed_setup_time  += step.info.begin_time - previous_end - [used_travel_time, potential_setup].min
          else
            used_travel_time = (step.info.travel_time || 0) - consumed_travel_time - consumed_setup_time
            consumed_travel_time = 0
            consumed_setup_time = 0
            loc_index = nil
          end
          considered_setup = step.info.travel_time&.positive? && (step.activity.setup_duration.to_i - consumed_setup_time) || 0
          arrival_time = previous_end + used_travel_time + considered_setup + consumed_setup_time
          step.info.waiting_time = step.info.begin_time - arrival_time
          previous_end = step.info.end_time || step.info.begin_time
        }
      end

      def compute_route_travel_distances(vrp, matrix)
        return nil unless matrix&.distance.nil? && steps.size > 1 &&
                          steps.reject{ |act| act.type == :rest }.all?{ |act| act.activity.point.location }

        info = route_info(vrp)

        return nil unless info && !info.empty?

        steps[1..-1].each_with_index{ |step, index|
          step.info.travel_distance = info[index]&.first
        }

        info
      end

      def route_info(vrp)
        previous = nil
        info = nil
        segments = steps.reverse.collect{ |step|
          current =
            if step.type == :rest
              previous
            else
              step.activity.point
            end
          segment =
            if previous && current
              [current.location.lat, current.location.lon, previous.location.lat, previous.location.lon]
            end
          previous = current
          segment
        }.reverse.compact

        unless segments.empty?
          info = OptimizerWrapper.router.compute_batch(OptimizerWrapper.config[:router][:url],
                                                          vehicle.router_mode.to_sym, vehicle.router_dimension,
                                                          segments, vrp.restitution_geometry.include?(:encoded_polylines),
                                                          vehicle.router_options)
          raise RouterError.new('Route info cannot be received') unless info
        end

        info&.each{ |d| d[0] = (d[0] / 1000.0).round(4) if d[0] }
        info
      end
    end
  end
end
