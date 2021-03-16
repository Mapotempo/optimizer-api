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
module Wrappers
  class Wrapper
    def initialize(hash = {})
      @tmp_dir = hash[:tmp_dir] || Dir.tmpdir
      @threads = hash[:threads] || 1
    end

    def solver_constraints
      [
       :assert_no_pickup_timewindows_after_delivery_timewindows,
      ]
    end

    def inapplicable_solve?(vrp)
      solver_constraints.reject{ |constraint|
        self.send(constraint, vrp)
      }
    end

    def assert_points_same_definition(vrp)
      (vrp.points.all?(&:location) || vrp.points.none?(&:location)) && (vrp.points.all?(&:matrix_index) || vrp.points.none?(&:matrix_index))
    end

    def assert_vehicles_only_one(vrp)
      vrp.vehicles.size == 1 && !vrp.scheduling?
    end

    def assert_vehicles_start(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.start_point.nil?
      }
    end

    def assert_vehicles_start_or_end(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.start_point.nil? && vehicle.end_point.nil?
      }
    end

    def assert_vehicles_no_capacity_initial(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |c| c.initial&.positive? }
      }
    end

    def assert_vehicles_no_alternative_skills(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.skills || vehicle.skills.size > 1
      }
    end

    def assert_no_direct_shipments(vrp)
      vrp.shipments.none?{ |shipment| shipment.direct }
    end

    def assert_no_pickup_timewindows_after_delivery_timewindows(vrp)
      vrp.shipments.empty? || vrp.shipments.none? { |shipment|
        first_open = shipment.pickup.timewindows.min_by(&:start)
        last_close = shipment.delivery.timewindows.max_by(&:end)
        first_open && last_close && first_open.start + 86400 * (first_open.day_index || 0) >
          (last_close.end || 86399) + 86400 * (last_close.day_index || 0)
      }
    end

    def assert_services_no_priority(vrp)
      vrp.services.empty? || vrp.services.uniq(&:priority).size == 1
    end

    def assert_vehicles_objective(vrp)
      vrp.vehicles.all?{ |vehicle|
        vehicle.cost_time_multiplier&.positive? ||
          vehicle.cost_distance_multiplier&.positive? ||
          vehicle.cost_waiting_time_multiplier&.positive? ||
          vehicle.cost_value_multiplier&.positive?
      }
    end

    def assert_vehicles_no_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.cost_late_multiplier&.positive?
      }
    end

    def assert_vehicles_no_late_multiplier_or_single_vehicle(vrp)
      assert_vehicles_no_late_multiplier(vrp) || assert_vehicles_only_one(vrp)
    end

    def assert_vehicles_no_overload_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |capacity|
          capacity.overload_multiplier&.positive?
        }
      }
    end

    def assert_vehicles_no_force_start(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?(&:force_start)
    end

    def assert_vehicles_no_duration_limit(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?(&:duration)
    end

    def assert_vehicles_no_zero_duration(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.duration&.zero?
      }
    end

    def assert_services_no_late_multiplier(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        if service.activity
          service.activity&.timewindows&.size&.positive? && service.activity&.late_multiplier&.positive?
        else
          service.activities.none?{ |activity|
            activity&.timewindows&.size&.positive? && activity&.late_multiplier&.positive?
          }
        end
      }
    end

    def assert_shipments_no_late_multiplier(vrp)
      vrp.shipments.empty? || vrp.shipments.none?{ |shipment|
        shipment.pickup.late_multiplier&.positive? || shipment.delivery.late_multiplier&.positive?
      }
    end

    def assert_missions_no_late_multiplier(vrp)
      assert_shipments_no_late_multiplier(vrp) && assert_services_no_late_multiplier(vrp)
    end

    def assert_matrices_only_one(vrp)
      vrp.vehicles.group_by{ |vehicle|
        vehicle.matrix_id || [vehicle.router_mode.to_sym, vehicle.router_dimension, vehicle.speed_multiplier]
      }.size <= 1
    end

    def assert_square_matrix(vrp)
      dimensions = vrp.vehicles.collect(&:dimensions).flatten.uniq
      vrp.matrices.all?{ |matrix|
        dimensions.all?{ |dimension|
          matrix[dimension].nil? || matrix[dimension].all?{ |line| matrix[dimension].size == line.size }
        }
      }
    end

    def assert_correctness_matrices_vehicles_and_points_definition(vrp)
      # Either there is no matrix and all points are with a location
      # or all points and vehicles have matrix_index and matrix_id, respectively
      (vrp.matrices.count{ |matrix| matrix[:time] || matrix[:distance] }.zero? && vrp.points.all?(&:location)) ||
        (vrp.points.all?(&:matrix_index) && vrp.vehicles.all?(&:matrix_id))
    end

    def assert_one_sticky_at_most(vrp)
      (vrp.services.empty? || vrp.services.none?{ |service|
        service.sticky_vehicles.size > 1
      }) && (vrp.shipments.empty? || vrp.shipments.none?{ |shipment|
        shipment.sticky_vehicles.size > 1
      })
    end

    def assert_no_relations(vrp)
      vrp.relations.empty? || vrp.relations.all?{ |relation| relation.linked_ids.empty? && relation.linked_vehicle_ids.empty? }
    end

    def assert_zones_only_size_one_alternative(vrp)
      vrp.zones.empty? || vrp.zones.all?{ |zone| zone.allocations.none?{ |alternative| alternative.size > 1 } }
    end

    def assert_no_value_matrix(vrp)
      vrp.matrices.none?(&:value)
    end

    def assert_no_subtours(vrp)
      vrp.subtours.empty?
    end

    def assert_only_empty_or_fill_quantities(vrp)
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
          return false if unit_status[:fill] && unit_status[:empty]
        }
      }
      true
    end

    def assert_end_optimization(vrp)
      vrp.resolution_duration || vrp.resolution_iterations_without_improvment
    end

    def assert_no_distance_limitation(vrp)
      vrp.vehicles.none?(&:distance)
    end

    def assert_vehicle_tw_if_schedule(vrp)
      vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' ||
        vrp.vehicles.all?{ |vehicle|
          vehicle.timewindow || vehicle.sequence_timewindows&.size&.positive?
        }
    end

    def assert_if_sequence_tw_then_schedule(vrp)
      vrp.vehicles.find{ |vehicle| !vehicle.sequence_timewindows.empty? }.nil? || vrp.scheduling?
    end

    def assert_if_periodic_heuristic_then_schedule(vrp)
      vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' || vrp.scheduling?
    end

    def assert_first_solution_strategy_is_possible(vrp)
      vrp.preprocessing_first_solution_strategy.empty? || (!vrp.resolution_evaluate_only && !vrp.resolution_batch_heuristic)
    end

    def assert_first_solution_strategy_is_valid(vrp)
      vrp.preprocessing_first_solution_strategy.empty? ||
        (vrp.preprocessing_first_solution_strategy[0] != 'self_selection' && vrp.preprocessing_first_solution_strategy[0] != 'periodic' || vrp.preprocessing_first_solution_strategy.size == 1) &&
          vrp.preprocessing_first_solution_strategy.all?{ |strategy| strategy == 'self_selection' || strategy == 'periodic' || OptimizerWrapper::HEURISTICS.include?(strategy) }
    end

    def assert_no_planning_heuristic(vrp)
      vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_only_force_centroids_if_kmeans_method(vrp)
      vrp.preprocessing_kmeans_centroids.nil? || vrp.preprocessing_partition_method == 'balanced_kmeans'
    end

    def assert_no_evaluation(vrp)
      !vrp.resolution_evaluate_only
    end

    def assert_no_shipments_if_evaluation(vrp)
      (!vrp.shipments || vrp.shipments.empty?) || !vrp.resolution_evaluate_only
    end

    def assert_only_one_visit(vrp)
      vrp.services.all?{ |service| service.visits_number == 1 } && vrp.shipments.all?{ |shipment| shipment.visits_number == 1 }
    end

    def assert_no_scheduling_if_evaluation(vrp)
      !vrp.scheduling? || !vrp.resolution_evaluate_only
    end

    def assert_route_if_evaluation(vrp)
      !vrp.resolution_evaluate_only || vrp.routes && !vrp.routes.empty?
    end

    def assert_wrong_vehicle_shift_preference_with_heuristic(vrp)
      (vrp.vehicles.map(&:shift_preference).uniq - [:minimize_span] - ['minimize_span']).empty? || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_vehicle_overall_duration_if_heuristic(vrp)
      vrp.vehicles.none?(&:overall_duration) || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_overall_duration(vrp)
      relation_array = %w[vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months]
      vrp.vehicles.none?(&:overall_duration) &&
        vrp.relations.none?{ |relation| relation_array.include?(relation.type) }
    end

    def assert_no_vehicle_distance_if_heuristic(vrp)
      vrp.vehicles.none?(&:distance) || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_possible_to_get_distances_if_maximum_ride_distance(vrp)
      vrp.vehicles.none?(&:maximum_ride_distance) || (vrp.points.all?{ |point| point.location&.lat } || vrp.matrices.all?{ |matrix| matrix.distance && !matrix.distance.empty? })
    end

    def assert_no_skills_if_heuristic(vrp)
      vrp.services.none?{ |service| !service.skills.empty? } || vrp.vehicles.none?{ |vehicle| !vehicle.skills.flatten.empty? } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' || !vrp.preprocessing_partitions.empty?
    end

    def assert_no_vehicle_free_approach_or_return_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_free_approach_or_return(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return }
    end

    def assert_no_vehicle_limit_if_heuristic(vrp)
      vrp.resolution_vehicle_limit.nil? || vrp.resolution_vehicle_limit >= vrp.vehicles.size || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_same_point_day_if_no_heuristic(vrp)
      !vrp.resolution_same_point_day || vrp.preprocessing_first_solution_strategy.to_a.first == 'periodic'
    end

    def assert_no_allow_partial_if_no_heuristic(vrp)
      vrp.resolution_allow_partial_assignment || vrp.preprocessing_first_solution_strategy.to_a.first == 'periodic'
    end

    def assert_no_first_solution_strategy(vrp)
      vrp.preprocessing_first_solution_strategy.empty? || vrp.preprocessing_first_solution_strategy == ['self_selection']
    end

    def assert_solver(vrp)
      vrp.resolution_solver
    end

    def assert_solver_if_not_periodic(vrp)
      vrp.resolution_solver || vrp.preprocessing_first_solution_strategy && (vrp.preprocessing_first_solution_strategy.first == 'periodic')
    end

    def assert_clustering_compatible_with_scheduling_heuristic(vrp)
      (!vrp.preprocessing_first_solution_strategy || !vrp.preprocessing_first_solution_strategy.include?('periodic')) || !vrp.preprocessing_cluster_threshold && !vrp.preprocessing_max_split_size
    end

    def assert_lat_lon_for_partition(vrp)
      vrp.preprocessing_partition_method.nil? || vrp.points.all?{ |pt| pt.location && pt.location.lat && pt.location.lon }
    end

    def assert_vehicle_entity_only_before_work_day(vrp)
      vehicle_entity_index = vrp.preprocessing_partitions.find_index{ |partition| partition[:entity] == :vehicle }
      work_day_entity_index = vrp.preprocessing_partitions.find_index{ |partition| partition[:entity] == :work_day }
      vehicle_entity_index.nil? || work_day_entity_index.nil? || vehicle_entity_index < work_day_entity_index
    end

    def assert_deprecated_partitions(vrp)
      !((vrp.preprocessing_partition_method || vrp.preprocessing_partition_metric) && !vrp.preprocessing_partitions.empty?)
    end

    def assert_partitions_entity(vrp)
      vrp.preprocessing_partitions.empty? || vrp.preprocessing_partitions.all?{ |partition| partition[:method] != 'balanced_kmeans' || partition[:entity] }
    end

    def assert_no_partitions(vrp)
      vrp.preprocessing_partitions.empty?
    end

    def assert_no_initial_centroids_with_partitions(vrp)
      vrp.preprocessing_partitions.empty? || vrp.preprocessing_kmeans_centroids.nil?
    end

    def assert_valid_partitions(vrp)
      vrp.preprocessing_partitions.size < 3 &&
        (vrp.preprocessing_partitions.collect{ |partition| partition[:entity] }.uniq.size == vrp.preprocessing_partitions.size)
    end

    def assert_route_date_or_indice_if_periodic(vrp)
      !vrp.periodic_heuristic? || vrp.routes.all?(&:day_index)
    end

    def assert_not_too_many_visits_in_route(vrp)
      vrp.routes.to_a.collect{ |r| r[:mission_ids] }.flatten.group_by{ |id| id }.all?{ |id, set|
        corresponding_service = vrp.services.find{ |s| s[:id] == id }
        if corresponding_service.nil?
          true # not to send a confusing error to user, this is detected in assert_missions_in_routes_do_exist
        else
          set.size <= corresponding_service.visits_number
        end
      }
    end

    def assert_homogeneous_router_definitions(vrp)
      vrp.vehicles.group_by{ |vehicle|
        [vehicle.router_mode, vehicle.dimensions, vehicle.router_options]
      }.size <= 1
    end

    def assert_homogeneous_costs(vrp)
      vrp.vehicles.group_by{ |vehicle|
        [vehicle.cost_time_multiplier, vehicle.cost_distance_multiplier, vehicle.cost_value_multiplier]
      }.size <= 1
    end

    def assert_no_exclusion_cost(vrp)
      vrp.services.none?(&:exclusion_cost) && vrp.shipments.none?(&:exclusion_cost)
    end

    def assert_only_time_dimension(vrp)
      vrp.vehicles.none? { |vehicle|
        vehicle.cost_distance_multiplier.to_f.positive? ||
          vehicle.cost_value_multiplier.to_f.positive? ||
          vehicle.distance
      }
    end

    def assert_only_distance_dimension(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.cost_time_multiplier.to_f.positive? ||
          vehicle.cost_value_multiplier.to_f.positive? ||
          vehicle.duration ||
          vehicle.timewindow&.end
      } && vrp.services.none?{ |service| service.activity.timewindows&.any? }
    end

    def assert_only_value_dimension(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.cost_time_multiplier.to_f.positive? ||
          vehicle.cost_distance_multiplier.to_f.positive? ||
          vehicle.duration ||
          vehicle.distance ||
          vehicle.timewindow&.end
      }
    end

    def assert_single_dimension(vrp)
      vrp.vehicles.empty? || (assert_only_time_dimension(vrp) ^ assert_only_distance_dimension(vrp) ^ assert_only_value_dimension(vrp))
    end

    def assert_no_route_if_schedule_without_periodic_heuristic(vrp)
      vrp.routes.empty? || !vrp.scheduling? || vrp.periodic_heuristic?
    end

    # TODO: Need a better way to represent solver preference
    def assert_small_minimum_duration(vrp)
      vrp.resolution_minimum_duration.nil? || vrp.vehicles.empty? || vrp.resolution_minimum_duration / vrp.vehicles.size < 5000
    end

    def assert_no_cost_fixed(vrp)
      vrp.vehicles.all?{ |vehicle| vehicle.cost_fixed.nil? || vehicle.cost_fixed.zero? } || vrp.vehicles.map(&:cost_fixed).uniq.size == 1
    end

    def assert_no_setup_duration(vrp)
      vrp.services.all?{ |service| service.activity.setup_duration.nil? || service.activity.setup_duration.zero? } &&
        vrp.shipments.all?{ |shipment|
          (shipment.pickup.setup_duration.nil? || shipment.pickup.setup_duration.zero?) &&
            (shipment.delivery.setup_duration.nil? || shipment.delivery.setup_duration.zero?)
        }
    end

    def solve_synchronous?(_vrp)
      false
    end

    def build_timewindows(activity, day_index)
      activity.timewindows.select{ |timewindow|
        day_index.nil? ||
          timewindow.day_index.nil? ||
          timewindow.day_index == day_index
      }.collect{ |timewindow|
        {
          start: timewindow.start,
          end: timewindow.end,
          day_index: timewindow.day_index
        }
      }
    end

    def build_quantities(job, job_loads, delivery = nil)
      if job_loads
        job_loads.collect{ |current_load|
          associated_quantity = job.quantities.find{ |quantity| quantity.unit && quantity.unit.id == current_load[:unit] } if job
          {
            unit: current_load[:unit],
            label: current_load[:label],
            value: associated_quantity && associated_quantity.value && (delivery.nil? ? 1 : -1) * associated_quantity.value,
            setup_value: current_load[:counting] ? associated_quantity && associated_quantity.setup_value : nil,
            current_load: current_load[:current_load]
          }.delete_if{ |_k, v| !v }
        }
      elsif job
        job.quantities.collect{ |quantity|
          next if quantity.unit.nil?

          {
            unit: quantity.unit.id,
            label: quantity.unit.label,
            value: quantity&.value && (delivery.nil? ? 1 : -1) * quantity.value,
            setup_value: quantity.unit.counting ? quantity.setup_value : 0
          }
        }.compact
      end
    end

    def build_rest(rest, vehicle = nil)
      {
        duration: rest.duration,
        router_mode: vehicle&.router_mode,
        speed_multiplier: vehicle&.speed_multiplier
      }
    end

    def build_detail(job, activity, point, day_index, job_load, vehicle, delivery = nil)
      {
        lat: point&.location&.lat,
        lon: point&.location&.lon,
        skills: job&.skills,
        setup_duration: activity&.setup_duration,
        duration: activity&.duration,
        additional_value: activity&.additional_value,
        timewindows: activity && build_timewindows(activity, day_index),
        quantities: build_quantities(job, job_load, delivery),
        router_mode: vehicle&.router_mode,
        speed_multiplier: vehicle&.speed_multiplier
      }.delete_if{ |_k, v| !v }
    end

    def build_route_data(vehicle_matrix, previous_matrix_index, current_matrix_index)
      if previous_matrix_index && current_matrix_index
        travel_distance = vehicle_matrix[:distance] ? vehicle_matrix[:distance][previous_matrix_index][current_matrix_index] : 0
        travel_time = vehicle_matrix[:time] ? vehicle_matrix[:time][previous_matrix_index][current_matrix_index] : 0
        travel_value = vehicle_matrix[:value] ? vehicle_matrix[:value][previous_matrix_index][current_matrix_index] : 0
        return {
          travel_distance: travel_distance,
          travel_time: travel_time,
          travel_value: travel_value
        }
      end
      {}
    end

    def compatible_day?(vrp, service, t_day, vehicle)
      first_day = vrp[:schedule][:range_indices] ? vrp[:schedule][:range_indices][:start] : vrp[:schedule][:range_date][:start]
      last_day = vrp[:schedule][:range_indices] ? vrp[:schedule][:range_indices][:end] : vrp[:schedule][:range_date][:end]
      (first_day..last_day).any?{ |day|
        s_ok = t_day == day || !service.unavailable_days.include?(day)
        v_ok = !vehicle.unavailable_days.include?(day)
        s_ok && v_ok
      }
    end

    def find_vehicle(vrp, service)
      service_timewindows = service.activity ? service.activity.timewindows : service.activities.collect(&:timewindows).flatten
      service_lateness = service.activity&.late_multiplier&.positive?

      available_vehicle = vrp.vehicles.find{ |vehicle|
        vehicle_timewindows = vehicle.timewindow ? [vehicle.timewindow] : vehicle.sequence_timewindows
        vehicle_work_days = vehicle_timewindows.collect(&:day_index).compact.flatten
        vehicle_work_days = [0, 1, 2, 3, 4, 5] if vehicle_work_days.empty?
        vehicle_lateness = vehicle.cost_late_multiplier&.positive?

        days = vrp.scheduling? ? (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |day| day } : [0]
        days.any?{ |day|
          vehicle_work_days.include?(day % 7) && !vehicle.unavailable_days.include?(day) &&
            !service.unavailable_days.include?(day) &&
            (service_timewindows.empty? || vehicle_timewindows.empty? ||
              service_timewindows.any?{ |tw|
                (tw.day_index.nil? || tw.day_index == day % 7) &&
                  vehicle_lateness ||
                  service_lateness ||
                  vehicle_timewindows.any?{ |v_tw|
                    days_compatible = !v_tw.day_index || !tw.day_index || v_tw.day_index == tw.day_index
                    days_compatible &&
                      (tw.end.nil? || v_tw.start < tw.end) &&
                      (v_tw.end.nil? || v_tw.end > tw.start)
                  }
              })
        }
      }

      available_vehicle
    end

    def check(vrp, dimension, unfeasible)
      return unfeasible if vrp.matrices.any?{ |matrix| matrix[dimension].nil? || matrix[dimension].size == 1 }

      matrix_indices = vrp.points.map(&:matrix_index).uniq

      return unfeasible if matrix_indices.size <= 1

      line_cpt = Array.new(matrix_indices.size){ 0 }
      column_cpt = Array.new(matrix_indices.size){ 0 }
      vrp.matrices.each{ |matrix|
        matrix_indices.each_with_index{ |index_a, line|
          matrix_indices.each_with_index{ |index_b, col|
            if matrix[dimension][index_a][index_b] >= 2**31 - 1
              line_cpt[line] += 1
              column_cpt[col] += 1
            end
          }
        }
      }

      matrix_indices.each.with_index{ |matrix_index, index|
        next if (column_cpt[index] < vrp.matrices.size * (matrix_indices.size - 1)) && (line_cpt[index] < vrp.matrices.size * (matrix_indices.size - 1))

        vrp.services.select{ |service| (service.activity ? [service.activity] : service.activities).any?{ |activity| activity.point.matrix_index == matrix_index } }.each{ |service|
          if unfeasible.none?{ |unfeas| unfeas[:service_id] == service[:id] }
            add_unassigned(unfeasible, vrp, service, 'Unreachable')
          end
        }
      }

      unfeasible
    end

    def add_unassigned(unfeasible, vrp, service, reason)
      if unfeasible.any?{ |unfeas| unfeas[:original_service_id] == service[:id] }
        # we update reason to have more details
        unfeasible.select{ |unfeas| unfeas[:original_service_id] == service[:id] }.each{ |unfeas|
          unfeas[:reason] += " && #{reason}"
        }
      else
        unfeasible << (0..service.visits_number).collect{ |index|
          service_unassigned = unfeasible.find{ |una| una[:original_service_id] == service[:id] }
          service_unassigned[:reason] += " && #{reason}" if service_unassigned
          next if service_unassigned || service.visits_number.positive? && index.zero?

          {
            original_service_id: service.id,
            service_id: vrp.scheduling? ? "#{service.id}_#{index}_#{service.visits_number}" : service[:id],
            point_id: service.activity ? service.activity.point_id : nil,
            detail: build_detail(service, service.activity, service.activity.point, nil, nil, nil),
            type: 'service',
            reason: reason
          }
        }.compact
        unfeasible.flatten!
      end

      unfeasible
    end

    def compute_vehicles_shift(vehicles)
      max_shift = vehicles.collect{ |vehicle|
        next if vehicle&.cost_late_multiplier&.positive?

        if vehicle.timewindow&.start && vehicle.timewindow&.end
          vehicle.timewindow.end - vehicle.timewindow.start
        elsif vehicle.sequence_timewindows.all?(&:end)
          vehicle.sequence_timewindows.collect{ |tw| tw.end - tw.start }.max
        end
      }
      max_shift.include?(nil) ? nil : max_shift.max
    end

    def compute_vehicles_capacity(vrp)
      unit_ids = vrp.units.map(&:id)
      capacities = Hash[unit_ids.product([-1])]
      vrp.vehicles.each{ |vehicle|
        limits = Hash[unit_ids.product([-1])] # We expect to detect every undefined capacity

        vehicle.capacities.each{ |capacity| # Defined capacities are scanned
          limits[capacity.unit.id] = capacity.overload_multiplier&.positive? ? nil : capacity.limit
        }

        limits.each{ |k, v| # Unfound units are tagged as infinite
          capacities[k] = nil if v.nil? || v.negative?
          capacities[k] = [v, capacities[k]].max unless capacities[k].nil?
        }
      }
      capacities.reject{ |_k, v| v.nil? || v.negative? }
    end

    def detect_unfeasible_services(vrp)
      unfeasible = []
      vehicle_max_shift = compute_vehicles_shift(vrp.vehicles)
      vehicle_max_capacities = compute_vehicles_capacity(vrp)
      available_vehicle_skillsets = vrp.vehicles.flat_map(&:skills).uniq

      vrp.services.each{ |service|
        service.quantities.each{ |qty|
          if vehicle_max_capacities[qty.unit_id] && qty.value && vehicle_max_capacities[qty.unit_id] < qty.value.abs
            add_unassigned(unfeasible, vrp, service, 'Service quantity greater than any vehicle capacity')
            break
          end
        }

        if !service.skills.empty?
          if service.sticky_vehicles.empty?
            if available_vehicle_skillsets.none?{ |skillset| (service.skills - skillset).empty? }
              add_unassigned(unfeasible, vrp, service, 'Service skill combination is not available on any vehicle')
            end
          elsif service.sticky_vehicles.all?{ |vehicle| vehicle.skills.none?{ |skillset| (service.skills - skillset).empty? } }
            add_unassigned(unfeasible, vrp, service, 'Incompatibility between service skills and sticky vehicles')
          end
        end

        next if service.activity.nil? && service.activities.empty?

        duration = service.activity ? service.activity.duration : service.activities.collect(&:duration).min
        add_unassigned(unfeasible, vrp, service, 'Service duration greater than any vehicle timewindow') if vehicle_max_shift && duration > vehicle_max_shift

        add_unassigned(unfeasible, vrp, service, 'No vehicle with compatible timewindow') if !find_vehicle(vrp, service)

        # unconsistency for planning
        next if !vrp.scheduling?

        add_unassigned(unfeasible, vrp, service, 'Unconsistency between visit number and minimum lapse') unless vrp.can_affect_all_visits?(service)
      }

      unfeasible
    end

    def check_distances(vrp, unfeasible)
      unfeasible = check(vrp, :time, unfeasible)
      unfeasible = check(vrp, :distance, unfeasible)
      unfeasible = check(vrp, :value, unfeasible)

      # check distances from vehicle depot is feasible
      vrp.services.each{ |service|
        # Check via vehicle time-windows
        reachable_by_a_vehicle = (service.activity ? [service.activity] : service.activities).any?{ |activity|
          index = activity.point.matrix_index
          vrp.vehicles.find{ |vehicle|
            feasible = true

            start_index = vehicle.start_point&.matrix_index
            end_index = vehicle.end_point&.matrix_index
            matrix = vrp.matrices.find{ |mat| mat.id == vehicle.matrix_id } if start_index || end_index

            if vehicle.cost_time_multiplier&.positive? &&
               !vehicle.cost_late_multiplier&.positive? &&
               ((vehicle.timewindow&.start && vehicle.timewindow&.end) || vehicle.sequence_timewindows&.size&.positive?)
              vehicle_available_time = vehicle.timewindow.end - vehicle.timewindow.start if vehicle.timewindow
              vehicle_available_time = vehicle.sequence_timewindows.collect{ |tw| tw.end - tw.start }.max if vehicle.sequence_timewindows&.size&.positive?

              min_time = (start_index && matrix[:time][start_index][index]).to_f + (end_index && matrix[:time][index][end_index]).to_f + activity.duration

              feasible &&= (vehicle_available_time >= min_time)
            end

            if feasible &&
               (start_index || end_index) &&
               vehicle.cost_distance_multiplier&.positive? &&
               vehicle.distance
              min_dist = (start_index && matrix[:distance][start_index][index]).to_f + (end_index && matrix[:distance][index][end_index]).to_f

              feasible &&= (vehicle.distance >= min_dist)
            end

            feasible
          }
        }

        if !reachable_by_a_vehicle
          add_unassigned(unfeasible, vrp, service, 'Service cannot be served due to vehicle parameters -- e.g., timewindow, distance limit, etc.')
          next
        end

        # Check via service time-windows
        service_unreachable_within_its_tw = false
        if !(service.activity ? service.activity.timewindows : service.activities.collect(&:timewindows).flatten).empty?
          service_unreachable_within_its_tw = vrp.matrices.all?{ |matrix| matrix[:time] } && (service.activity ? [service.activity] : service.activites).all?{ |activity|
            index = activity.point.matrix_index

            vrp.vehicles.all?{ |vehicle|
              matrix = vrp.matrices.find{ |m| m.id == vehicle.matrix_id }

              if !activity.late_multiplier&.positive? # if service tw_violation is not allowed
                earliest_arrival = 0
                earliest_arrival += vehicle.timewindow.start                               if vehicle.timewindow&.start
                earliest_arrival += matrix[:time][vehicle.start_point.matrix_index][index] if vehicle.start_point_id
                timely_arrival_not_possible = activity.timewindows.all?{ |tw|
                  tw.end && earliest_arrival && earliest_arrival > tw.end
                }
              end

              if !vehicle.cost_late_multiplier&.positive? && (vehicle.timewindow&.end || vehicle.sequence_timewindows&.size&.positive?) # if vehicle tw_violation is not allowed
                vehicle_end = vehicle.timewindow&.end || vehicle.sequence_timewindows.collect(&:end).max
                latest_arrival = vehicle_end - activity.duration
                latest_arrival -= matrix[:time][index][vehicle.end_point.matrix_index] if vehicle.end_point_id
                timely_return_not_possible = activity.timewindows.all?{ |tw|
                  latest_arrival && latest_arrival < tw.start
                }
              end
              timely_arrival_not_possible || timely_return_not_possible
            }
          }
        end

        add_unassigned(unfeasible, vrp, service, 'Service cannot be reached within its timewindows') if service_unreachable_within_its_tw
      }

      log "Following services marked as infeasible:\n#{unfeasible.group_by{ |u| u[:reason] }.collect{ |g, set| "#{(set.size < 20) ? set.collect{ |s| s[:service_id] }.join(', ') : "#{set.size} services"}\n with reason '#{g}'" }.join("\n")}", level: :debug unless unfeasible.empty?

      log "#{unfeasible.size} services marked as infeasible with the following reasons: #{unfeasible.collect{ |u| u[:reason] }.uniq.join(', ')}", level: :info unless unfeasible.empty?

      unfeasible
    end

    def simplify_constraints(vrp)
      if vrp[:vehicles] && !vrp[:vehicles].empty?
        vrp[:vehicles].each{ |vehicle|
          if (vehicle[:force_start] || vehicle[:shift_preference] == 'force_start') && vehicle[:duration] && vehicle[:timewindow]
            vehicle[:timewindow][:end] = vehicle[:timewindow][:start] + vehicle[:duration]
            vehicle[:duration] = nil
          end
        }
      end

      vrp
    end

    def unassigned_services(vrp, unassigned_reason)
      vrp.services.flat_map{ |service|
        Array.new(service.visits_number) { |visit_index|
          {
            service_id: vrp.scheduling? ? "#{service.id}_#{visit_index + 1}_#{service.visits_number}" : service.id,
            type: service.type.to_s,
            point_id: service.activity.point_id,
            detail: build_detail(service, service.activity, service.activity.point, nil, nil, nil),
            reason: unassigned_reason
          }.delete_if{ |_k, v| !v }
        }
      }
    end

    def unassigned_shipments(vrp, unassigned_reason)
      vrp.shipments.flat_map{ |shipment|
        shipment.visits_number.times.flat_map{ |visit_index|
          [{
            pickup_shipment_id: vrp.scheduling? ? "#{shipment.id}_#{visit_index + 1}_#{shipment.visits_number}" : shipment.id.to_s,
            point_id: shipment.pickup.point_id,
            detail: build_detail(shipment, shipment.pickup, shipment.pickup.point, nil, nil, nil),
            reason: unassigned_reason
           }.delete_if{ |_k, v| !v },
           {
            delivery_shipment_id: vrp.scheduling? ? "#{shipment.id}_#{visit_index + 1}_#{shipment.visits_number}" : shipment.id.to_s,
            point_id: shipment.delivery.point_id,
            detail: build_detail(shipment, shipment.delivery, shipment.delivery.point, nil, nil, nil, true),
            reason: unassigned_reason
          }.delete_if{ |_k, v| !v }]
        }
      }
    end

    def unassigned_rests(vrp)
      vrp.vehicles.flat_map{ |vehicle|
        vehicle.rests.flat_map{ |rest|
          {
            rest_id: rest.id,
            detail: build_rest(rest, nil)
          }
        }
      }
    end

    def expand_vehicles_for_consistent_empty_result(vrp)
      periodic = Interpreters::PeriodicVisits.new(vrp)
      periodic.generate_vehicles(vrp)
    end

    def empty_result(solver, vrp, unassigned_reason = nil, already_expanded = true)
      vrp.vehicles = expand_vehicles_for_consistent_empty_result(vrp) if vrp.scheduling? && !already_expanded
      {
        solvers: [solver],
        cost: nil,
        cost_details: Models::CostDetails.new({}),
        iterations: nil,
        routes: vrp.vehicles.collect{ |vehicle| { vehicle_id: vehicle.id, activities: [] } },
        unassigned: (unassigned_services(vrp, unassigned_reason) +
                     unassigned_shipments(vrp, unassigned_reason) +
                     unassigned_rests(vrp)).flatten,
        elapsed: 0,
        total_distance: nil
      }
    end

    def kill; end
  end
end
