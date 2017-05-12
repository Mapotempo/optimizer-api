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
        :assert_no_shipments_with_multiple_timewindows,
      ]
    end

    def solve(vrp, job, &block)
# FIXME or-tools can handle no end-point itself
      @job = job

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]

      services = vrp.services.collect{ |service|
        vehicles_indices = if vrp.services.any? { |service| service.skills == nil } && vrp.services.any? { |service| service.skills.size > 0 } &&
          vrp.vehicles.any? { |vehicle| vehicle.skills } && vrp.vehicles.none? { |vehicle| vehicle.skills && ((vehicle.skills[0] & service.skills).size == service.skills.size) }
          [-1]
        else
          vrp.vehicles.collect.with_index{ |vehicle, index|
            if !vehicle.skills.empty? && ((vehicle.skills[0] & service.skills).size == service.skills.size)
              index
            else
              nil
            end
          }.compact
        end

        OrtoolsVrp::Service.new(
          time_windows: service.activity.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
            start: tw.start || -2**56,
            end: tw.end || 2**56,
          ) },
          quantities: vrp.units.collect{ |unit|
            q = service.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (q.value*1000+0.5).to_i : 0
          },
          type: service.type.to_s,
          duration: service.activity.duration,
          priority: service.priority,
          matrix_index: points[service.activity.point_id].matrix_index,
          vehicle_indices: service.sticky_vehicles.size > 0 ? service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: service.activity.setup_duration,
          id: service.id,
          late_multiplier: service.activity.late_multiplier || 0,
        )
      } + vrp.shipments.collect{ |shipment|
        vehicles_indices = vrp.vehicles.collect.with_index{ |vehicle, index|
          if !vehicle.skills.empty? && ((vehicle.skills[0] & shipment.skills).size == shipment.skills.size)
            index
          else
            nil
          end
        }.compact
        [OrtoolsVrp::Service.new(
          time_windows: shipment.pickup.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
            start: tw.start || -2**56,
            end: tw.end || 2**56,
          ) },
          quantities: vrp.units.collect{ |unit|
            q = shipment.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (q.value*1000+0.5).to_i : 0
          },
          type: 'pickup',
          duration: shipment.pickup.duration,
          priority: shipment.priority,
          matrix_index: points[shipment.pickup.point_id].matrix_index,
          vehicle_indices: shipment.sticky_vehicles.size > 0 ? shipment.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: shipment.pickup.setup_duration,
          id: shipment.id + "pickup",
          linked_ids: [shipment.id + "delivery"],
          late_multiplier: shipment.pickup.late_multiplier || 0
        )] + [OrtoolsVrp::Service.new(
          time_windows: shipment.delivery.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
            start: tw.start || -2**56,
            end: tw.end || 2**56,
          ) },
          quantities: vrp.units.collect{ |unit|
            q = shipment.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (q.value*1000+0.5).to_i : 0
          },
          type: 'delivery',
          duration: shipment.delivery.duration,
          priority: shipment.priority,
          matrix_index: points[shipment.delivery.point_id].matrix_index,
          vehicle_indices: shipment.sticky_vehicles.size > 0 ? shipment.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: shipment.delivery.setup_duration,
          id: shipment.id + "delivery",
          late_multiplier: shipment.delivery.late_multiplier || 0
        )]
      }.flatten(1)

      matrix_indices = vrp.services.collect{ |service|
        points[service.activity.point_id].matrix_index
      } + vrp.shipments.collect{ |shipment|
        [points[shipment.pickup.point_id].matrix_index, points[shipment.delivery.point_id].matrix_index]
      }.flatten(1)

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
          cost_late_multiplier: vehicle.cost_late_multiplier || 0,
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
          ),
          rests: vehicle.rests.collect{ |rest|
            OrtoolsVrp::Rest.new(
              time_windows: rest.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
                start: tw.start || -2**56,
                end: tw.end || 2**56,
              ) },
              duration: rest.duration,
            )
          },
          matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.matrix_id },
          start_index: vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          end_index: vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
          duration: vehicle.duration ? vehicle.duration : -1,
          force_start: vehicle.force_start
        )
      }

      problem = OrtoolsVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
      )

      cost, iterations, result = run_ortools(problem, vrp, services, points, matrix_indices, &block)
      return if !result

      parse_output(vrp, services, points, matrix_indices, cost, iterations, result)
    end

    def closest_rest_start(timewindows, current_start)
      timewindows.size == 0 || timewindows.one?{ |tw| current_start >= tw[:start] && current_start <= tw[:end] } ? current_start :
        timewindows.sort_by { |tw0, tw1| tw1 ? tw0[:start] < tw1[:start] : tw0 }.find{ |tw| tw[:start] > current_start }[:start]
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

    def parse_output(vrp, services, points, matrix_indices, cost, iterations, result)
      result = result.split(';').collect{ |r| r.split(',').collect{ |i| i.scan(/[0-9]+/).collect{ |j| Integer(j) } }[1..-2] }

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
          route_start = vehicle.timewindow && vehicle.timewindow[:start] ? vehicle.timewindow[:start] : 0
          earliest_start = route_start
          {
          vehicle_id: vehicle.id,
          activities:
            ([if vehicle.start_point
              previous = points[vehicle.start_point.id].matrix_index
              {
                point_id: vehicle.start_point.id
              }
            else
              nil
            end] +
            route.collect{ |i|
              if i.first < matrix_indices.size + 2
                if i.first < vrp.services.size
                  point = services[i.first].matrix_index
                  earliest_start = i.size > 1 ? i.last : earliest_start
                  current_activity = {
                    service_id: vrp.services[i.first].id,
                    travel_time: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous][point] : 0),
                    travel_distance: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous][point] : 0),
                    begin_time: earliest_start,
                    departure_time: i.size > 1 ? earliest_start + vrp.services[i.first].activity[:duration].to_i : nil
  #              pickup_shipments_id [:id0:],
  #              delivery_shipments_id [:id0:]
                  }
                  earliest_start += vrp.services[i.first].activity[:duration].to_i
                  previous = point
                  current_activity
                else
                  shipment_index = ((i.first - vrp.services.size)/2).to_i
                  shipment_activity = (i.first - vrp.services.size)%2
                  point = services[i.first].matrix_index
                  earliest_start = i.size > 1 ? i.last : earliest_start
                  current_activity = {
                    pickup_shipment_id: shipment_activity == 0 && vrp.shipments[shipment_index].id,
                    delivery_shipment_id: shipment_activity == 1 && vrp.shipments[shipment_index].id,
                    travel_time: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous][point] : 0),
                    travel_distance: (previous && point && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous][point] : 0),
                    begin_time: earliest_start,
                    departure_time: i.size > 1 ? earliest_start + (shipment_activity == 0 ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i ): nil
  #              pickup_shipments_id [:id0:],
  #              delivery_shipments_id [:id0:]
                  }
                  earliest_start += shipment_activity == 0 ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i
                  previous = point
                  current_activity
                end
              else
                earliest_start = closest_rest_start(vrp.rests[i.first - matrix_indices.size - 2][:timewindows], earliest_start)
                current_rest = {
                  rest_id: vrp.rests[i.first - matrix_indices.size - 2].id,
                  begin_time: earliest_start,
                  departure_time: earliest_start + vrp.rests[i.first - matrix_indices.size - 2][:duration]
                }
                earliest_start += vrp.rests[i.first - matrix_indices.size - 2][:duration]
                current_rest
              end
            } +
            [vehicle.end_point && {
              point_id: vehicle.end_point.id
            }]).compact
        }},
        unassigned: (vrp.services.collect(&:id) - result.flatten(1).collect{ |i| i.first < vrp.services.size && vrp.services[i.first].id }).collect{ |service_id| {service_id: service_id} }
      }
    end

    def run_ortools(problem, vrp, services, points, matrix_indices, &block)
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
        vrp.resolution_vehicle_limit ? "-vehicle_limit #{vrp.resolution_vehicle_limit}" : nil,
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
        r = /(([0-9]+(,[0-9]+(\[[0-9]+\])*)*;)+)+/.match(line)
        block.call(self, iterations, nil, cost, r && parse_output(vrp, services, points, matrix_indices, cost, iterations, r[1])) if block
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
