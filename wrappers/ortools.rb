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

module Wrappers
  class Ortools < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_ortools = hash[:exec_ortools] || '../mapotempo-optimizer/optimizer/tsp_simple'
      @optimize_time = hash[:optimize_time] || 30000
      @soft_upper_bound = hash[:soft_upper_bound] || 3
    end

    def solve?(vrp)
      assert_vehicles_only_one(vrp) &&
      assert_vehicles_start(vrp) &&
      assert_vehicles_no_timewindows(vrp) &&
      assert_services_no_skills(vrp) &&
      assert_services_no_multiple_timewindows(vrp) &&
      assert_services_no_exclusion_cost(vrp) &&
      assert_no_shipments(vrp) &&
      assert_ortools_uniq_late_multiplier(vrp)
    end

    def solve(vrp, &block)
# FIXME Send two matrix
# FIXME Send cost coef
# FIXME or-tools can handle no edn-point itself
      vehicle = vrp.vehicles.first

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]

      matrix_indices = vrp.services.collect{ |service|
        points[service.activity.point_id].matrix_index
      }

      matrix_indices =
        (vehicle.start_point ? [points[vehicle.start_point_id].matrix_index] : []) +
        matrix_indices +
        (vehicle.end_point ? [points[vehicle.end_point_id].matrix_index] : []) +
        vehicle.rests.select{ |rest| rest.point }.collect{ |rest| points[rest.point_id].matrix_index }

      quantities = vrp.services.collect(&:quantities) # Not used
      matrix = vehicle.matrix(matrix_indices)
      if !vehicle.end_point
        matrix = matrix.collect{ |row| row + [0] } + [[0] * (matrix.size + 1)]
      end

      timewindows = [[nil, nil, 0]] + vrp.services.collect{ |service|
          (service.activity.timewindows.empty? ? [nil, nil] : [service.activity.timewindows[0].start, service.activity.timewindows[0].end]) + [service.activity.duration]
        } + vehicle.rests.select{ |rest| rest.point }.collect{ |rest|
          [rest.start, rest.end, rest.duration]
        }

      rest_window = vehicle.rests.select{ |rest| rest.point.nil? }.collect{ |rest|
        [rest.start, rest.end, rest.duration]
      }

      soft_upper_bound = vrp.services[0].late_multiplier

      result = run_ortools(quantities, matrix, timewindows, rest_window, vrp.resolution_duration, soft_upper_bound)
      return if !result

      if vehicle.start_point
        result = result[1..-1]
        result = result.collect{ |i| i - 1 }
      end
# Always an end_point, we force it at 0 cost
#      if vehicle.end_point
        result = result[0..-2]
#      end

      {
#        costs: result['solution_cost'] + vehicle.cost_fixed,
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: [{
          vehicle_id: vehicle.id,
          activities:
            [{
              point_id: vehicle.start_point ? vehicle.start_point.id : vrp.services[0].activity.point.id
            }] +
            result.collect{ |i| {
              point_id: vrp.services[i].activity.point.id,
              service_id: vrp.services[i].id
#              travel_distance 0,
#              travel_start_time 0,
#              waiting_duration 0,
#              arrival_time 0,
#              departure_time 0,
#              pickup_shipments_id [:id0:],
#              delivery_shipments_id [:id0:]
            }} +
            [{
              point_id: vehicle.end_point ? vehicle.end_point.id : vrp.services[-1].activity.point.id
            }]
        }]
      }
    end

    private

    def assert_ortools_uniq_late_multiplier(vrp)
      (vrp.services.empty? || vrp.services.collect(&:late_multiplier).uniq.size == 1) &&
      (vrp.vehicles[0].rests.empty? || vrp.vehicles[0].rests.collect(&:late_multiplier).uniq.size == 1)
# TODO check services.late_multiplier = rests.late_multiplier, or support late_multiplier in tsp-simple
    end

    def run_ortools(quantities, matrix, timewindows, rest_window, optimize_time, soft_upper_bound)
      input = Tempfile.new('optimize-or-tools-input', tmpdir=@tmp_dir)
      input.write("#{matrix.size}\n")
      input.write("#{rest_window.size}\n")
      input.write(matrix.collect{ |a| a.collect{ |b| [b, b].join(" ") }.join(" ") }.join("\n"))
      input.write("\n")
      input.write((timewindows + [[0, 2147483647, 0]]).collect{ |a| [a[0] ? a[0]:0, a[1]? a[1]:2147483647, a[2]].join(" ") }.join("\n"))
      input.write("\n")
      input.write(rest_window.collect{ |a| [a[0] ? a[0]:0, a[1]? a[1]:2147483647, a[2]].join(" ") }.join("\n"))
      input.write("\n")
      input.close

      output = Tempfile.new('optimize-or-tools-output', tmpdir=@tmp_dir)
      output.close

      cmd = "cd `dirname #{@exec_ortools}` && ./`basename #{@exec_ortools}` -time_limit_in_ms #{optimize_time || @optimize_time} -soft_upper_bound #{soft_upper_bound || @soft_upper_bound} -instance_file '#{input.path}' > '#{output.path}'"
      system(cmd)

      if $?.exitstatus == 0
        result = File.read(output.path)
        result = result.split("\n")[-1]
        puts result.inspect
        result.split(' ').collect{ |i| Integer(i) } if result
      end
    ensure
      input && input.unlink
      output && output.unlink
    end
  end
end
