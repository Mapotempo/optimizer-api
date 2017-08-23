# Copyright © Mapotempo, 2016
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
require './wrappers/wrapper'

require 'json'
require 'tempfile'


module Wrappers
  class Vroom < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_vroom = hash[:exec_vroom] || '../vroom/bin/vroom'
    end

    def solver_constraints
      super + [
        :assert_vehicles_only_one,
        :assert_vehicles_start_or_end,
        :assert_vehicles_no_end_time_or_late_multiplier,
        :assert_services_no_capacities,
        :assert_services_no_skills,
        :assert_services_no_timewindows,
        :assert_services_no_priority,
        :assert_no_shipments,
        :assert_matrices_only_one,
        :assert_one_vehicle_only_or_no_sticky_vehicle,
        :assert_no_relations,
        :assert_vehicles_no_duration_limit,
        :assert_no_value_matrix
      ]
    end

    def solve_synchronous?(vrp)
      true
    end

    def solve(vrp, job = nil, thread_proc = nil, &block)
      if vrp.points.empty? || vrp.services.empty?
        return
      end

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]

      matrix_indices = vrp.services.collect{ |service|
        points[service.activity.point_id].matrix_index
      }

      vehicle = vrp.vehicles.first
      vehicle_have_start = !vehicle.start_point_id.nil?
      vehicle_have_end = !vehicle.end_point_id.nil?
      vehicle_loop = vehicle.start_point_id == vehicle.end_point_id ||
        (vehicle.start_point && vehicle.end_point && vehicle.start_point.location && vehicle.end_point.location && vehicle.start_point.location.lat == vehicle.end_point.location.lat && vehicle.start_point.location.lon == vehicle.end_point.location.lon)

      matrix_indices =
        (vehicle_have_start ? [points[vehicle.start_point_id].matrix_index] : []) +
        matrix_indices +
        (!vehicle_loop && vehicle_have_end ? [points[vehicle.end_point_id].matrix_index] : [])

      matrix = vehicle.matrix_blend(vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }, matrix_indices, [:time, :distance], {cost_time_multiplier: vehicle.cost_time_multiplier, cost_distance_multiplier: vehicle.cost_distance_multiplier})

      if vrp.preprocessing_prefer_short_segment
        matrix = matrix.collect{ |a| a.collect{ |b| (b + 20 * Math.sqrt(b)).round } }
      end

      result = run_vroom(vehicle_have_start, vehicle_have_end, vehicle_loop, matrix) { |avancement, total|
        block.call(self, avancement, total, nil, nil) if block
      }
      return if !result

      tour = result['routes'][0]['steps'].collect{ |step| step['job'] }
      puts tour.inspect

      if vehicle_loop
        index = tour.index(0)
        tour = tour.rotate(index)
      end

      if vehicle_loop || vehicle_have_start
        tour = tour[1..-1]
      else
        tour = tour.collect{ |i| i + 1 }
      end

      if vehicle_loop || vehicle_have_end
        tour = tour[0..-2]
      end

      cost = (result['solution']['cost'] / 100) + vehicle.cost_fixed
      block.call(self, 1, 1, cost, nil) if block
      previous = vehicle_have_start ? vehicle.start_point.matrix_index : nil
      activities = ([vehicle_have_start ? {
          point_id: vehicle.start_point.id
        } : nil] +
        tour.collect{ |i|
          point = vrp.services[i - 1].activity.point[:matrix_index]
          current_activity = {
            service_id: vrp.services[i - 1].id,
            travel_time: (previous && point && vrp.matrices[0][:time] ? vrp.matrices[0][:time][previous][point] : 0),
            travel_distance: (previous && point && vrp.matrices[0][:distance] ? vrp.matrices[0][:distance][previous][point] : 0)
#          travel_distance 0,
#          travel_start_time 0,
#          waiting_duration 0,
#          arrival_time 0,
#          duration 0,
#          pickup_shipments_id [:id0:],
#          delivery_shipments_id [:id0:]
          }
          previous = point
          current_activity
        } +
        [vehicle_have_end ? {
          point_id: vehicle.end_point.id
        } : nil]).compact

      rests = vehicle.rests
      if vehicle.timewindow && vehicle.timewindow.start
        rests.sort_by!{ |rest| rest.timewindows[0].end ? -rest.timewindows[0].end : -2**31 }.each{ |rest|
          time = vehicle.timewindow.start + vrp.services[tour[0]-1].activity.duration
          i = pos_rest = 0
          if vehicle_have_start
            time += vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.time[vehicle.start_point.matrix_index][vrp.services[tour[0]-1].activity.point.matrix_index]
            pos_rest += 1
          end
          if !rest.timewindows[0].end || time < rest.timewindows[0].end
            pos_rest += 1
            while i < tour.size - 1 && (!rest.timewindows[0].end || (time += vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.time[vrp.services[tour[i]-1].activity.point.matrix_index][vrp.services[tour[i+1]-1].activity.point.matrix_index] + vrp.services[tour[i+1]-1].activity.duration) < rest.timewindows[0].end) do
              i += 1
            end
            pos_rest += i
          end
          activities.insert(pos_rest, {rest_id: rest.id})
        }
      else
        rests.each{ |rest| activities.insert(vehicle_have_end ? -2 : -1, {rest_id: rest.id}) }
      end

      {
        cost: cost,
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: [{
          vehicle_id: vehicle.id,
          activities: activities
        }]
      }
    end

    private

    def assert_vehicles_no_end_time_or_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.all?{ |vehicle|
        !vehicle.timewindow || (vehicle.cost_late_multiplier && vehicle.cost_late_multiplier > 0)
      }
    end

    def run_vroom(have_start, have_end, is_loop, matrix)
      input = Tempfile.new('optimize-vroom-input', tmpdir=@tmp_dir)
      input.write("NAME: vroom\n")
      input.write("TYPE: ATSP\n")
      if !is_loop
        input.write("START: #{0}\n") if have_start
        input.write("END: #{matrix.size - 1}\n") if have_end
      end
      input.write("DIMENSION: #{matrix.size}\n")
      input.write("EDGE_WEIGHT_TYPE: EXPLICIT\n")
      input.write("EDGE_WEIGHT_FORMAT: FULL_MATRIX\n")
      input.write("EDGE_WEIGHT_SECTION\n")
      input.write(matrix.collect{ |a| a.collect{ |f| (f * 100).to_i }.join(" ") }.join("\n"))
      input.write("\n")
      input.write("EOF\n")
      input.close

      output = Tempfile.new('optimize-vroom-output', tmpdir=@tmp_dir)
      output.close

      cmd = "#{@exec_vroom} -i '#{input.path}' -o '#{output.path}'"
      puts cmd
      system(cmd)

      if $?.exitstatus == 0
        JSON.parse(File.read(output.path))
      end
    ensure
      input && input.unlink
      output && output.unlink
    end
  end
end
