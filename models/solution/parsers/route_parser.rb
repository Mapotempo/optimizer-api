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

module Parsers
  class RouteParser
    def self.parse(route, vrp, matrix, options = {})
      return if route.steps.empty?

      @route = route

      compute_missing_dimensions(matrix) if options[:compute_dimensions]
      compute_route_waiting_times
      route_data = compute_route_travel_distances(vrp, matrix)
      compute_total_time
      compute_route_waiting_times unless @route.steps.empty?
      compute_route_total_dimensions(matrix)
      return unless ([:polylines, :encoded_polylines] & vrp.restitution_geometry).any? &&
                    @route.steps.any?(&:service_id)

      route_data ||= route_info(vrp)
      @route.geometry = route_data&.map(&:last)
      @route
    end

    def self.compute_total_time
      return if @route.steps.empty?

      @route.info.end_time = @route.steps.last.info.end_time || @route.steps.last.info.begin_time
      @route.info.start_time = @route.steps.first.info.begin_time
      return unless @route.info.end_time && @route.info.start_time

      @route.info.total_time = @route.info.end_time - @route.info.start_time
    end

    def self.compute_route_total_dimensions(matrix)
      previous_index = nil
      dimensions = []
      dimensions << :time if matrix&.time
      dimensions << :distance if matrix&.distance
      dimensions << :value if matrix&.value

      total = dimensions.collect.with_object({}) { |dimension, hash| hash[dimension] = 0 }
      @route.steps.each{ |step_object|
        matrix_index = step_object.activity.point&.matrix_index
        dimensions.each{ |dimension|
          if previous_index && matrix_index
            unless step_object.info.send("travel_#{dimension}".to_sym)
              step_object.info.send("travel_#{dimension}=", matrix.send(dimension)[previous_index][matrix_index])
            end
            total[dimension] += step_object.info.send("travel_#{dimension}".to_sym).round
            step_object.info.current_distance = total[dimension].round if dimension == :distance
          else
            step_object.info.send("travel_#{dimension}=", 0)
          end
        }

        previous_index = matrix_index if step_object.type != :rest
      }

      if @route.info.end_time && @route.info.start_time
        @route.info.total_time = @route.info.end_time - @route.info.start_time
      end
      @route.info.total_travel_time = total[:time].round if dimensions.include?(:time)
      @route.info.total_distance = total[:distance].round if dimensions.include?(:distance)
      @route.info.total_travel_value = total[:value].round if dimensions.include?(:value)

      return unless @route.steps.all?{ |a| a.info.waiting_time }

      @route.info.total_waiting_time = @route.steps.collect{ |a| a.info.waiting_time }.sum.round
    end

    def self.compute_missing_dimensions(matrix)
      dimensions = %i[time distance value]
      dimensions.each{ |dimension|
        next unless matrix&.send(dimension)&.any?

        next if @route.steps.any?{ |step|
          step.info.send("travel_#{dimension}") && step.info.send("travel_#{dimension}") > 0
        }

        previous_departure = dimension == :time ? @route.steps.first.info.begin_time : 0
        previous_index = nil
        @route.steps.each{ |step|
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

    def self.compute_time_info(step_object, previous_departure, travel_time)
      earliest_arrival =
        [
          step_object.activity.timewindows&.find{ |tw| (tw.end || 2**32) > previous_departure }&.start || 0,
          previous_departure + travel_time
        ].max || 0
      if travel_time > 0
        earliest_arrival += step_object.activity.setup_duration * @route.vehicle.coef_setup + @route.vehicle.additional_setup
      end
      step_object.info.begin_time = earliest_arrival
      step_object.info.end_time = earliest_arrival +
        (step_object.activity.duration * @route.vehicle.coef_service + @route.vehicle.additional_service)
      step_object.info.departure_time = step_object.info.end_time
      earliest_arrival
    end

    def self.compute_route_waiting_times
      return if @route.steps.empty?

      previous_end = @route.steps.first.info.begin_time
      loc_index = nil
      consumed_travel_time = 0
      consumed_setup_time = 0
      @route.steps.each.with_index{ |step_object, index|
        used_travel_time = 0
        if step_object.type == :rest
          if loc_index.nil?
            next_index = @route.steps[index..-1].index{ |a| a.type != :rest }
            loc_index = index + next_index if next_index
            consumed_travel_time = 0
          end
          shared_travel_time = loc_index && @route.steps[loc_index].info.travel_time || 0
          potential_setup = shared_travel_time > 0 && @route.steps[loc_index].activity.setup_duration || 0
          left_travel_time = shared_travel_time - consumed_travel_time
          used_travel_time = [step_object.info.begin_time - previous_end, left_travel_time].min
          consumed_travel_time += used_travel_time
          # As setup is considered as a transit value, it may be performed before a rest
          consumed_setup_time  += [step_object.info.begin_time - previous_end - used_travel_time, potential_setup].min
        else
          used_travel_time = (step_object.info.travel_time || 0) - consumed_travel_time - consumed_setup_time
          consumed_travel_time = 0
          consumed_setup_time = 0
          loc_index = nil
        end
        considered_setup = step_object.info.travel_time&.positive? &&
                           (step_object.activity.setup_duration.to_i - consumed_setup_time) || 0
        arrival_time = previous_end + used_travel_time + considered_setup + consumed_setup_time
        step_object.info.waiting_time = step_object.info.begin_time - arrival_time
        previous_end = step_object.info.end_time || step_object.info.begin_time
      }
    end

    def self.compute_route_travel_distances(vrp, matrix)
      return nil unless matrix&.distance.nil? && @route.steps.size > 1 &&
                        @route.steps.reject{ |act| act.type == :rest }.all?{ |act| act.activity.point.location }

      info = route_info(vrp)

      return nil unless info && !info.empty?

      @route.steps[1..-1].each_with_index{ |step, index|
        step.info.travel_distance = info[index]&.first
      }

      info
    end

    def self.route_info(vrp)
      previous = nil
      info = nil
      segments = @route.steps.reverse.collect{ |step|
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
        info = vrp.router.compute_batch(OptimizerWrapper.config[:router][:url],
                                                     @route.vehicle.router_mode.to_sym, @route.vehicle.router_dimension,
                                                     segments, vrp.restitution_geometry.include?(:encoded_polylines),
                                                     @route.vehicle.router_options)
        raise RouterError.new('Route info cannot be received') unless info
      end

      info&.each{ |d| d[0] = (d[0] / 1000.0).round(4) if d[0] }
      info
    end
  end
end
