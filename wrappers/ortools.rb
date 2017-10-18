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
        :assert_vehicles_at_least_one,
        :assert_vehicles_no_capacity_initial,
        :assert_vehicles_no_alternative_skills,
        :assert_no_shipments_with_multiple_timewindows,
        :assert_zones_only_size_one_alternative
      ]
    end

    def solve(vrp, job, thread_proc = nil, &block)
# FIXME or-tools can handle no end-point itself
      @job = job

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]
      relations = []

      services = vrp.services.collect{ |service|
        vehicles_indices = if !service[:skills].empty? && (vrp.vehicles.all? { |vehicle| vehicle.skills.empty? })
          [-1]
        else
          vrp.vehicles.collect.with_index{ |vehicle, index|
            if service.skills.empty? || !vehicle.skills.empty? && ((vehicle.skills[0] & service.skills).size == service.skills.size)
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
            q && q.value ? (service.type.to_s == "delivery" ? -1 : 1) * (q.value*(unit.counting ? 1 : 1000)+0.5).to_i : 0
          },
          duration: service.activity.duration,
          additional_value: service.activity.additional_value,
          priority: service.priority,
          matrix_index: points[service.activity.point_id].matrix_index,
          vehicle_indices: service.sticky_vehicles.size > 0 ? service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: service.activity.setup_duration,
          id: service.id,
          late_multiplier: service.activity.late_multiplier || 0,
          setup_quantities: vrp.units.collect{ |unit|
            q = service.quantities.find{ |quantity| quantity.unit == unit }
            q && q.setup_value && unit.counting ? (q.setup_value).to_i : 0
          },
        )
      } + vrp.shipments.collect{ |shipment|
        vehicles_indices = if !shipment[:skills].empty? && (vrp.vehicles.all? { |vehicle| vehicle.skills.empty? })
          [-1]
        else
          vrp.vehicles.collect.with_index{ |vehicle, index|
            if shipment.skills.empty? || !vehicle.skills.empty? && ((vehicle.skills[0] & shipment.skills).size == shipment.skills.size)
              index
            else
              nil
            end
          }.compact
        end
        relations <<  OrtoolsVrp::Relation.new(
          type: "shipment",
          linked_ids: [shipment.id + "pickup", shipment.id + "delivery"],
          lapse: -1
        )
        [OrtoolsVrp::Service.new(
          time_windows: shipment.pickup.timewindows.collect{ |tw| OrtoolsVrp::TimeWindow.new(
            start: tw.start || -2**56,
            end: tw.end || 2**56,
          ) },
          quantities: vrp.units.collect{ |unit|
            q = shipment.quantities.find{ |quantity| quantity.unit == unit }
            q && q.value ? (q.value*1000+0.5).to_i : 0
          },
          duration: shipment.pickup.duration,
          additional_value: shipment.pickup.additional_value,
          priority: shipment.priority,
          matrix_index: points[shipment.pickup.point_id].matrix_index,
          vehicle_indices: shipment.sticky_vehicles.size > 0 ? shipment.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) } : vehicles_indices,
          setup_duration: shipment.pickup.setup_duration,
          id: shipment.id + "pickup",
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
          duration: shipment.delivery.duration,
          additional_value: shipment.delivery.additional_value,
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
          distance: matrix[:distance] ? matrix[:distance].flatten : [],
          value: matrix[:value] ? matrix[:value].flatten : []
        )
      }
      vehicles = vrp.vehicles.collect{ |vehicle|
        OrtoolsVrp::Vehicle.new(
          cost_fixed: vehicle.cost_fixed,
          cost_distance_multiplier: vehicle.cost_distance_multiplier,
          cost_time_multiplier: vehicle.cost_time_multiplier,
          cost_waiting_time_multiplier: vehicle.cost_waiting_time_multiplier,
          cost_value_multiplier: vehicle.cost_value_multiplier || 0,
          cost_late_multiplier: vehicle.cost_late_multiplier || 0,
          capacities: vrp.units.collect{ |unit|
            q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
            OrtoolsVrp::Capacity.new(
              limit: q && q.limit ? unit.counting ? q.limit : (q.limit*1000+0.5).to_i : -2147483648,
              overload_multiplier: (q && q.overload_multiplier) || 0,
              counting: (unit && unit.counting) || false
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
          value_matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.value_matrix_id } || 0,
          start_index: vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          end_index: vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
          duration: vehicle.duration ? vehicle.duration : -1,
          force_start: vehicle.force_start,
          day_index: vehicle.global_day_index ? vehicle.global_day_index : -1
        )
      }

      relations += vrp.relations.collect{ |relation|
        OrtoolsVrp::Relation.new(
          type: relation.type.to_s,
          linked_ids: relation.linked_ids || [],
          lapse: relation.lapse || -1
        )
      }

      problem = OrtoolsVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
        relations: relations
      )
      ret = run_ortools(problem, vrp, services, points, matrix_indices, thread_proc, &block)
      case ret
      when String
        return ret
      when Array
        cost, iterations, result = ret
      else
        return ret
      end

      parse_output(vrp, services, points, matrix_indices, cost, iterations, result)
    end

    def closest_rest_start(timewindows, current_start)
      timewindows.size == 0 || timewindows.one?{ |tw| current_start >= tw[:start] && current_start <= tw[:end] } ? current_start :
        timewindows.sort_by { |tw0, tw1| tw1 ? tw0[:start] < tw1[:start] : tw0 }.find{ |tw| tw[:start] > current_start }[:start]
    end

    def kill
      @killed = true
    end

    private

    def build_timewindows(activity, day_index)
      activity.timewindows.select{ |timewindow| timewindow.day_index.nil? || timewindow.day_index == day_index}.collect{ |timewindow|
        {
          start: timewindow.start,
          end: timewindow.end
        }
      }
    end

    def build_quantities(job)
      job.quantities.collect{ |quantity|
        if quantity.unit
          {
            unit: quantity.unit,
            value: quantity.value,
            setup_value: quantity.unit.counting ? quantity.setup_value : 0
          }
        end
      }.compact
    end

    def build_rest(rest, day_index)
      {
        duration: rest.duration,
        timewindows: build_timewindows(rest, day_index)
      }
    end

    def build_detail(job, activity, point, day_index)
      {
        lat: point && point.location && point.location.lat,
        lon: point && point.location && point.location.lon,
        skills: job.skills,
        setup_duration: activity.setup_duration,
        duration: activity.duration,
        additional_value: activity.additional_value,
        timewindows: build_timewindows(activity, day_index),
        quantities: build_quantities(job)
      }.delete_if{ |k,v| !v }.compact
    end

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
              previous_index = points[vehicle.start_point.id].matrix_index
              {
                point_id: vehicle.start_point.id,
                detail: vehicle.start_point.location ? {
                  lat: vehicle.start_point.location.lat,
                  lon: vehicle.start_point.location.lon
                } : nil
              }.delete_if{ |k,v| !v }
            else
              nil
            end] +
            route.collect{ |i|
              route_rest_index = 0
              if i.first < matrix_indices.size + 2
                if i.first < vrp.services.size
                  point_index = services[i.first].matrix_index
                  point = vrp.points[point_index]
                  service = vrp.services[i.first]
                  earliest_start = i.size > 1 ? i.last : earliest_start
                  current_activity = {
                    service_id: service.id,
                    point_id: point ? point.id : nil,
                    travel_time: (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous_index][point_index] : 0),
                    travel_distance: (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous_index][point_index] : 0),
                    begin_time: earliest_start,
                    departure_time: i.size > 1 ? earliest_start + vrp.services[i.first].activity[:duration].to_i : nil,
                    detail: build_detail(service, service.activity, point, vehicle.global_day_index ? vehicle.global_day_index%7 : nil)
  #              pickup_shipments_id [:id0:],
  #              delivery_shipments_id [:id0:]
                  }
                  earliest_start += vrp.services[i.first].activity[:duration].to_i
                  previous_index = point_index
                  current_activity
                else
                  shipment_index = ((i.first - vrp.services.size)/2).to_i
                  shipment_activity = (i.first - vrp.services.size)%2
                  shipment = vrp.shipments[shipment_index]
                  point_index = services[i.first].matrix_index
                  point = vrp.points[point_index]
                  earliest_start = i.size > 1 ? i.last : earliest_start
                  current_activity = {
                    pickup_shipment_id: shipment_activity == 0 && shipment.id,
                    delivery_shipment_id: shipment_activity == 1 && shipment.id,
                    point_id: point.id,
                    travel_time: (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:time][previous_index][point_index] : 0),
                    travel_distance: (previous_index && point_index && vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance] ? vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[:distance][previous_index][point_index] : 0),
                    begin_time: earliest_start,
                    departure_time: i.size > 1 ? earliest_start + (shipment_activity == 0 ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i ): nil,
                    detail: build_detail(shipment, shipment_activity == 0 ? shipment.pickup : shipment.delivery, point, vehicle.global_day_index ? vehicle.global_day_index%7 : nil)
  #              pickup_shipments_id [:id0:],
  #              delivery_shipments_id [:id0:]
                  }.delete_if{ |k,v| !v }
                  earliest_start += shipment_activity == 0 ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i
                  previous_index = point_index
                  current_activity
                end
              else
                vehicle_rest = vehicle.rests[route_rest_index]
                earliest_start = closest_rest_start(vehicle_rest[:timewindows], earliest_start)
                current_rest = {
                  rest_id: vehicle_rest.id,
                  begin_time: earliest_start,
                  departure_time: earliest_start + vehicle_rest[:duration],
                  detail: build_rest(vehicle_rest, vehicle.global_day_index ? vehicle.global_day_index%7 : nil)
                }
                earliest_start += vehicle_rest[:duration]
                ++route_rest_index
                current_rest
              end
            } +
            [vehicle.end_point && {
              point_id: vehicle.end_point.id,
              detail: vehicle.end_point.location ? {
                lat: vehicle.end_point.location.lat,
                lon: vehicle.end_point.location.lon
              } : nil
            }.delete_if{ |k,v| !v }]).compact
        }},
        unassigned: (vrp.services.collect(&:id) - result.flatten(1).collect{ |i| i.first < vrp.services.size && vrp.services[i.first].id }).collect{ |service_id|
          service = vrp.services.find{ |service| service.id == service_id }
          {
            service_id:service_id,
            activity: build_detail(service, service.activity, service.activity.point, nil)
          }
        } + (vrp.shipments.collect(&:id) - result.flatten(1).collect{ |i| i.first >= vrp.services.size && i.first - vrp.services.size < vrp.shipments.size && vrp.shipments[i.first - vrp.services.size].id }).collect{ |shipment_id|
          shipment = vrp.shipments.find{ |shipment| shipment.id == shipment_id }
          [{
            shipment_id: "#{shipment_id}pickup",
            activity: build_detail(shipment, shipment.pickup, shipment.pickup.point, nil)
          }] << {
            shipment_id: "#{shipment_id}delivery",
            activity: build_detail(shipment, shipment.delivery, shipment.delivery.point, nil)
          }
        }.flatten
      }
    end

    def run_ortools(problem, vrp, services, points, matrix_indices, thread_proc = nil, &block)
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
        vrp.restitution_intermediate_solutions ? "-intermediate_solutions" : nil,
        "-instance_file '#{input.path}'"].compact.join(' ')
      puts cmd
      stdin, stdout_and_stderr, @thread = @semaphore.synchronize {
        Open3.popen2e(cmd) if !@killed
      }

      return if !@thread

      pipe = @semaphore.synchronize {
        IO.popen("ps -ef | grep #{@thread.pid}")
      }

      childs = pipe.readlines.map do |line|
        parts = line.split(/\s+/)
        parts[1].to_i if parts[2] == @thread.pid.to_s
      end.compact || []
      childs << @thread.pid

      if thread_proc
        thread_proc.call(childs)
      end

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

      result = out.split("\n")[-1]
      if @thread.value == 0
        cost_line = out.split("\n")[-2]
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
      elsif @thread.value == 9
        out = "Job killed"
        puts out # Keep trace in worker
        if cost && !result.include?('Iteration : ')
          [cost, iterations, result]
        else
          out
        end
      else
        raise RuntimeError.new(result)
      end
    ensure
      input && input.unlink
    end
  end
end
