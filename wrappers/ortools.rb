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
require './wrappers/ortools_result_pb'

require 'open3'
module Wrappers
  class Ortools < Wrapper
    def initialize(hash = {})
      super(hash)
      @exec_ortools = hash[:exec_ortools] || 'LD_LIBRARY_PATH=../or-tools/dependencies/install/lib/:../or-tools/lib/ ../optimizer-ortools/tsp_simple'
      @optimize_time = hash[:optimize_time]
      @resolution_stable_iterations = hash[:optimize_time]
      @previous_result = nil

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [
        :assert_end_optimization,
        :assert_vehicles_objective,
        :assert_vehicles_no_capacity_initial,
        :assert_vehicles_no_alternative_skills,
        :assert_zones_only_size_one_alternative,
        :assert_only_empty_or_fill_quantities,
        :assert_points_same_definition,
        :assert_vehicles_no_zero_duration,
        :assert_correctness_matrices_vehicles_and_points_definition,
        :assert_square_matrix,
        :assert_vehicle_tw_if_schedule,
        :assert_if_sequence_tw_then_schedule,
        :assert_if_periodic_heuristic_then_schedule,
        :assert_only_force_centroids_if_kmeans_method,
        :assert_no_scheduling_if_evaluation,
        :assert_route_if_evaluation,
        :assert_no_shipments_if_evaluation,
        :assert_wrong_vehicle_shift_preference_with_heuristic,
        :assert_no_vehicle_overall_duration_if_heuristic,
        :assert_no_vehicle_distance_if_heuristic,
        :assert_possible_to_get_distances_if_maximum_ride_distance,
        :assert_no_skills_if_heuristic,
        :assert_no_vehicle_free_approach_or_return_if_heuristic,
        :assert_no_vehicle_limit_if_heuristic,
        :assert_no_same_point_day_if_no_heuristic,
        :assert_no_allow_partial_if_no_heuristic,
        :assert_solver_if_not_periodic,
        :assert_first_solution_strategy_is_possible,
        :assert_first_solution_strategy_is_valid,
        :assert_clustering_compatible_with_scheduling_heuristic,
        :assert_lat_lon_for_partition,
        :assert_vehicle_entity_only_before_work_day,
        :assert_deprecated_partitions,
        :assert_partitions_entity,
        :assert_no_initial_centroids_with_partitions,
        :assert_valid_partitions,
        :assert_route_date_or_indice_if_periodic,
        :assert_not_too_many_visits_in_route,
        :assert_no_route_if_schedule_without_periodic_heuristic,
        # :assert_no_overall_duration, # TODO: Requires a complete rework
      ]
    end

    def solve(vrp, job, thread_proc = nil, &block)
      tic = Time.now
      order_relations = vrp.relations.select{ |relation| relation.type == 'order' }
      already_begin = order_relations.collect{ |relation| relation.linked_ids[0..-2] }.flatten
      duplicated_begins = already_begin.uniq.select{ |linked_id| already_begin.select{ |link| link == linked_id }.size > 1 }
      already_end = order_relations.collect{ |relation| relation.linked_ids[1..-1] }.flatten
      duplicated_ends = already_end.uniq.select{ |linked_id| already_end.select{ |link| link == linked_id }.size > 1 }
      if vrp.routes.empty? && order_relations.size == 1
        order_relations.select{ |relation| (relation.linked_ids[0..-2] & duplicated_begins).size == 0 && (relation.linked_ids[1..-1] & duplicated_ends).size == 0 }.each{ |relation|
          order_route = {
            vehicle: (vrp.vehicles.size == 1) ? vrp.vehicles.first : nil,
            mission_ids: relation.linked_ids
          }
          vrp.routes += [order_route]
        }
      end

      problem_units = vrp.units.collect{ |unit|
        {
          unit_id: unit.id,
          fill: false,
          empty: false
        }
      }

      vrp.services.each{ |service|
        service.quantities.each{ |quantity|
          unit_status = problem_units.find{ |unit| unit[:unit_id] == quantity.unit_id }
          unit_status[:fill] ||= quantity.fill
          unit_status[:empty] ||= quantity.empty
        }
      }
      # FIXME: or-tools can handle no end-point itself
      @job = job
      @previous_result = nil
      points = Hash[vrp.points.collect{ |point| [point.id, point] }]
      relations = []
      services = []
      services_positions = { always_first: [], always_last: [], never_first: [], never_last: [] }
      vrp.services.each_with_index{ |service, service_index|
        vehicles_indices = if !service[:skills].empty? && (vrp.vehicles.all? { |vehicle| vehicle.skills.empty? }) && service[:unavailable_visit_day_indices].empty?
          []
        else
          vrp.vehicles.collect.with_index{ |vehicle, index|
            if (service.skills.empty? || !vehicle.skills.empty? && ((vehicle.skills[0] & service.skills).size == service.skills.size) &&
            check_services_compatible_days(vrp, vehicle, service)) && (service.unavailable_visit_day_indices.empty? || !service.unavailable_visit_day_indices.include?(vehicle.global_day_index))
              index
            end
          }.compact
        end

        if service.activity
          services << OrtoolsVrp::Service.new(
            time_windows: service.activity.timewindows.collect{ |tw|
              OrtoolsVrp::TimeWindow.new(start: tw.start || -2**56, end: tw.end || 2**56)
            },
            quantities: vrp.units.collect{ |unit|
              is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              (q&.value) ? (is_empty_unit ? -1 : 1) * ((service.type.to_s == 'delivery') ? -1 : 1) * (q.value * (unit.counting ? 1 : 1000)).round : 0
            },
            duration: service.activity.duration,
            additional_value: service.activity.additional_value,
            priority: service.priority,
            matrix_index: points[service.activity.point_id].matrix_index,
            vehicle_indices: (service.sticky_vehicles.size > 0 && service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact.size > 0) ?
              service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact : vehicles_indices,
            setup_duration: service.activity.setup_duration,
            id: service.id,
            late_multiplier: service.activity.late_multiplier || 0,
            setup_quantities: vrp.units.collect{ |unit|
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              (q && q.setup_value && unit.counting) ? q.setup_value.to_i : 0
            },
            exclusion_cost: service.exclusion_cost && service.exclusion_cost.to_i || -1,
            refill_quantities: vrp.units.collect{ |unit|
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              !q.nil? && (q.fill || q.empty)
            },
            problem_index: service_index,
          )

          services = update_services_positions(services, services_positions, service.id, service.activity.position, service_index)
        elsif service.activities
          service.activities.each_with_index{ |possible_activity, activity_index|
            services << OrtoolsVrp::Service.new(
              time_windows: possible_activity.timewindows.collect{ |tw|
                OrtoolsVrp::TimeWindow.new(start: tw.start || -2**56, end: tw.end || 2**56)
              },
              quantities: vrp.units.collect{ |unit|
                is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                (q&.value) ? (is_empty_unit ? -1 : 1) * ((service.type.to_s == 'delivery') ? -1 : 1) * (q.value * (unit.counting ? 1 : 1000)).round : 0
              },
              duration: possible_activity.duration,
              additional_value: possible_activity.additional_value,
              priority: service.priority,
              matrix_index: points[possible_activity.point_id].matrix_index,
              vehicle_indices: (service.sticky_vehicles.size > 0 && service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact.size > 0) ?
                service.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact : vehicles_indices,
              setup_duration: possible_activity.setup_duration,
              id: "#{service.id}_activity#{activity_index}",
              late_multiplier: possible_activity.late_multiplier || 0,
              setup_quantities: vrp.units.collect{ |unit|
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                (q&.setup_value && unit.counting) ? q.setup_value.to_i : 0
              },
              exclusion_cost: service.exclusion_cost || -1,
              refill_quantities: vrp.units.collect{ |unit|
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                !q.nil? && (q.fill || q.empty)
              },
              problem_index: service_index,
            )

            services = update_services_positions(services, services_positions, service.id, possible_activity.position, service_index)
          }
        end
      }
      vrp.shipments.each_with_index{ |shipment, shipment_index|
        vehicles_indices = if !shipment[:skills].empty? && (vrp.vehicles.all? { |vehicle| vehicle.skills.empty? })
          []
        else
          vrp.vehicles.collect.with_index{ |vehicle, index|
            if shipment.skills.empty? ||
               !vehicle.skills.empty? && ((vehicle.skills[0] & shipment.skills).size == shipment.skills.size) && (shipment.unavailable_visit_day_indices.empty? ||
               !shipment.unavailable_visit_day_indices.include(vehicle.global_day_index))
              index
            end
          }.compact
        end
        relations << OrtoolsVrp::Relation.new(
          type: 'shipment',
          linked_ids: [shipment.id + 'pickup', shipment.id + 'delivery'],
          lapse: -1
        )
        if shipment.maximum_inroute_duration&.positive?
          relations << OrtoolsVrp::Relation.new(
            type: 'maximum_duration_lapse',
            linked_ids: [shipment.id + 'pickup', shipment.id + 'delivery'],
            lapse: shipment.maximum_inroute_duration
          )
        end
        if shipment.direct
          relations << OrtoolsVrp::Relation.new(
            type: 'sequence',
            linked_ids: [shipment.id + 'pickup', shipment.id + 'delivery']
          )
        end
        services << OrtoolsVrp::Service.new(
          time_windows: shipment.pickup.timewindows.collect{ |tw|
            OrtoolsVrp::TimeWindow.new(start: tw.start || -2**56, end: tw.end || 2**56)
          },
          quantities: vrp.units.collect{ |unit|
            is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
            q = shipment.quantities.find{ |quantity| quantity.unit == unit }
            (q && q.value) ? (is_empty_unit ? -1 : 1) * (q.value * 1000).round : 0
          },
          duration: shipment.pickup.duration,
          additional_value: shipment.pickup.additional_value,
          priority: shipment.priority,
          matrix_index: points[shipment.pickup.point_id].matrix_index,
          vehicle_indices: (shipment.sticky_vehicles.size > 0) ? shipment.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact : vehicles_indices,
          setup_duration: shipment.pickup.setup_duration,
          id: shipment.id + 'pickup',
          late_multiplier: shipment.pickup.late_multiplier || 0,
          exclusion_cost: shipment.exclusion_cost || -1,
          refill_quantities: vrp.units.collect{ |_unit| false },
          problem_index: vrp.services.size + 2 * shipment_index,
        )
        services << OrtoolsVrp::Service.new(
          time_windows: shipment.delivery.timewindows.collect{ |tw|
            OrtoolsVrp::TimeWindow.new(start: tw.start || -2**56, end: tw.end || 2**56)
          },
          quantities: vrp.units.collect{ |unit|
            is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
            q = shipment.quantities.find{ |quantity| quantity.unit == unit }
            (q&.value) ? - (is_empty_unit ? -1 : 1) * (q.value * 1000).round : 0
          },
          duration: shipment.delivery.duration,
          additional_value: shipment.delivery.additional_value,
          priority: shipment.priority,
          matrix_index: points[shipment.delivery.point_id].matrix_index,
          vehicle_indices: (!shipment.sticky_vehicles.empty?) ? shipment.sticky_vehicles.collect{ |sticky_vehicle| vrp.vehicles.index(sticky_vehicle) }.compact : vehicles_indices,
          setup_duration: shipment.delivery.setup_duration,
          id: shipment.id + 'delivery',
          late_multiplier: shipment.delivery.late_multiplier || 0,
          exclusion_cost: shipment.exclusion_cost || -1,
          refill_quantities: vrp.units.collect{ |_unit| false },
          problem_index: vrp.services.size + 2 * shipment_index + 1,
        )
      }.flatten(1)

      matrix_indices = vrp.services.collect{ |service|
        service.activity ? points[service.activity.point_id].matrix_index : service.activities.collect{ |activity| points[activity.point_id].matrix_index }
      } + vrp.shipments.flat_map{ |shipment|
        [points[shipment.pickup.point_id].matrix_index, points[shipment.delivery.point_id].matrix_index]
      }

      matrices = vrp.matrices.collect{ |matrix|
        OrtoolsVrp::Matrix.new(
          time: matrix[:time] ? matrix[:time].flatten : [],
          distance: matrix[:distance] ? matrix[:distance].flatten : [],
          value: matrix[:value] ? matrix[:value].flatten : []
        )
      }

      v_types = []
      vrp.vehicles.each{ |vehicle|
        v_type_id = [
          vehicle.cost_fixed,
          vehicle.cost_distance_multiplier,
          vehicle.cost_time_multiplier,
          vehicle.cost_waiting_time_multiplier || vehicle.cost_time_multiplier,
          vehicle.cost_value_multiplier || 0,
          vehicle.cost_late_multiplier || 0,
          vehicle.coef_service || 1,
          vehicle.coef_setup || 1,
          vehicle.additional_service || 0,
          vehicle.additional_setup || 0,
          vrp.units.collect{ |unit|
            q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
            [
              (q && q.limit && q.limit < 1e+22) ? unit.counting ? q.limit : (q.limit * 1000).round : -2147483648,
              (q && q.overload_multiplier) || 0,
              (unit && unit.counting) || false
            ]
          }.flatten.compact,
          [
            vehicle.timewindow&.start || 0,
            vehicle.timewindow&.end || 2147483647,
          ],
          vehicle.rests.collect{ |rest|
            [
              rest.timewindows.collect{ |tw|
                [
                  tw.start || -2**56,
                  end: tw.end || 2**56,
                ]
              },
              rest.duration,
            ].flatten.compact
          },
          vehicle.skills,
          vehicle.matrix_id,
          vehicle.value_matrix_id,
          vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
          vehicle.duration || -1,
          vehicle.distance || -1,
          (vehicle.force_start ? 'force_start' : vehicle.shift_preference.to_s),
          vehicle.global_day_index || -1,
          vehicle.maximum_ride_time || 0,
          vehicle.maximum_ride_distance || 0,
          vehicle.free_approach || false,
          vehicle.free_return || false
        ].flatten

        v_type_checksum = Digest::MD5.hexdigest(Marshal.dump(v_type_id))
        v_type_index = v_types.index(v_type_checksum)
        if v_type_index
          vehicle.type_index = v_type_index
        else
          vehicle.type_index = v_types.size
          v_types << v_type_checksum
        end
      }
      vehicles = vrp.vehicles.collect{ |vehicle|
        OrtoolsVrp::Vehicle.new(
          id: vehicle.id,
          cost_fixed: vehicle.cost_fixed,
          cost_distance_multiplier: vehicle.cost_distance_multiplier,
          cost_time_multiplier: vehicle.cost_time_multiplier,
          cost_waiting_time_multiplier: vehicle.cost_waiting_time_multiplier || vehicle.cost_time_multiplier,
          cost_value_multiplier: vehicle.cost_value_multiplier || 0,
          cost_late_multiplier: vehicle.cost_late_multiplier || 0,
          coef_service: vehicle.coef_service || 1,
          coef_setup: vehicle.coef_setup || 1,
          additional_service: vehicle.additional_service || 0,
          additional_setup: vehicle.additional_setup || 0,
          capacities: vrp.units.collect{ |unit|
            q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
            OrtoolsVrp::Capacity.new(
              limit: (q && q.limit && q.limit < 1e+22) ? unit.counting ? q.limit : (q.limit * 1000).round : -2147483648,
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
              time_windows: rest.timewindows.collect{ |tw|
                OrtoolsVrp::TimeWindow.new(start: tw.start || -2**56, end: tw.end || 2**56)
              },
              duration: rest.duration,
              id: rest.id,
              late_multiplier: rest.late_multiplier,
              exclusion_cost: rest.exclusion_cost || -1
            )
          },
          matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.matrix_id },
          value_matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.value_matrix_id } || 0,
          start_index: vehicle.start_point ? points[vehicle.start_point_id].matrix_index : -1,
          end_index: vehicle.end_point ? points[vehicle.end_point_id].matrix_index : -1,
          duration: vehicle.duration || -1,
          distance: vehicle.distance || -1,
          shift_preference: (vehicle.force_start ? 'force_start' : vehicle.shift_preference.to_s),
          day_index: vehicle.global_day_index || -1,
          max_ride_time: vehicle.maximum_ride_time || 0,
          max_ride_distance: vehicle.maximum_ride_distance || 0,
          free_approach: vehicle.free_approach || false,
          free_return: vehicle.free_return || false,
          type_index: vehicle.type_index
        )
      }

      relations += vrp.relations.collect{ |relation|
        current_linked_ids = relation.linked_ids.select{ |mission_id|
          services.one?{ |service| service.id == mission_id } ||
            vrp.shipments.one? { |shipment| mission_id == "#{shipment.id}pickup" } ||
            vrp.shipments.one? { |shipment| mission_id == "#{shipment.id}delivery" }
        }.uniq
        current_linked_vehicles = relation.linked_vehicle_ids.select{ |vehicle_id|
          vrp.vehicles.one? { |vehicle| vehicle.id == vehicle_id }
        }.uniq
        next if current_linked_ids.empty? && current_linked_vehicles.empty?

        OrtoolsVrp::Relation.new(
          type: relation.type.to_s,
          linked_ids: current_linked_ids,
          linked_vehicle_ids: current_linked_vehicles,
          lapse: relation.lapse || -1
        )
      }.compact

      routes = vrp.routes.collect{ |route|
        next if route.vehicle.nil? || route.mission_ids.empty?

        OrtoolsVrp::Route.new(
          vehicle_id: route.vehicle.id,
          service_ids: corresponding_mission_ids(services.collect(&:id), route.mission_ids)
        )
      }

      relations << OrtoolsVrp::Relation.new(type: 'force_first', linked_ids: services_positions[:always_first], lapse: -1) unless services_positions[:always_first].empty?
      relations << OrtoolsVrp::Relation.new(type: 'never_first', linked_ids: services_positions[:never_first], lapse: -1) unless services_positions[:never_first].empty?
      relations << OrtoolsVrp::Relation.new(type: 'never_last', linked_ids: services_positions[:never_last], lapse: -1) unless services_positions[:never_last].empty?
      relations << OrtoolsVrp::Relation.new(type: 'force_end', linked_ids: services_positions[:always_last], lapse: -1) unless services_positions[:always_last].empty?

      problem = OrtoolsVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
        relations: relations,
        routes: routes
      )

      log "ortools solve problem creation elapsed: #{Time.now - tic}sec", level: :debug
      ret = run_ortools(problem, vrp, services, points, matrix_indices, thread_proc, &block)
      case ret
      when String
        return ret
      when Array
        cost, iterations, result = ret
      else
        return ret
      end

      result
    end

    def kill
      @killed = true
    end

    private

    def build_costs(costs)
      cost = Models::Costs.new(
        fixed: costs&.fixed || 0,
        time: costs && (costs.time + costs.time_fake + costs.time_without_wait) || 0,
        distance: costs && (costs.distance + costs.distance_fake) || 0,
        value: costs&.value || 0,
        lateness: costs&.lateness || 0,
        overload: costs&.overload || 0
      )
      cost.total = cost.attributes.values.sum
      cost
    end

    def check_services_compatible_days(vrp, vehicle, service)
      !vrp.schedule_range_indices || (!service.minimum_lapse && !service.maximum_lapse) ||
        vehicle.global_day_index.between?(service.first_possible_days.first, service.last_possible_days.first)
    end

    def parse_output(vrp, _services, points, _matrix_indices, _cost, _iterations, output)
      if vrp.vehicles.empty? || (vrp.services.nil? || vrp.services.empty?) && (vrp.shipments.nil? || vrp.shipments.empty?)
        return empty_result('ortools', vrp)
      end

      content = OrtoolsResult::Result.decode(output.read)
      output.rewind

      # Currently, we continue to multiply by 1000 so we divide by 1000.0
      # but this needs to be updated by unit.precision_coef
      content.routes.each{ |route|
        route.costs.overload = (route.costs.overload || 0) / 1000.0 if route.costs
        route.activities.each{ |activity|
          activity.quantities.map!{ |val| val / 1000.0 }
        }
      }

      return @previous_result if content.routes.empty? && @previous_result

      route_start_time = 0
      route_end_time = 0
      costs_array = []

      collected_indices = []
      vehicle_rest_ids = Hash.new([])
      {
        cost: content.cost || 0,
        solvers: ['ortools'],
        iterations: content.iterations || 0,
        elapsed: content.duration * 1000, # ms
        routes: content.routes.each_with_index.collect{ |route, index|
          vehicle = vrp.vehicles[index]
          vehicle_matrix = vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }
          route_costs = build_costs(route.costs)
          costs_array << route_costs

          previous_matrix_index = nil
          load_status = vrp.units.collect{ |unit|
            {
              unit: unit.id,
              label: unit.label,
              current_load: 0
            }
          }
          route_start = (vehicle.timewindow && vehicle.timewindow[:start]) ? vehicle.timewindow[:start] : 0
          earliest_start = route_start
          {
            vehicle_id: vehicle.id,
            original_vehicle_id: vehicle.original_id,
            costs: route_costs,
            activities: route.activities.collect.with_index{ |activity, activity_index|
              current_activity = nil
              current_index = activity.index || 0
              activity_loads = load_status.collect.with_index{ |load_quantity, load_index|
                unit = vrp.units.find{ |u| u.id == load_quantity[:unit] }
                {
                  unit: unit.id,
                  label: unit.label,
                  current_load: (if vehicle.end_point && activity.type == 'end'
                                  route.activities[-2].quantities[load_index]
                                elsif activity.type == 'break' && activity_index.positive?
                                  route.activities[activity_index - 1].quantities[load_index]
                                else
                                  activity.quantities[load_index]
                                end || 0).round(2),
                  counting: unit.counting
                }
              }
              earliest_start = activity.start_time || 0
              if activity.type == 'start'
                load_status = build_quantities(nil, activity_loads)
                route_start_time = earliest_start
                if vehicle.start_point
                  previous_matrix_index = points[vehicle.start_point.id].matrix_index
                  current_activity = {
                    point_id: vehicle.start_point.id,
                    begin_time: earliest_start,
                    current_distance: activity.current_distance,
                    detail: build_detail(nil, nil, vehicle.start_point, nil, activity_loads, vehicle)
                  }.delete_if{ |_k, v| !v }
                end
              elsif activity.type == 'end'
                current_matrix_index = vehicle.end_point&.matrix_index
                route_data = build_route_data(vehicle_matrix, previous_matrix_index, current_matrix_index)
                route_end_time = earliest_start
                if vehicle.end_point
                  current_activity = {
                    point_id: vehicle.end_point.id,
                    current_distance: activity.current_distance,
                    begin_time: earliest_start,
                    detail: {
                      lat: vehicle.end_point.location&.lat,
                      lon: vehicle.end_point.location&.lon,
                      quantities: activity_loads.collect{ |current_load|
                        {
                          unit: current_load[:unit],
                          current_load: current_load[:current_load]
                        }
                      }
                    }
                  }.merge(route_data).delete_if{ |_k, v| !v }
                end
              elsif activity.type == 'service'
                collected_indices << current_index
                if current_index < vrp.services.size
                  service = vrp.services[current_index]
                  point = service.activity&.point || !service.activities.empty? && service.activities[activity.alternative].point
                  current_matrix_index = point.matrix_index
                  route_data = build_route_data(vehicle_matrix, previous_matrix_index, current_matrix_index)
                  current_activity = {
                    original_service_id: service.original_id,
                    service_id: service.id,
                    point_id: point ? point.id : nil,
                    current_distance: activity.current_distance,
                    begin_time: earliest_start,
                    departure_time: earliest_start + (service.activity ? service.activity[:duration].to_i : service.activities[activity.alternative][:duration].to_i),
                    detail: build_detail(service, service.activity, point, vehicle.global_day_index ? vehicle.global_day_index % 7 : nil, activity_loads, vehicle),
                    alternative: service.activities ? activity.alternative : nil
                  }.merge(route_data).delete_if{ |_k, v| !v }
                else
                  shipment_index = ((current_index - vrp.services.size) / 2).to_i
                  shipment_activity = (current_index - vrp.services.size) % 2
                  shipment = vrp.shipments[shipment_index]
                  point = shipment_activity.zero? ? shipment.pickup.point : shipment.delivery.point # TODO: consider alternatives
                  current_matrix_index = point.matrix_index
                  earliest_start = activity.start_time || 0
                  route_data = build_route_data(vehicle_matrix, previous_matrix_index, current_matrix_index)
                  current_activity = {
                    original_shipment_id: shipment.original_id,
                    pickup_shipment_id: shipment_activity.zero? && shipment.id,
                    delivery_shipment_id: shipment_activity == 1 && shipment.id,
                    point_id: point.id,
                    begin_time: earliest_start,
                    departure_time: earliest_start + (shipment_activity.zero? ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i),
                    detail: build_detail(shipment, shipment_activity.zero? ? shipment.pickup : shipment.delivery, point, vehicle.global_day_index ? vehicle.global_day_index % 7 : nil, activity_loads, vehicle, shipment_activity.zero? ? nil : true)
                  }.merge(route_data).delete_if{ |_k, v| !v }
                  earliest_start += shipment_activity.zero? ? vrp.shipments[shipment_index].pickup[:duration].to_i : vrp.shipments[shipment_index].delivery[:duration].to_i
                end
                previous_matrix_index = current_matrix_index
              elsif activity.type == 'break'
                activity.id
                vehicle_rest_ids[vehicle.id] << activity.id
                vehicle_rest = vehicle.rests.find{ |rest| rest.id == activity.id }
                earliest_start = activity.start_time
                current_activity = {
                  rest_id: activity.id,
                  begin_time: earliest_start,
                  departure_time: earliest_start + vehicle_rest[:duration],
                  detail: build_rest(vehicle_rest, vehicle.global_day_index ? vehicle.global_day_index % 7 : nil, activity_loads)
                }
                earliest_start += vehicle_rest[:duration]
              end
              current_activity
            }.compact,
            start_time: route_start_time,
            end_time: route_end_time,
            initial_loads: load_status.collect{ |unit|
              {
                unit: unit[:unit],
                label: unit[:label],
                value: unit[:current_load]
              }
            }
          }
        },
        unassigned: (vrp.services.collect(&:id) - collected_indices.collect{ |index| index < vrp.services.size && vrp.services[index].id }).collect{ |service_id|
          service = vrp.services.find{ |s| s.id == service_id }
          {
            original_service_id: service.original_id,
            service_id: service_id,
            type: service.type.to_s,
            point_id: service.activity ? service.activity.point_id : service.activities.collect{ |activity| activity[:point_id] },
            detail: service.activity ? build_detail(service, service.activity, service.activity.point, nil, nil, nil) : { activities: service.activities }
          }
        } + (vrp.shipments.collect(&:id) - collected_indices.collect{ |index| index >= vrp.services.size && ((index - vrp.services.size) / 2).to_i < vrp.shipments.size && vrp.shipments[((index - vrp.services.size) / 2).to_i].id }.uniq).collect{ |shipment_id|
          shipment = vrp.shipments.find{ |sh| sh.id == shipment_id }
          [{
            original_shipment_id: shipment.original_id,
            shipment_id: shipment_id.to_s,
            type: 'pickup',
            point_id: shipment.pickup.point_id,
            detail: build_detail(shipment, shipment.pickup, shipment.pickup.point, nil, nil, nil)
          }, {
            original_shipment_id: shipment.original_id,
            shipment_id: shipment_id.to_s,
            type: 'delivery',
            point_id: shipment.delivery.point_id,
            detail: build_detail(shipment, shipment.delivery, shipment.delivery.point, nil, nil, nil, true)
          }]
        }.flatten + vrp.vehicles.flat_map{ |vehicle|
          (vehicle.rests.collect(&:id) - vehicle_rest_ids[vehicle.id]).map{ |rest_id|
            rest = vrp.rests.find{ |rt| rt.id == rest_id }
            {
              vehicle_id: vehicle.id,
              rest_id: rest_id,
              detail: build_rest(rest, nil, {})
            }
          }
        }
      }.merge(costs: costs_array.sum)
    end

    def run_ortools(problem, vrp, services, points, matrix_indices, thread_proc = nil, &block)
      log "----> run_ortools services(#{services.size}) preassigned(#{vrp.routes.flat_map{ |r| r[:mission_ids].size }.sum}) vehicles(#{vrp.vehicles.size})"
      tic = Time.now
      if vrp.vehicles.empty? || (vrp.services.nil? || vrp.services.empty?) && (vrp.shipments.nil? || vrp.shipments.empty?)
        return [0, 0, @previous_result = parse_output(vrp, services, points, matrix_indices, 0, 0, nil)]
      end

      input = Tempfile.new('optimize-or-tools-input', @tmp_dir, binmode: true)
      input.write(OrtoolsVrp::Problem.encode(problem))
      input.close

      output = Tempfile.new('optimize-or-tools-output', @tmp_dir, binmode: true)

      correspondant = { 'path_cheapest_arc' => 0, 'global_cheapest_arc' => 1, 'local_cheapest_insertion' => 2, 'savings' => 3, 'parallel_cheapest_insertion' => 4, 'first_unbound' => 5, 'christofides' => 6 }

      raise StandardError, "Inconsistent first solution strategy used internally: #{vrp.preprocessing_first_solution_strategy}" if vrp.preprocessing_first_solution_strategy && correspondant[vrp.preprocessing_first_solution_strategy.first].nil?

      cmd = [
              "#{@exec_ortools} ",
              (vrp.resolution_duration || @optimize_time) && '-time_limit_in_ms ' + (vrp.resolution_duration || @optimize_time).round.to_s,
              vrp.preprocessing_prefer_short_segment ? '-nearby' : nil,
              (vrp.resolution_evaluate_only ? nil : (vrp.preprocessing_neighbourhood_size ? "-neighbourhood #{vrp.preprocessing_neighbourhood_size}" : nil)),
              (vrp.resolution_iterations_without_improvment || @iterations_without_improvment) && '-no_solution_improvement_limit ' + (vrp.resolution_iterations_without_improvment || @iterations_without_improvment).to_s,
              (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) && '-minimum_duration ' + (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out).round.to_s,
              (vrp.resolution_time_out_multiplier || @time_out_multiplier) && '-time_out_multiplier ' + (vrp.resolution_time_out_multiplier || @time_out_multiplier).to_s,
              vrp.resolution_init_duration ? "-init_duration #{vrp.resolution_init_duration.round}" : nil,
              (vrp.resolution_vehicle_limit && vrp.resolution_vehicle_limit < problem.vehicles.size) ? "-vehicle_limit #{vrp.resolution_vehicle_limit}" : nil,
              vrp.preprocessing_first_solution_strategy ? "-solver_parameter #{correspondant[vrp.preprocessing_first_solution_strategy.first]}" : nil,
              (vrp.resolution_evaluate_only || vrp.resolution_batch_heuristic) ? '-only_first_solution' : nil,
              vrp.restitution_intermediate_solutions ? '-intermediate_solutions' : nil,
              "-instance_file '#{input.path}'",
              "-solution_file '#{output.path}'"
            ].compact.join(' ')

      log cmd

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

      thread_proc&.call(childs)

      out = ''
      iterations = 0
      cost = nil
      time = 0.0
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        r = /Iteration : ([0-9]+)/.match(line)
        r && (iterations = Integer(r[1]))
        s = / Cost : ([0-9.eE+]+)/.match(line)
        s && (cost = Float(s[1]))
        t = /Time : ([0-9.eE+]+)/.match(line)
        t && (time = t[1].to_f)
        log line.strip, level: (/Final Iteration :/.match(line) || /First solution strategy :/.match(line) || /Using initial solution provided./.match(line) || /OR-Tools v[0-9]+\.[0-9]+\n/.match(line)) ? :info : (r || s || t) ? :debug : :error
        out += line

        next unless r && t # if there is no iteration and time then there is nothing to do

        begin
          @previous_result = if vrp.restitution_intermediate_solutions && s
                               parse_output(vrp, services, points, matrix_indices, cost, iterations, output)
                             end
          block&.call(self, iterations, nil, nil, cost, time, @previous_result) # if @previous_result=nil, it will not override the existing solution
        rescue Google::Protobuf::ParseError => e
          # log and ignore protobuf parsing errors
          log "#{e.class}: #{e.message} (in run_ortools during parse_output)", level: :error
        end
      }

      result = out.split("\n")[-1]
      if @thread.value.success?
        if result == 'No solution found...'
          cost = Helper.fixnum_max
          @previous_result = empty_result('ortools', vrp)
          @previous_result[:cost] = cost
        else
          @previous_result = parse_output(vrp, services, points, matrix_indices, cost, iterations, output)
        end
        [cost, iterations, @previous_result]
      elsif @thread.value.signaled? && @thread.value.termsig == 9
        log 'Job killed', level: :fatal # Keep trace in worker
        raise OptimizerWrapper::JobKilledError
      else # Fatal Error
        message = if @thread.value == 127
                    'Executable does not exist'
                  else
                    "Job terminated with unknown thread status: #{@thread.value}"
                  end
        log message, level: :fatal
        raise RuntimeError, message
      end
    ensure
      input&.unlink
      output&.close
      output&.unlink
      @thread&.value # wait for the termination of the thread in case there is one
      stdin&.close
      stdout_and_stderr&.close
      pipe&.close
      log "<---- run_ortools #{Time.now - tic}sec elapsed", level: :debug
    end

    def update_services_positions(services, services_positions, id, position, service_index)
      services_positions[:always_first] << id if position == :always_first
      services_positions[:never_first] << id if [:never_first, :always_middle].include?(position)
      services_positions[:never_last] << id if [:never_last, :always_middle].include?(position)
      services_positions[:always_last] << id if position == :always_last

      return services if position != :never_middle

      services + services.select{ |s| s.problem_index == service_index }.collect{ |s|
        services_positions[:always_first] << id
        services_positions[:always_last] << "#{id}_alternative"
        copy_s = s.dup
        copy_s.id += '_alternative'
        copy_s
      }
    end

    def corresponding_mission_ids(available_ids, mission_ids)
      mission_ids.collect{ |mission_id|
        correct_id = if available_ids.include?(mission_id)
          mission_id
        elsif available_ids.include?("#{mission_id}pickup")
          "#{mission_id}pickup"
        elsif available_ids.include?("#{mission_id}delivery")
          "#{mission_id}delivery"
        end

        available_ids.delete(correct_id)
        correct_id
      }
    end
  end
end
