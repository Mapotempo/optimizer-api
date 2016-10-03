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
        :assert_vehicles_no_end_time_or_late_multiplier,
        :assert_vehicles_no_rests,
        :assert_services_no_quantities,
        :assert_services_no_skills,
        :assert_services_no_timewindows,
        :assert_services_no_exclusion_cost,
        :assert_no_shipments,
        :assert_vroom_not_start_and_end,
        :assert_matrices_only_one,
        :assert_one_vehicle_only_or_no_sticky_vehicle
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

      matrix = vehicle.matrix_blend(matrix_indices, [:time, :distance])

      if vrp.preprocessing_prefer_short_segment
        matrix = matrix.collect{ |a| a.collect{ |b| (b + 20 * Math.sqrt(b)).round } }
      end

      result = run_vroom(vehicle_have_start, vehicle_have_end, matrix) { |avancement, total|
        block.call(self, avancement, total, nil, nil) if block
      }
      return if !result

      tour = result['routes'][0]['steps'].collect{ |step| step['job'] }

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

      {
        cost: cost,
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: [{
          vehicle_id: vehicle.id,
          activities:
            ([vehicle_have_start ? {
              point_id: vehicle.start_point.id
            } : nil] +
            tour.collect{ |i| {
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
            [vehicle_have_end ? {
              point_id: vehicle.end_point.id
            } : nil]).compact
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

    def assert_vehicles_no_end_time_or_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.all?{ |vehicle|
        !vehicle.timewindow || (vehicle.cost_late_multiplier && vehicle.cost_late_multiplier > 0)
      }
    end

    def run_vroom(have_start, have_end, matrix)
      input = Tempfile.new('optimize-vroom-input', tmpdir=@tmp_dir)
      input.write("NAME: vroom\n")
      input.write("TYPE: ATSP\n")
      if !have_end || !have_start
        input.write("OPEN_TRIP: TRUE\n")
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
