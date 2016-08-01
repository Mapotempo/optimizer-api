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
require 'thread'

module Wrappers
  class Ortools < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_ortools = hash[:exec_ortools] || '../mapotempo-optimizer/optimizer/tsp_simple'
      @optimize_time = hash[:optimize_time]
      @resolution_stable_iterations = hash[:optimize_time]

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [
        :assert_end_optimization,
        :assert_vehicles_only_one,
        :assert_vehicles_no_timewindows,
        :assert_services_no_skills,
        :assert_services_no_multiple_timewindows,
        :assert_services_no_exclusion_cost,
        :assert_no_shipments,
        :assert_ortools_uniq_late_multiplier,
      ]
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
        (vehicle.end_point ? [points[vehicle.end_point_id].matrix_index] : [])

      quantities = vrp.services.collect(&:quantities) # Not used
      matrix = vrp.matrix(matrix_indices, vehicle.cost_time_multiplier, vehicle.cost_distance_multiplier)

      if !vehicle.start_point
        matrix_indices = [0] + matrix_indices.collect{ |i| i + 1 }
        matrix = [[0] * matrix.length] + matrix
        matrix.collect!{ |x| [0] + x }
      end

      if !vehicle.end_point
        matrix_indices << [matrix_indices.size]
        matrix += [[0] * matrix.length]
        matrix.collect!{ |x| x + [0] }
      end

      timewindows = [[nil, nil, 0]] + vrp.services.collect{ |service|
          (service.activity.timewindows.empty? ? [nil, nil] : [service.activity.timewindows[0].start, service.activity.timewindows[0].end]) + [service.activity.duration]
        }

      rest_window = vehicle.rests.collect{ |rest|
        [rest.timewindows[0].start, rest.timewindows[0].end, rest.duration]
      }

      soft_upper_bound = (!vrp.services.empty? && vrp.services[0].late_multiplier) || (!vrp.vehicles.empty? && vrp.vehicles[0].cost_late_multiplier)

      cost, result = run_ortools(quantities, matrix, timewindows, rest_window, vrp.resolution_duration, soft_upper_bound, vrp.preprocessing_prefer_short_segment, vrp.resolution_iterations_without_improvment, &block)
      return if !result

      result = result[1..-2]
      result = result.collect{ |i| i - 1 }

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
            ([vehicle.start_point && {
              point_id: vehicle.start_point.id
            }] +
            result.collect{ |i|
              if i < vrp.services.size
                {
                  point_id: vrp.services[i].activity.point.id,
                  service_id: vrp.services[i].id
#              travel_distance 0,
#              travel_start_time 0,
#              waiting_duration 0,
#              arrival_time 0,
#              departure_time 0,
#              pickup_shipments_id [:id0:],
#              delivery_shipments_id [:id0:]
                }
              else
                {
                  rest_id: vrp.rests[i - (vrp.services.size + (vehicle.start_point ? 1 : 0) + (vehicle.end_point ? 1 : 0))].id
                }
              end
            } +
            [vehicle.end_point && {
              point_id: vehicle.end_point.id
            }]).compact
        }]
      }
    end

    def kill
      @semaphore.synchronize {
        Process.kill("KILL", @thread.pid)
        @killed = true
      }
    end

    private

    def assert_end_optimization(vrp)
      vrp.resolution_duration || vrp.resolution_iterations_without_improvment
    end

    def assert_ortools_uniq_late_multiplier(vrp)
# TODO services.late_multiplier != rests.late_multiplier could be supported in tsp-simple
      late_multipliers = []
      late_multipliers |= vrp.services.collect(&:late_multiplier).compact.uniq if !vrp.services.empty?
      late_multipliers |= vrp.vehicles[0].rests.collect(&:late_multiplier).compact.uniq if vrp.vehicles[0] && !vrp.vehicles[0].rests.empty?
      late_multipliers.size <= 1
    end

    def run_ortools(quantities, matrix, timewindows, rest_window, optimize_time, soft_upper_bound, nearby, iterations_without_improvment, &block)
      input = Tempfile.new('optimize-or-tools-input', tmpdir=@tmp_dir)
      input.write("#{matrix.size}\n")
      input.write("#{rest_window.size}\n")
      input.write(matrix.collect{ |a| a.collect{ |b| [b, b].join(" ") }.join(" ") }.join("\n"))
      input.write("\n")
      input.write((timewindows + [[-2147483648, 2147483647, 0]]).collect{ |a| [a[0] ? a[0]:-2147483648, a[1]? a[1]:2147483647, a[2]].join(" ") }.join("\n"))
      input.write("\n")
      input.write(rest_window.collect{ |a| [a[0] ? a[0]:-2147483648, a[1]? a[1]:2147483647, a[2]].join(" ") }.join("\n"))
      input.write("\n")
      input.close

      cmd = [
        "cd `dirname #{@exec_ortools}` && ./`basename #{@exec_ortools}` ",
        (optimize_time || @optimize_time) && '-time_limit_in_ms ' + (optimize_time || @optimize_time).to_s,
        soft_upper_bound && '-soft_upper_bound ' + soft_upper_bound.to_s,
        nearby ? '-nearby' : nil,
        (iterations_without_improvment || @iterations_without_improvment) && '-no_solution_improvement_limit ' + (iterations_without_improvment || @iterations_without_improvment).to_s,
        "-instance_file '#{input.path}'"].compact.join(' ')
      puts cmd
      stdin, stdout_and_stderr, @thread = @semaphore.synchronize {
        Open3.popen2e(cmd) if !@killed
      }
      return if !@thread

      out = ''
      iterations = 0
      cost = nil
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        puts (@job ? @job + ' - ' : '') + line
        out = out + line
        r = /Iteration : ([0-9]+)/.match(line)
        r && (iterations = Integer(r[1]))
        r = / Cost : ([0-9.eE+]+)/.match(line)
        r && (cost = Float(r[1]))
        block.call(self, iterations, nil, cost, nil) if block
      }

      if @thread.value == 0
        cost_line = out.split("\n")[-2]
        result = out.split("\n")[-1]
        if result == 'No solution found...'
          nil
        else
          cost = if cost_line.include?('Cost: ')
            cost_line.split(' ')[-1].to_i
          end
          result = result.split(' ').collect{ |i| Integer(i) } if result
          [cost, result]
        end
      else
        out
      end
    ensure
      input && input.unlink
    end
  end
end
