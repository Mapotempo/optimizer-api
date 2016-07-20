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
      @vroom_exec_count = hash[:vroom_exec_count] || 3
    end

    def solver_constraints
      super + [
        :assert_vehicles_only_one,
        :assert_vehicles_no_timewindows,
        :assert_vehicles_no_rests,
        :assert_services_no_quantities,
        :assert_services_no_skills,
        :assert_services_no_timewindows,
        :assert_services_no_exclusion_cost,
        :assert_no_shipments,
        :assert_vroom_not_start_and_end,
      ]
    end

    def solve_synchronous?(vrp)
      true
    end

    def solve(vrp, &block)
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
      vehicle_loop = vehicle.start_point_id == vehicle.end_point_id

      matrix_indices =
        (vehicle_have_start ? [points[vehicle.start_point_id].matrix_index] : []) +
        matrix_indices +
        (!vehicle_loop && vehicle_have_end ? [points[vehicle.end_point_id].matrix_index] : [])

      matrix = vrp.matrix(matrix_indices, vehicle.cost_time_multiplier, vehicle.cost_distance_multiplier)

      if vrp.preprocessing_prefer_short_segment
        matrix = matrix.collect{ |a| a.collect{ |b| (b + 20 * Math.sqrt(b)).round } }
      end

      result = run_vroom(vehicle_have_start, vehicle_have_end, matrix, @vroom_exec_count) { |avancement, total|
        block.call(self, avancement, total, nil, nil) if block
      }
      return if !result

      if vehicle_loop
        index = result['tour'].index(0)
        result['tour'] = result['tour'].rotate(index)
      end

      if vehicle_loop || vehicle_have_start
        result['tour'] = result['tour'][1..-1]
      else
        result['tour'] = result['tour'].collect{ |i| i + 1 }
      end

      if !vehicle_loop && vehicle_have_end
        result['tour'] = result['tour'][0..-2]
      end

      {
        cost: result['solution_cost'] + vehicle.cost_fixed,
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: [{
          vehicle_id: vehicle.id,
          activities:
            [{
              point_id: vehicle_have_start ? vehicle.start_point.id : vrp.services[result['tour'][0] - 1].activity.point.id
            }] +
            result['tour'].collect{ |i| {
              point_id: vrp.services[i - 1].activity.point.id,
              service_id: vrp.services[i - 1].id
#              travel_distance 0,
#              travel_start_time 0,
#              waiting_duration 0,
#              arrival_time 0,
#              duration 0,
#              pickup_shipments_id [:id0:],
#              delivery_shipments_id [:id0:]
            }} +
            [{
              point_id: vehicle_have_end ? vehicle.end_point.id : !vehicle_loop ? vrp.services[result['tour'][-1] - 1].activity.point.id : vrp.services[result['tour'][0] - 1].activity.point.id
            }]
        }]
      }
    end

    private

    def assert_vroom_not_start_and_end(vrp)
      vehicle = vrp.vehicles.first
      !vehicle ||
        (vehicle.start_point && vehicle.start_point == vehicle.end_point) ||
        (vehicle.start_point && !vehicle.end_point) ||
        (!vehicle.start_point && vehicle.end_point)
    end

    def run_vroom(have_start, have_end, matrix, count = 1)
      input = Tempfile.new('optimize-vroom-input', tmpdir=@tmp_dir)
      input.write("NAME: vroom\n")
      input.write("TYPE: ATSP\n")
      input.write("DIMENSION: #{matrix.size}\n")
      input.write("EDGE_WEIGHT_TYPE: EXPLICIT\n")
      input.write("EDGE_WEIGHT_FORMAT: FULL_MATRIX\n")
      input.write("EDGE_WEIGHT_SECTION\n")
      input.write(matrix.collect{ |a| a.join(" ") }.join("\n"))
      input.write("\n")
      input.write("EOF\n")
      input.close

      output = Tempfile.new('optimize-vroom-output', tmpdir=@tmp_dir)
      output.close

      cmd = "#{@exec_vroom} -i '#{input.path}' -o '#{output.path}' #{have_start && !have_end ? '-s' : ''} #{!have_start && have_end ? '-e' : ''}"
      count.times.collect{ |i|
        puts cmd
        system(cmd)
        yield i, count

        if $?.exitstatus == 0
          JSON.parse(File.read(output.path))
        end
      }.min_by{ |json|
        json['solution_cost']
      }
    ensure
      input && input.unlink
      output && output.unlink
    end
  end
end
