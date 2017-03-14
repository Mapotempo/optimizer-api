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
require './wrappers/ortools_vrp_pb'

require 'open3'
require 'thread'

module Wrappers
  class Ortools < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_ortools = hash[:exec_ortools] || 'LD_LIBRARY_PATH=../or-tools/dependencies/install/lib/:../or-tools/lib/ ../optimizer-ortools/tsp_simple'
      @optimize_time = hash[:optimize_time]
      @resolution_stable_iterations = hash[:optimize_time]

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [
        :assert_end_optimization,
        :assert_vehicles_no_capacity_initial,
        :assert_vehicles_no_alternative_skills,
        :assert_services_at_most_two_timewindows,
        :assert_no_shipments,
      ]
    end

    def solve(vrp, job, &block)
# FIXME or-tools can handle no end-point itself
      @job = job

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]

      services = vrp.services.collect{ |service|
        vehicles_indices = vrp.vehicles.collect.with_index{ |vehicle, index|
          if !vehicle.skills.empty? && ((vehicle.skills[0] & service.skills).size == service.skills.size)
            index
          else
            nil
          end
        }.compact

        OrtoolsVrp::Service.new(
          time_windows: service.activity.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
            start: tw.start || -2**56,
            end: tw.end || 2**56,
            late_multiplier: service.late_multiplier || 0,
          ) },
          quantities: vrp.units.collect{ |unit|
            q = service.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (q.value*1000+0.5).to_i : 0
          },
          duration: service.activity.duration,
          priority: service.priority,
          matrix_index: points[service.activity.point_id].matrix_index,
          vehicle_indices: service.sticky_vehicles.size > 0 ? service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: service.activity.setup_duration
        )
      }

      matrix_indices = vrp.services.collect{ |service|
        points[service.activity.point_id].matrix_index
      }

      matrices = vrp.matrices.collect{ |matrix|
        OrtoolsVrp::Matrix.new(
          time: matrix[:time] ? matrix[:time].flatten : [],
          distance: matrix[:distance] ? matrix[:distance].flatten : []
        )
      }
      vehicles = vrp.vehicles.collect{ |vehicle|
        OrtoolsVrp::Vehicle.new(
          cost_fixed: vehicle.cost_fixed,
          cost_distance_multiplier: vehicle.cost_distance_multiplier,
          cost_time_multiplier: vehicle.cost_time_multiplier,
          cost_waiting_time_multiplier: vehicle.cost_waiting_time_multiplier,
          capacities: vrp.units.collect{ |unit|
            q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
            OrtoolsVrp::Capacity.new(
              limit: q && q.limit ? (q.limit*1000+0.5).to_i : -2147483648,
              overload_multiplier: (q && q.overload_multiplier) || 0,
            )
          },
          time_window: OrtoolsVrp::TimeWindow.new(
            start: (vehicle.timewindow && vehicle.timewindow.start) || 0,
            end: (vehicle.timewindow && vehicle.timewindow.end) || 2147483647,
            late_multiplier: vehicle.cost_late_multiplier || 0,
          ),
          rests: vehicle.rests.collect{ |rest|
            OrtoolsVrp::Rest.new(
              time_windows: rest.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
                start: tw.start || -2**56,
                end: tw.end || 2**56,
                late_multiplier: rest.late_multiplier || 0,
              ) },
              duration: rest.duration,
            )
          },
          matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.matrix_id },
          start_index: vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          end_index: vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
        )
      }

      problem = OrtoolsVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
      )

      cost, iterations, result = run_ortools(problem, vrp, &block)
      return if !result

      result = result.collect{ |r| r[1..-2] }

      {
        cost: cost,
        iterations: iterations,
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: result.each_with_index.collect{ |route, index|
          vehicle = vrp.vehicles[index]
          previous = nil
          {
          vehicle_id: vehicle.id,
          activities:
            ([vehicle.start_point && {
              point_id: vehicle.start_point.id
            }] +
            route.collect{ |i|
              if i < matrix_indices.size + 2
                point = services[i].matrix_index
                current_activity = {
                  service_id: vrp.services[i].id,
                  travel_time: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous][point] : 0),
                  travel_distance: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous][point] : 0)
#              travel_distance 0,
#              travel_start_time 0,
#              waiting_duration 0,
#              arrival_time 0,
#              departure_time 0,
#              pickup_shipments_id [:id0:],
#              delivery_shipments_id [:id0:]
                }
                previous = point
                current_activity
              else
                {
                  rest_id: vrp.rests[i - matrix_indices.size - 2].id
                }
              end
            } +
            [vehicle.end_point && {
              point_id: vehicle.end_point.id
            }]).compact
        }},
        unassigned: (vrp.services.collect(&:id) - result.flatten.collect{ |i| i < vrp.services.size && vrp.services[i].id }).collect{ |service_id| {service_id: service_id} }
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

    def run_ortools(problem, vrp, &block)
      input = Tempfile.new('optimize-or-tools-input', tmpdir=@tmp_dir)
      input.write(OrtoolsVrp::Problem.encode(problem))
      input.close

      cmd = [
        "#{@exec_ortools} ",
        (vrp.resolution_duration || @optimize_time) && '-time_limit_in_ms ' + (vrp.resolution_duration || @optimize_time).to_s,
        vrp.preprocessing_prefer_short_segment ? '-nearby' : nil,
        (vrp.resolution_iterations_without_improvment || @iterations_without_improvment) && '-no_solution_improvement_limit ' + (vrp.resolution_iterations_without_improvment || @iterations_without_improvment).to_s,
        (vrp.resolution_initial_time_out || @initial_time_out) && '-initial_time_out_no_solution_improvement ' + (vrp.resolution_initial_time_out || @initial_time_out).to_s,
        (vrp.resolution_time_out_multiplier || @time_out_multiplier) && '-time_out_multiplier ' + (vrp.resolution_time_out_multiplier || @time_out_multiplier).to_s,
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
          cost = if cost_line.include?('Cost : ')
            cost_line.split(' ')[-4].to_i
          end
          iterations = if cost_line.include?('Final Iteration : ')
            cost_line.split(' ')[3].to_i
          end
          result = result.split(';').collect{ |r| r.split(',').collect{ |i| Integer(i) } }.select{ |r| r.size > 0 } if result
          [cost, iterations, result]
        end
      else
        out
      end
    ensure
      input && input.unlink
    end
  end
end
