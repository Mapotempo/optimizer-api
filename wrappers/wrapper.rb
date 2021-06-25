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
      vrp.vehicles.none?{ |vehicle|
        vehicle.start_point.nil?
      }
    end

    def assert_vehicles_start_or_end(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.start_point.nil? && vehicle.end_point.nil?
      }
    end

    def assert_vehicles_no_capacity_initial(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |c| c.initial&.positive? }
      }
    end

    def assert_vehicles_no_alternative_skills(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.skills.size > 1 }
    end

    def assert_no_direct_shipments(vrp)
      vrp.shipments.none?(&:direct)
    end

    def assert_no_pickup_timewindows_after_delivery_timewindows(vrp)
      vrp.shipments.none? { |shipment|
        first_open = shipment.pickup.timewindows.min_by(&:start)
        last_close = shipment.delivery.timewindows.max_by(&:end)
        first_open && last_close && first_open.start + 86400 * (first_open.day_index || 0) >
          (last_close.end || 86399) + 86400 * (last_close.day_index || 0)
      }
    end

    def assert_services_no_priority(vrp)
      vrp.services.uniq(&:priority).size <= 1
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
      vrp.vehicles.none?{ |vehicle|
        vehicle.cost_late_multiplier&.positive?
      }
    end

    def assert_vehicles_no_late_multiplier_or_single_vehicle(vrp)
      assert_vehicles_no_late_multiplier(vrp) || assert_vehicles_only_one(vrp)
    end

    def assert_vehicles_no_overload_multiplier(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |capacity|
          capacity.overload_multiplier&.positive?
        }
      }
    end

    def assert_vehicles_no_force_start(vrp)
      vrp.vehicles.none?(&:force_start)
    end

    def assert_vehicles_no_duration_limit(vrp)
      vrp.vehicles.none?(&:duration)
    end

    def assert_vehicles_no_zero_duration(vrp)
      vrp.vehicles.none?{ |vehicle|
        vehicle.duration&.zero?
      }
    end

    def assert_services_no_late_multiplier(vrp)
      vrp.services.none?{ |service|
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
      vrp.shipments.none?{ |shipment|
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
      vrp.services.none?{ |service| service.sticky_vehicles.size > 1 } &&
        vrp.shipments.none?{ |shipment| shipment.sticky_vehicles.size > 1 }
    end

    def assert_no_relations_except_simple_shipments(vrp)
      vrp.relations.all?{ |r|
        (r.type == :shipment && r.linked_ids.size == 2) ||
          (r.linked_ids.empty? && r.linked_vehicle_ids.empty?) }
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

    def assert_no_activity_with_position(vrp)
      vrp.services.none?{ |service|
        (service.activities.to_a + [service.activity]).compact.any?{ |a| a.position != :neutral }
      }
    end

    def assert_no_vehicle_overall_duration_if_heuristic(vrp)
      vrp.vehicles.none?(&:overall_duration) || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_overall_duration(vrp)
      relation_array = %i[vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months]
      vrp.vehicles.none?(&:overall_duration) &&
        vrp.relations.none?{ |relation| relation_array.include?(relation.type&.to_sym) }
    end

    def assert_no_vehicle_distance_if_heuristic(vrp)
      vrp.vehicles.none?(&:distance) || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_possible_to_get_distances_if_maximum_ride_distance(vrp)
      vrp.vehicles.none?(&:maximum_ride_distance) || (vrp.points.all?{ |point| point.location&.lat } || vrp.matrices.all?{ |matrix| matrix.distance && !matrix.distance.empty? })
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

    def assert_no_service_duration_modifiers(vrp)
      # TODO: this assert can be relaxed by implementing a simplifier
      # if all vehicles are homogenous w.r.t. service_duration modifiers,
      # we can update the service durations directly and rewind it easily
      # see simplify_service_setup_duration_and_vehicle_setup_modifiers for an example
      vrp.vehicles.all?{ |vehicle|
        (vehicle.coef_service.nil? || vehicle.coef_service == 1) && vehicle.additional_service.to_i == 0
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

    def assert_no_complex_setup_durations(vrp)
      (
        vrp.services.all?{ |s| s.activity.setup_duration.to_i == 0 } || # either there is no setup duration
        ( # or it can be simplified by augmenting the time matrix
          vrp.services.group_by{ |s| s.activity.point }.all?{ |_point, service_group|
            service_group.uniq{ |s| s.activity.setup_duration.to_i }.size == 1
          } && vrp.vehicles.group_by{ |v| [v.coef_setup || 1, v.additional_setup.to_i] }.size <= 1
        )
      ) && vrp.shipments.all?{ |shipment|
        shipment.pickup.setup_duration.to_i == 0 &&
          shipment.delivery.setup_duration.to_i == 0
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
      else
        []
      end
    end

    def build_rest(rest, vehicle = nil)
      {
        duration: rest.duration,
        router_mode: vehicle&.router_mode,
        speed_multiplier: vehicle&.speed_multiplier
      }.delete_if{ |_k, v| v.nil? }
    end

    def build_skills(job)
      return nil unless job

      all_skills = job.skills - job.original_skills
      skills_to_output = []

      vehicle_cluster = all_skills.find{ |sk| sk.to_s.include?('vehicle_partition_') }
      skills_to_output << vehicle_cluster.to_s.split('_')[2..-1].join('_') if vehicle_cluster

      work_day_cluster = all_skills.find{ |sk| sk.to_s.include?('work_day_partition_') }
      skills_to_output << work_day_cluster.to_s.split('_')[3..-1].join('_') if work_day_cluster

      skills_to_output << job.original_skills

      skills_to_output.flatten
    end

    def build_detail(job, activity, point, day_index, job_load, vehicle, delivery = nil)
      {
        lat: point&.location&.lat,
        lon: point&.location&.lon,
        skills: build_skills(job),
        internal_skills: job&.skills,
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

    ALL_OR_NONE_RELATIONS = %i[shipment sequence meetup].freeze
    def add_unassigned(unfeasible, vrp, service, reason)
      # calls add_unassigned_internal for every service in an "ALL_OR_NONE_RELATION" with the service
      service_already_marked_unfeasible = unfeasible.any?{ |un| un[:original_service_id] == service.id }

      unless service_already_marked_unfeasible && reason.start_with?('In a relation with an unfeasible service: ')
        add_unassigned_internal(unfeasible, vrp, service, reason)
      end

      unless service_already_marked_unfeasible
        service.relations.each{ |relation|
          next unless ALL_OR_NONE_RELATIONS.include?(relation.type.to_sym) # TODO: remove to_sym when https://github.com/Mapotempo/optimizer-api/pull/145 is merged

          relation.linked_services&.each{ |service_in|
            next if service_in == service

            add_unassigned(unfeasible, vrp, service_in, "In a relation with an unfeasible service: #{service.id}")
          }
        }
      end

      unfeasible
    end

    def add_unassigned_internal(unfeasible, vrp, service, reason)
      if unfeasible.any?{ |unfeas| unfeas[:original_service_id] == service[:id] }
        # we update reason to have more details
        unfeasible.each{ |unfeas|
          next unless unfeas[:original_service_id] == service[:id]

          unfeas[:reason] += " && #{reason}"
        }
      else
        unfeasible.concat Array.new(service.visits_number){ |index|
          {
            original_service_id: service.id,
            service_id: vrp.scheduling? ? "#{service.id}_#{index + 1}_#{service.visits_number}" : service[:id],
            point_id: service.activity ? service.activity.point_id : nil,
            detail: build_detail(service, service.activity, service.activity.point, nil, nil, nil),
            type: 'service',
            reason: reason
          }
        }
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

        activities = [service.activity, service.activities].compact.flatten

        if activities.any?{ |a| a.timewindows.any?{ |tw| tw.start && tw.end && tw.start > tw.end } }
          add_unassigned(unfeasible, vrp, service, 'Service timewindows are infeasible')
        end

        if vehicle_max_shift && activities.collect(&:duration).min > vehicle_max_shift
          add_unassigned(unfeasible, vrp, service, 'Service duration greater than any vehicle timewindow')
        end

        unless find_vehicle(vrp, service)
          add_unassigned(unfeasible, vrp, service, 'No vehicle with compatible timewindow')
        end

        # unconsistency for planning
        next if !vrp.scheduling?

        unless vrp.can_affect_all_visits?(service)
          add_unassigned(unfeasible, vrp, service, 'Unconsistency between visit number and minimum lapse')
        end
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

    def simplifications
      # Simplification functions should have the following structure and implement
      # :simplify, :rewind, and :patch_result modes.
      #
      #       def simplify_X(vrp, result = nil, options = { mode: :simplify })
      #         # Description of the simplification
      #         case options[:mode]
      #         when :simplify
      #           # simplifies the constraint
      #         when :rewind
      #           nil # if nothing to do
      #         when :patch_result
      #           # patches the result
      #         else
      #           raise 'Unknown :mode option'
      #         end
      #         nil # returns nil because the objects are modified and this function is going to be called automatically
      #       end
      #
      # (If some modes are not necessary they can be merged -- e.g. `when :rewind, :patch_result` and have `nil`)
      # :patch_result is called for interim solutions and for the last solution before the :rewind is called.

      # TODO: We can simplify service timewindows if they are not necessary -- e.g., all service TWs are "larger" than
      # the vehicle TWs. (this modification needs to be rewinded incase we are in dicho or max_split)

      # TODO: infeasibility detection can be done with the simplification interface
      # (especially the part that is done after matrix)

      # Warning: The order might be important if the simplifications are interdependent.
      # The simplifications will be called in the following order and their corresponding rewind
      # and result patching operations will be called in the opposite order. This can be changed
      # if necessary.
      [
        :simplify_vehicle_duration,
        :simplify_vehicle_pause,
        :simplify_service_setup_duration_and_vehicle_setup_modifiers,
      ].freeze
    end

    def simplify_constraints(vrp)
      simplifications.each{ |simplification|
        self.send(simplification, vrp, nil, mode: :simplify)
      }

      vrp
    end

    def patch_simplified_constraints_in_result(result, vrp)
      return result unless result.is_a?(Hash)

      simplifications.reverse_each{ |simplification|
        self.send(simplification, vrp, result, mode: :patch_result)
      }

      result
    end

    def patch_and_rewind_simplified_constraints(vrp, result)
      # first patch the results (before the constraint are rewinded)
      patch_simplified_constraints_in_result(result, vrp) if result.is_a?(Hash)

      # then rewind the simplifications
      simplifications.reverse_each{ |simplification|
        self.send(simplification, vrp, nil, mode: :rewind)
      }

      vrp
    end

    def simplify_vehicle_duration(vrp, _result = nil, options = { mode: :simplify })
      # Simplify vehicle durations using timewindows if there is force_start
      case options[:mode]
      when :simplify
        vrp.vehicles&.each{ |vehicle|
          next unless (vehicle.force_start || vehicle.shift_preference == 'force_start') && vehicle.duration && vehicle.timewindow

          # Warning: this can make some services infeasible because vehicle cannot work after tw.start + duration
          vehicle.timewindow.end = vehicle.timewindow.start + vehicle.duration
          vehicle.duration = nil
        }
      when :rewind, :patch_result
        nil # TODO: this simplification can be moved to a higher level since it doesn't need rewinding or patching
      else
        raise 'Unknown :mode option'
      end
      nil
    end

    def simplify_vehicle_pause(vrp, result = nil, options = { mode: :simplify })
      # Simplifies vehicle pauses if there is no reason to keep them -- i.e., no services with timewindows
      case options[:mode]
      when :simplify
        return nil unless !vrp.scheduling? &&
                          vrp.relations&.none?{ |r| r.type == :maximum_duration_lapse } &&
                          vrp.services&.none?{ |service|
                            service.maximum_lapse ||
                            service.activity&.timewindows&.any? ||
                            service.activities&.any?{ |a| a.timewindows&.any? }
                          }

        vrp.vehicles&.each{ |vehicle|
          # TODO: ( vehicle.rests.size > 1) having multiple pauses to insert is harder but it is possible (need to pay
          # attention to not to shift the previously inserted pauses out of their TW, and if necessary make services
          # jump over them)
          #
          # TODO: (r.timewindows&.size.to_i > 1) having multiple TWs for pauses is possible but even harder.
          # If necessary, this implementation can be extended to handle this case by re-optimizing with or-tools
          # in a generic way
          next if vehicle.rests.size > 1 ||
                  vehicle.rests.any?{ |r| r.timewindows&.size.to_i > 1 || r.exclusion_cost.to_f.positive? }

          # If there is a service longer than the timewindow of the rest then we cannot be sure to
          # insert the pause without inducing unnecessary idle time
          max_service_duration = 0
          vrp.services.each{ |service|
            next unless (service.sticky_vehicles.empty? || service.sticky_vehicles == vehicle) &&
                        (service.skills - vehicle.skills).empty?

            service_duration = service.activity&.setup_duration.to_i +
                               service.activity&.duration.to_i +
                               service.activities&.collect{ |a| a.setup_duration.to_i + a.duration.to_i }&.max.to_i

            max_service_duration = service_duration if service_duration > max_service_duration
          }

          # NOTE: We could, in theory, add a TW to the "long" services so that they won't "block"
          # the pause location but then we need to create alternative copies of these services
          # for each vehicle, with different rest timewindows -- which kinda defeats the purpose.
          #
          # TODO: we could still simplify the other pauses of a vehicle even if some of the pauses cannot be
          # simplified due to `max_service_duration > rest.tw` but this would complicate the post-processing
          # e.g., we cannot shift everything later easily. At the moment, at most one pause is supported anyways.
          next if vehicle.rests.any?{ |rest|
            rest.timewindows.any? { |rest_tw|
              rest_start = rest_tw.start || vehicle.timewindow&.start || 0
              rest_end = rest_tw.end || vehicle.timewindow&.end || vehicle.duration && rest.duration && (rest_start + vehicle.duration - rest.duration) || 2**56
              max_service_duration > rest_end - rest_start
            }
          }

          vehicle.rests.each{ |rest|
            vehicle.duration -= rest.duration if vehicle.duration
            vehicle.timewindow.end -= rest.duration if vehicle.timewindow&.end
          }

          vehicle[:simplified_rest_ids] = vehicle[:rest_ids].dup
          vehicle[:rest_ids] = []
          vehicle[:simplified_rests] = vehicle.rests.dup
          vehicle.rests = []
        }

        vrp[:simplified_rests] = vrp.rests.select{ |r| vrp.vehicles.none?{ |v| v.rests.include?(r) } }
        vrp.rests -= vrp[:simplified_rests]
      when :rewind
        # take the modifications back in case the vehicle is moved to another sub-problem
        vrp.vehicles&.each{ |vehicle|
          next unless vehicle[:simplified_rest_ids]&.any?

          vehicle[:rest_ids].concat vehicle[:simplified_rest_ids]
          vehicle[:simplified_rest_ids] = nil
          vehicle.rests.concat vehicle[:simplified_rests]
          vehicle[:simplified_rests] = nil

          vehicle.rests.each{ |rest|
            vehicle.duration += rest.duration if vehicle.duration
            vehicle.timewindow.end += rest.duration if vehicle.timewindow&.end
          }
        }

        if vrp[:simplified_rests]
          vrp.rests.concat vrp[:simplified_rests]
          vrp[:simplified_rests] = nil
        end
      when :patch_result
        # correct the result with respect to simplifications
        pause_and_depot = %w[depot rest].freeze
        vrp.vehicles&.each{ |vehicle|
          next unless vehicle[:simplified_rest_ids]&.any?

          route = result[:routes].find{ |r| r[:vehicle_id] == vehicle.id }
          no_cost = route[:activities].none?{ |a| pause_and_depot.exclude?(a[:type]) }

          # first shift every activity all the way to the left (earlier) if the route starts after
          # the vehicle TW.start so that it is easier to do the insertions since there is no TW on
          # services, we can do this even if force_start is false
          shift_amount = vehicle.timewindow&.start.to_i - (route[:start_time] || vehicle.timewindow&.start).to_i
          shift_route_times(route, shift_amount) if shift_amount < 0

          # insert the rests back into the route and adjust the timing of the activities coming after the pause
          vehicle[:simplified_rests].each{ |rest|
            # find the first service that finishes after the TW.end of pause
            insert_rest_at =
              unless rest.timewindows&.last&.end.nil?
                route[:activities].index{ |activity|
                  (activity[:end_time] || activity[:begin_time]) > rest.timewindows.last.end
                }
              end

            insert_rest_at, rest_start =
              if insert_rest_at.nil?
                # reached the end of the route or there is no TW.end on the pause
                # in any case, insert the rest at the end (before the end depot if it exists)
                if route[:activities].empty?
                  # no activity
                  [route[:activities].size, vehicle.timewindow&.start || 0]
                elsif route[:activities].last[:type] == 'depot' && vehicle.end_point
                  # last activity is an end depot
                  [route[:activities].size - 1, route[:activities].last[:begin_time]]
                else
                  # last activity is not an end depot
                  # either the last activity is a service and it has an end_time
                  # or it is the begin depot and we can use the begin_time
                  [route[:activities].size, route[:activities].last[:end_time] || route[:activities].last[:begin_time]]
                end
              else
                # there is a clear position to insert
                activity_after_rest = route[:activities][insert_rest_at]

                rest_start = activity_after_rest[:begin_time]
                # if this the first service of this location then we need to consider the setup_duration
                rest_start -= activity_after_rest[:detail][:setup_duration].to_i if activity_after_rest[:travel_time] > 0
                if rest.timewindows&.last&.end && rest_start > rest.timewindows.last.end
                  rest_start -= activity_after_rest[:travel_time]
                  rest_start = [rest_start, rest.timewindows&.first&.start.to_i].max # don't induce idle_time if within travel_time
                end

                [insert_rest_at, rest_start]
              end

            # Above we try to make the pause as late as possible, and if rest_start is still not after TW.start
            # we need to correct it. Checking with TW.start (not TW.end) is important in case there is force_start.
            idle_time_created_by_inserted_pause = [rest.timewindows&.first&.start.to_i - rest_start, 0].max
            rest_start = rest.timewindows.first.start if idle_time_created_by_inserted_pause > 0

            if vehicle.timewindow&.end && rest_start > vehicle.timewindow&.end
              raise 'An unexpected error happened while calculating the pause location' # this should not be possible
            end

            if !vehicle.force_start && vehicle.shift_preference != 'force_start'
              # if no force_start, shift everything to the right so that inserting pause wouldn't create any idle time
              shift_route_times(route, idle_time_created_by_inserted_pause)
              idle_time_created_by_inserted_pause = 0
            end

            route[:activities].insert(insert_rest_at, { rest_id: rest.id, type: 'rest', begin_time: rest_start,
                                                        end_time: rest_start + rest.duration,
                                                        departure_time: rest_start + rest.duration,
                                                        detail: build_rest(rest) })

            shift_route_times(route, idle_time_created_by_inserted_pause + rest.duration, insert_rest_at + 1)

            next if no_cost

            cost_increase = vehicle.cost_time_multiplier.to_f * rest.duration +
                            vehicle.cost_waiting_time_multiplier.to_f * idle_time_created_by_inserted_pause

            if route[:cost_details]
              route[:cost_details].time += cost_increase
              route[:cost_details].total += cost_increase
            end
            if result[:cost_details]
              result[:cost_details].time += cost_increase
              result[:cost_details].total += cost_increase
            end
            result[:cost] += cost_increase # totals are not calculated yet
          }
        }
      else
        raise 'Unknown :mode option'
      end
      nil
    end

    def simplify_service_setup_duration_and_vehicle_setup_modifiers(vrp, result = nil, options = { mode: :simplify })
      # Simplifies setup durations if there is no reason to keep them.
      # If all services of a point p has the same setup_duration s_p,
      # and if all vehicles using the same matrix have the same coef_setup and additional_setup;
      # then the time matrix can be modified so that for all i, t'_ip = t_ip + s_p
      # (arriving point p takes longer to include the setup_duration)
      # and the setup duration s_p can be removed from the problem.
      # This way solvers like vroom which does not support setup duration can be used.
      return nil if vrp.scheduling?

      case options[:mode]
      when :simplify
        # simplifies the constraint
        return nil if vrp.vehicles.group_by(&:matrix_id).any?{ |_m_id, v_group|
                        v_group.group_by{ |v| [v.coef_setup || 1, v.additional_setup.to_i] }.size > 1
                      }

        vehicles_grouped_by_matrix_id = vrp.vehicles.group_by(&:matrix_id)
        vrp.services.group_by{ |s| s.activity.point }.each{ |point, service_group|
          next if service_group.any?{ |s| s.activity.setup_duration.to_i == 0 } || # no need if no setup_duration
                  service_group.uniq{ |s| s.activity.setup_duration }.size > 1 # can't if setup_durations are different

          setup_duration = service_group.first.activity.setup_duration

          service_group.each{ |service|
            service.activity[:simplified_setup_duration] = service.activity.setup_duration
            service.activity.setup_duration = nil
          }

          vrp.matrices.each{ |matrix|
            vehicle = vehicles_grouped_by_matrix_id[matrix.id].first
            coef_setup = vehicle.coef_setup || 1
            additional_setup = vehicle.additional_setup.to_i

            # WARNING: Here we apply the setup_duration for the points which has non-zero
            # distance (in time!) between them because this is the case in optimizer-ortools.
            # If this is changed to per "destination" (i.e., point.id) based setup duration
            # then the following logic needs to be updated. Basically we need to do each_with_index
            # and apply the setup duration increment to every pair except index == point.matrix_index
            # even if they were 0 in the first place.
            matrix.time.each{ |row|
              row[point.matrix_index] += (coef_setup * setup_duration + additional_setup).to_i if row[point.matrix_index] > 0
            }
          }
        }

        return nil unless vrp.services.any?{ |s| s[:simplified_setup_duration] }

        vrp.vehicles.each{ |vehicle|
          vehicle[:simplified_coef_setup] = vehicle.coef_setup
          vehicle[:simplified_additional_setup] = vehicle.additional_setup
          vehicle.coef_setup = nil
          vehicle.additional_setup = nil
        }
      when :rewind
        # take it back in case in dicho and there will be re-optimization
        return nil unless vrp.services.any?{ |s| s[:simplified_setup_duration] }

        vehicles_grouped_by_matrix_id = vrp.vehicles.group_by(&:matrix_id)

        vrp.services.group_by{ |s| s.activity.point }.each{ |point, service_group|
          setup_duration = service_group.first[:simplified_setup_duration].to_i

          next if setup_duration.zero?

          vrp.matrices.each{ |matrix|
            vehicle = vehicles_grouped_by_matrix_id[matrix.id].first
            coef_setup = vehicle[:simplified_coef_setup] || 1
            additional_setup = vehicle[:simplified_additional_setup].to_i

            matrix.time.each{ |row|
              row[point.matrix_index] -= (coef_setup * setup_duration + additional_setup).to_i  if row[point.matrix_index] > 0
            }
          }

          service_group.each{ |service|
            service.setup_duration = service[:simplified_setup_duration]
            service[:simplified_setup_duration] = nil
          }
        }

        vrp.vehicles.each{ |vehicle|
          vehicle.coef_setup = vehicle[:simplified_coef_setup]
          vehicle.additional_setup = vehicle[:simplified_additional_setup]
          vehicle[:simplified_coef_setup] = nil
          vehicle[:simplified_additional_setup] = nil
        }
      when :patch_result
        # patches the result
        # the travel_times need to be decreased and setup_duration need to be increased by
        # (coef_setup * setup_duration + additional_setup) if setup_duration > 0 and travel_time > 0
        return nil unless vrp.services.any?{ |s| s[:simplified_setup_duration] }

        vehicles_grouped_by_vehicle_id = vrp.vehicles.group_by(&:id)
        services_grouped_by_point_id = vrp.services.group_by{ |s| s.activity.point }

        overall_total_travel_time_correction = 0
        result[:routes].each{ |route|
          vehicle = vehicles_grouped_by_vehicle_id[route[:vehicle_id]].first
          coef_setup = vehicle[:simplified_coef_setup] || 1
          additional_setup = vehicle[:simplified_additional_setup].to_i

          total_travel_time_correction = 0
          route[:activities].each{ |activity|
            next if activity[:travel_time].to_i.zero?

            setup_duration = services_grouped_by_point_id[activity[:point_id]].first[:simplified_setup_duration].to_i

            next if setup_duration.zero?

            time_correction = coef_setup * setup_duration + additional_setup

            total_travel_time_correction += time_correction
            activity[:detail][:setup_duration] = time_correction.round
            activity[:travel_time] -= activity[:detail][:setup_duration]
          }

          overall_total_travel_time_correction += total_travel_time_correction
          route[:total_travel_time] -= total_travel_time_correction.round
        }
        result[:total_travel_time] -= overall_total_travel_time_correction.round

        result[:unassigned].each{ |activity|
          setup_duration = services_grouped_by_point_id[activity[:point_id]].first[:simplified_setup_duration].to_i

          activity[:detail][:setup_duration] = setup_duration
        }
      else
        raise 'Unknown :mode option'
      end
      nil
    end

    def shift_route_times(route, shift_amount, shift_start_index = 0)
      return if shift_amount == 0

      raise 'Cannot shift the route, there are not enough activities' if shift_start_index > route[:activities].size

      route[:start_time] += shift_amount if shift_start_index == 0
      route[:activities].each_with_index{ |activity, index|
        next if index < shift_start_index

        activity[:begin_time] += shift_amount
        activity[:end_time] += shift_amount if activity[:end_time]
        activity[:departure_time] += shift_amount if activity[:departure_time]
      }
      route[:end_time] += shift_amount if route[:end_time]
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
      OptimizerWrapper.parse_result(vrp, {
        solvers: [solver],
        cost: nil,
        cost_details: Models::CostDetails.new({}),
        iterations: nil,
        routes: vrp.vehicles.collect{ |vehicle|
          OptimizerWrapper.empty_route(vrp, vehicle)
        },
        unassigned: (unassigned_services(vrp, unassigned_reason) +
                     unassigned_shipments(vrp, unassigned_reason) +
                     unassigned_rests(vrp)).flatten,
        elapsed: 0,
        total_distance: nil
      })
    end

    def kill; end
  end
end
