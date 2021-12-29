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
      []
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
      vrp.vehicles.size == 1 && !vrp.schedule?
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
        vehicle.capacities.any?{ |c| c.initial && c.initial < c.limit }
      }
    end

    def assert_vehicles_no_alternative_skills(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.skills.size > 1 }
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
      vrp.services.none?{ |service| service.sticky_vehicles.size > 1 }
    end

    def assert_no_relations_except_simple_shipments(vrp)
      vrp.relations.all?{ |r|
        next true if r.linked_ids.empty? && r.linked_vehicle_ids.empty?
        next false unless r.type == :shipment && r.linked_ids.size == 2

        quantities = Hash.new {}
        vrp.units.each{ |unit| quantities[unit.id] = [] }
        r.linked_services.first.quantities.each{ |q| quantities[q.unit.id] << q.value }
        r.linked_services.last.quantities.each{ |q| quantities[q.unit.id] << q.value }
        quantities.all?{ |_unit, values|
          values.empty? || (values.size == 2 && values.first >= 0 && values.first == -values.last)
        }
      }
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

    def assert_vehicle_tw_if_periodic(vrp)
      !vrp.periodic_heuristic? ||
        vrp.vehicles.all?{ |vehicle|
          vehicle.timewindow || vehicle.sequence_timewindows&.size&.positive?
        }
    end

    def assert_if_periodic_heuristic_then_schedule(vrp)
      !vrp.periodic_heuristic? || vrp.schedule?
    end

    def assert_first_solution_strategy_is_possible(vrp)
      vrp.preprocessing_first_solution_strategy.empty? || (!vrp.resolution_evaluate_only && !vrp.resolution_batch_heuristic)
    end

    def assert_first_solution_strategy_is_valid(vrp)
      vrp.preprocessing_first_solution_strategy.empty? ||
        (vrp.preprocessing_first_solution_strategy[0] != 'self_selection' && !vrp.periodic_heuristic? || vrp.preprocessing_first_solution_strategy.size == 1) &&
          vrp.preprocessing_first_solution_strategy.all?{ |strategy| strategy == 'self_selection' || strategy == 'periodic' || OptimizerWrapper::HEURISTICS.include?(strategy) }
    end

    def assert_no_planning_heuristic(vrp)
      !vrp.periodic_heuristic?
    end

    def assert_only_force_centroids_if_kmeans_method(vrp)
      vrp.preprocessing_kmeans_centroids.nil? || vrp.preprocessing_partition_method == 'balanced_kmeans'
    end

    def assert_no_evaluation(vrp)
      !vrp.resolution_evaluate_only
    end

    def assert_only_one_visit(vrp)
      vrp.services.all?{ |service| service.visits_number == 1 }
    end

    def assert_no_periodic_if_evaluation(vrp)
      !vrp.periodic_heuristic? || !vrp.resolution_evaluate_only
    end

    def assert_route_if_evaluation(vrp)
      !vrp.resolution_evaluate_only || vrp.routes && !vrp.routes.empty?
    end

    def assert_wrong_vehicle_shift_preference_with_heuristic(vrp)
      (vrp.vehicles.map(&:shift_preference).uniq - [:minimize_span] - ['minimize_span']).empty? || !vrp.periodic_heuristic?
    end

    def assert_no_activity_with_position(vrp)
      vrp.services.none?{ |service|
        (service.activities.to_a + [service.activity]).compact.any?{ |a| a.position != :neutral }
      }
    end

    def assert_no_vehicle_overall_duration_if_heuristic(vrp)
      vrp.vehicles.none?(&:overall_duration) || !vrp.periodic_heuristic?
    end

    def assert_no_overall_duration(vrp)
      relation_array = %i[vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months]
      vrp.vehicles.none?(&:overall_duration) &&
        vrp.relations.none?{ |relation| relation_array.include?(relation.type&.to_sym) }
    end

    def assert_no_vehicle_distance_if_heuristic(vrp)
      vrp.vehicles.none?(&:distance) || !vrp.periodic_heuristic?
    end

    def assert_possible_to_get_distances_if_maximum_ride_distance(vrp)
      vrp.vehicles.none?(&:maximum_ride_distance) || (vrp.points.all?{ |point| point.location&.lat } || vrp.matrices.all?{ |matrix| matrix.distance && !matrix.distance.empty? })
    end

    def assert_no_vehicle_free_approach_or_return_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return } || !vrp.periodic_heuristic?
    end

    def assert_no_free_approach_or_return(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return }
    end

    def assert_no_vehicle_limit_if_heuristic(vrp)
      vrp.resolution_vehicle_limit.nil? || vrp.resolution_vehicle_limit >= vrp.vehicles.size || !vrp.periodic_heuristic?
    end

    def assert_no_same_point_day_if_no_heuristic(vrp)
      !vrp.resolution_same_point_day || vrp.periodic_heuristic?
    end

    def assert_no_allow_partial_if_no_heuristic(vrp)
      vrp.resolution_allow_partial_assignment || vrp.periodic_heuristic?
    end

    def assert_no_first_solution_strategy(vrp)
      vrp.preprocessing_first_solution_strategy.empty? || vrp.preprocessing_first_solution_strategy == ['self_selection']
    end

    def assert_solver(vrp)
      vrp.resolution_solver
    end

    def assert_solver_if_not_periodic(vrp)
      vrp.resolution_solver || vrp.preprocessing_first_solution_strategy && vrp.periodic_heuristic?
    end

    def assert_clustering_compatible_with_periodic_heuristic(vrp)
      (!vrp.preprocessing_first_solution_strategy || !vrp.periodic_heuristic?) || !vrp.preprocessing_cluster_threshold && !vrp.preprocessing_max_split_size
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
      vrp.services.none?(&:exclusion_cost)
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
      vrp.routes.empty? || !vrp.schedule? || vrp.periodic_heuristic?
    end

    # TODO: Need a better way to represent solver preference
    def assert_small_minimum_duration(vrp)
      vrp.resolution_minimum_duration.nil? || vrp.vehicles.empty? || vrp.resolution_minimum_duration / vrp.vehicles.size < 5000
    end

    def assert_no_cost_fixed(vrp)
      vrp.vehicles.all?{ |vehicle| vehicle.cost_fixed.nil? || vehicle.cost_fixed.zero? } || vrp.vehicles.map(&:cost_fixed).uniq.size == 1
    end

    def assert_no_complex_setup_durations(vrp)
      vrp.services.all?{ |s| s.activity.setup_duration.to_i == 0 } || # either there is no setup duration
      ( # or it can be simplified by augmenting the time matrix
        vrp.services.group_by{ |s| s.activity.point }.all?{ |_point, service_group|
          service_group.uniq{ |s| s.activity.setup_duration.to_i }.size == 1
        } && vrp.vehicles.group_by{ |v| [v.coef_setup || 1, v.additional_setup.to_i] }.size <= 1
      )
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
      first_day = vrp.schedule_range_indices[:start]
      last_day = vrp.schedule_range_indices[:end]
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

        days = vrp.schedule? ? (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |day| day } : [0]
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
          add_unassigned(unfeasible, vrp, service, 'Unreachable')
        }
      }

      unfeasible
    end

    ALL_OR_NONE_RELATIONS = %i[shipment sequence meetup].freeze
    def add_unassigned(unfeasible, vrp, service, reason)
      # calls add_unassigned_internal for every service in an "ALL_OR_NONE_RELATION" with the service
      service_already_marked_unfeasible = !!unfeasible[service.id]

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
      if unfeasible[service.id]
        # we update reason to have more details
        unfeasible[service.id].each{ |un| un[:reason] += " && #{reason}" }
      else
        service_detail = build_detail(service, service.activity, service.activity.point, nil, nil, nil)

        unfeasible[service.id] = []

        service.visits_number.times{ |index|
          unfeasible[service.id] << {
            original_service_id: service.original_id,
            pickup_shipment_id: service.type == :pickup && service.original_id,
            delivery_shipment_id: service.type == :delivery && service.original_id,
            service_id: vrp.schedule? ? "#{service.id}_#{index + 1}_#{service.visits_number}" : service.id,
            point_id: service.activity&.point_id,
            detail: service_detail,
            type: service.type,
            reason: reason
          }.delete_if{ |_k, v| v.nil? }
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

    def possible_days_are_consistent(vrp, service)
      return false if service.first_possible_days.any?{ |d| d > vrp.schedule_range_indices[:end] }

      return false if service.last_possible_days.any?{ |d| d < vrp.schedule_range_indices[:start] }

      consistency_for_each_visit =
        (0..service.visits_number - 1).none?{ |v_i|
          service.first_possible_days[v_i] &&
            service.last_possible_days[v_i] &&
            service.first_possible_days[v_i] > service.last_possible_days[v_i]
        }

      return false unless consistency_for_each_visit

      visit_index = 1
      consistency_in_between_visits = true
      current_day = service.first_possible_days.first
      while visit_index < service.last_possible_days.size && consistency_in_between_visits
        this_visit_day = [service.first_possible_days[visit_index], current_day + (service.minimum_lapse || 1)].max
        if this_visit_day <= current_day ||
           (service.last_possible_days[visit_index] && this_visit_day > service.last_possible_days[visit_index]) ||
           this_visit_day > vrp.schedule_range_indices[:end]
          consistency_in_between_visits = false
        else
          current_day = this_visit_day
          visit_index += 1
        end
      end

      consistency_in_between_visits
    end

    def detect_unfeasible_services(vrp)
      unfeasible = {}

      vehicle_max_shift = compute_vehicles_shift(vrp.vehicles)
      vehicle_max_capacities = compute_vehicles_capacity(vrp)

      vrp.services.each{ |service|
        service.quantities.each{ |qty|
          if vehicle_max_capacities[qty.unit_id] && qty.value && vehicle_max_capacities[qty.unit_id] < qty.value.abs
            add_unassigned(unfeasible, vrp, service, 'Service quantity greater than any vehicle capacity')
            break
          end
        }

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

        detect_inconsistent_relation_timewindows_od_service(vrp, unfeasible, service)

        # Planning inconsistency
        next if !vrp.schedule?

        unless possible_days_are_consistent(vrp, service)
          add_unassigned(unfeasible, vrp, service, 'Provided possible days do not allow service to be assigned')
        end

        unless vrp.can_affect_all_visits?(service)
          add_unassigned(unfeasible, vrp, service, 'Inconsistency between visit number and minimum lapse')
        end
      }

      unfeasible
    end

    def detect_inconsistent_relation_timewindows_od_service(vrp, unfeasible, service)
      # In a POSITION_TYPES relationship s1->s2, s2 cannot be served
      # if its timewindows end before any timewindow of s1 starts
      service.relations.each{ |relation|
        next unless Models::Relation::POSITION_TYPES.include?(relation[:type])

        max_earliest_arrival = 0
        relation.linked_services.map{ |service_in|
          next unless service_in.activity.timewindows.any?

          earliest_arrival = service_in.activity.timewindows.map{ |tw|
            (tw.day_index || 0) * 86400 + (tw.start || 0)
          }.min
          latest_arrival = service_in.activity.timewindows.map{ |tw|
            tw.day_index ? tw.day_index * 86400 + (tw.end || 86399) : (tw.end || 2147483647)
          }.max

          max_earliest_arrival = [max_earliest_arrival, earliest_arrival].compact.max

          if latest_arrival < max_earliest_arrival
            add_unassigned(unfeasible, vrp, service_in, 'Inconsistent timewindows within relations of service')
          end
        }
      }
    end

    def service_reachable_by_vehicle_within_timewindows(vrp, activity, vehicle)
      vehicle_start = vehicle.timewindow&.start || vehicle.sequence_timewindows.collect(&:start).min || 0
      vehicle_end =
        if vehicle.cost_late_multiplier&.positive? # vehicle lateness is allowed
          vehicle.timewindow&.end ?
            vehicle.timewindow.end + vehicle.timewindow.maximum_lateness :
            vehicle.sequence_timewindows.collect{ |tw| tw.end + tw.maximum_lateness }.max
        else # vehicle lateness is not allowed
          vehicle.timewindow&.end || vehicle.sequence_timewindows.collect(&:end).max
        end

      matrix = vrp.matrices.find{ |m| m.id == vehicle.matrix_id }

      time_to_go = vehicle.start_point&.matrix_index ? matrix.time[vehicle.start_point&.matrix_index][activity.point.matrix_index] : 0
      time_back = vehicle.end_point&.matrix_index ? matrix.time[activity.point.matrix_index][vehicle.end_point&.matrix_index] : 0

      earliest_arrival = vehicle_start + time_to_go
      earliest_back = earliest_arrival + activity.duration + time_back

      return false if vehicle_end && earliest_back > vehicle_end

      return false if vehicle.duration && earliest_back - earliest_arrival > vehicle.duration

      if activity.timewindows.any?
        if activity.late_multiplier&.positive? # service lateness is allowed
          return false if activity.timewindows.none?{ |tw| tw.end.nil? || earliest_arrival <= tw.end + tw.maximum_lateness }
        else # service lateness is not allowed
          return false if activity.timewindows.none?{ |tw| tw.end.nil? || earliest_arrival <= tw.end }
        end
        if vehicle_end
          latest_arrival = vehicle_end - time_back - activity.duration
          return false if activity.timewindows.all?{ |tw| latest_arrival < tw.start }
        end
      end

      if vehicle.distance
        # check distances constraints
        dist_to_go = vehicle.start_point&.matrix_index ? matrix.distance[vehicle.start_point&.matrix_index][activity.point.matrix_index] : 0
        dist_back = vehicle.end_point&.matrix_index ? matrix.distance[activity.point.matrix_index][vehicle.end_point&.matrix_index] : 0

        return false if dist_to_go + dist_back > vehicle.distance
      end

      true
    end

    def check_distances(vrp, unfeasible)
      unfeasible = check(vrp, :time, unfeasible)
      unfeasible = check(vrp, :distance, unfeasible)
      unfeasible = check(vrp, :value, unfeasible)

      vrp.services.each{ |service|
        no_vehicle_compatible =
          vrp.vehicles.none?{ |vehicle|
            (service.activity ? [service.activity] : service.activities).any?{ |activity|
              (service.skills.empty? || vehicle.skills.any?{ |skill_set| (service.skills - skill_set).empty? }) &&
                (service.sticky_vehicles.empty? || service.sticky_vehicles.include?(vehicle)) &&
                service_reachable_by_vehicle_within_timewindows(vrp, activity, vehicle)
            }
          }

        next unless no_vehicle_compatible

        add_unassigned(unfeasible, vrp, service, 'No compatible vehicle can reach this service while respecting all constraints')
      }

      unless unfeasible.empty?
        log "Following services marked as infeasible:\n#{unfeasible.values.flatten.group_by{ |u| u[:reason] }.collect{ |g, set| "#{(set.size < 20) ? set.collect{ |s| s[:service_id] }.join(', ') : "#{set.size} services"}\n with reason '#{g}'" }.join("\n")}", level: :debug
        log "#{unfeasible.size} services marked as infeasible with the following reasons: #{unfeasible.values.flatten.collect{ |u| u[:reason] }.uniq.join(', ')}", level: :info
      end

      unfeasible
    end

    def simplifications
      # Simplification functions should have the following structure and implement
      # :simplify, :rewind, and :patch_result modes.
      #
      #       def simplify_X(vrp, result = nil, options = { mode: :simplify })
      #         # Description of the simplification
      #         simplification_active = false
      #         case options[:mode]
      #         when :simplify
      #           # simplifies the constraint
      #           simplification_active = true if applied
      #         when :rewind
      #           nil # if nothing to do
      #           simplification_active = true if applied
      #         when :patch_result
      #           # patches the result
      #           simplification_active = true if applied
      #         else
      #           raise 'Unknown :mode option'
      #         end
      #         simplification_active # returns true if the simplification is applied/rewinded/patched
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
        :prioritize_first_available_trips_and_vehicles,
        :simplify_vehicle_duration,
        :simplify_vehicle_pause,
        :simplify_complex_multi_pickup_or_delivery_shipments,
        :simplify_service_setup_duration_and_vehicle_setup_modifiers,
      ].freeze
    end

    def simplify_constraints(vrp)
      simplifications.each{ |simplification|
        simplification_activated = self.send(simplification, vrp, nil, mode: :simplify)
        log "#{simplification} simplification is activated" if simplification_activated
      }

      vrp
    end

    def patch_simplified_constraints_in_result(result, vrp)
      return result unless result.is_a?(Hash)

      simplifications.reverse_each{ |simplification|
        result_patched = self.send(simplification, vrp, result, mode: :patch_result)
        log "#{simplification} simplification is active, result is patched" if result_patched
      }

      result
    end

    def patch_and_rewind_simplified_constraints(vrp, result)
      # first patch the results (before the constraint are rewinded)
      patch_simplified_constraints_in_result(result, vrp) if result.is_a?(Hash)

      # then rewind the simplifications
      simplifications.reverse_each{ |simplification|
        simplification_rewinded = self.send(simplification, vrp, nil, mode: :rewind)
        log "#{simplification} simplification is rewinded" if simplification_rewinded
      }

      vrp
    end

    def prioritize_first_available_trips_and_vehicles(vrp, result = nil, options = { mode: :simplify })
      # For each vehicle group, it applies a small but increasing fixed_cost so that or-tools can
      # distinguish two identical vehicles and use the one that comes first.
      # This is to handle two cases:
      #  i.  Skipped intermediary trips of the same vehicle_trips relation
      #  ii. Skipped intermediary "similar" vehicles of vrp.vehicles list

      simplification_active = false
      case options[:mode]
      when :simplify
        # cannot do prioritization by fixed_cost if the vehicles have different costs
        # TODO: if needed this limitation can be partially removed for the cases where a group of vehicles
        # have one cost and another group has another cost. The below logic can be applied such groups of vehicles
        # separately but the code would be messier. Wait for a real use case.
        return unless vrp.vehicles.uniq(&:cost_fixed).size == 1

        simplification_active = true

        all_vehicle_trips_relations = vrp.relations.select{ |v| v.type == :vehicle_trips }
        leader_trip_vehicles = all_vehicle_trips_relations.map{ |r| r.linked_vehicle_ids.first }
        loner_vehicles = vrp.vehicles.map(&:id) - all_vehicle_trips_relations.flat_map(&:linked_vehicle_ids)

        cost_increment = 1e-4 # cost is multiplied with 1e6 (CUSTOM_BIGNUM_COST) inside optimizer-ortools
        cost_adjustment = cost_increment

        # Below both (i. and ii.) cases are handled
        # The vehicles that are the "leader" trip of a vehicle trip relation handle the
        # remaining trips of that relation.
        vrp.vehicles.each{ |vehicle|
          case vehicle.id
          when *leader_trip_vehicles
            vehicle_trips = all_vehicle_trips_relations.find{ |r| r.linked_vehicle_ids.first == vehicle.id }
            linked_vehicles = vehicle_trips.linked_vehicle_ids.map{ |lv_id| vrp.vehicles.find{ |v| v.id == lv_id } }

            linked_vehicles.each{ |linked_vehicle|
              # WARNING: this logic depends on the fact that each vehicle can appear in at most one vehicle_trips
              # relation ensured by check_vehicle_trips_relation_consistency (models/concerns/validate_data.rb)
              linked_vehicle[:fixed_cost_before_adjustment] = linked_vehicle.cost_fixed
              linked_vehicle.cost_fixed += cost_adjustment
              cost_adjustment += cost_increment
            }
          when *loner_vehicles
            vehicle[:fixed_cost_before_adjustment] = vehicle.cost_fixed
            vehicle.cost_fixed += cost_adjustment
            cost_adjustment += cost_increment
          end
        }
      when :rewind
        # rewinds the simplification
        return nil unless vrp.vehicles.any?{ |v| v[:fixed_cost_before_adjustment] }

        simplification_active = true

        vrp.vehicles.each{ |vehicle|
          next if vehicle[:fixed_cost_before_adjustment].nil?

          vehicle.cost_fixed = vehicle[:fixed_cost_before_adjustment]
          vehicle[:fixed_cost_before_adjustment] = nil
        }
      when :patch_result
        # patches the result
        return nil unless vrp.vehicles.any?{ |v| v[:fixed_cost_before_adjustment] }

        simplification_active = true

        result[:routes].each{ |route|
          vehicle = vrp.vehicles.find{ |v| v.id == route[:vehicle_id] }

          # correct the costs if the vehicle had cost adjustment and it is used
          next unless vehicle[:fixed_cost_before_adjustment] && route[:cost_details]&.fixed&.positive?

          cost_diff = route[:cost_details].fixed - vehicle[:fixed_cost_before_adjustment]

          route[:cost_details].fixed -= cost_diff
          result[:cost_details].fixed -= cost_diff
        }
        result[:cost] = result[:cost_details].total
      else
        raise 'Unknown :mode option'
      end
      simplification_active # returns true if the simplification is applied/rewinded/patched
    end

    def simplify_complex_multi_pickup_or_delivery_shipments(vrp, result = nil, options = { mode: :simplify })
      # Simplify vehicle durations using timewindows if there is force_start
      simplification_active = false
      case options[:mode]
      when :simplify
        return nil if vrp.services.any?{ |s| s.activities.any? } # alternative activities is not yet supported

        services_in_multi_shipment_relations, vrp.services =
          vrp.services.partition{ |s| s.relations.count{ |r| r.type == :shipment } > 1 }

        return nil unless services_in_multi_shipment_relations.any?

        # TODO: if needed the following check can be removed by extending the logic to initial solutions by replacing
        # the original service id with the new expanded service ids in the routes (and rewind it afterwards)
        # but if the complex relations are already in feasible initial routes then it might not worth it.
        # So we can wait for a real use case arrives and we have an instance to test.
        if services_in_multi_shipment_relations.any?{ |s| vrp.routes.any?{ |r| r.mission_ids.include?(s.id) }}
          vrp.services += services_in_multi_shipment_relations
          return nil
        end

        simplification_active = true

        expanded_services = []
        expanded_relations = []
        sequence_relations = []

        multi_shipment_relations, vrp.relations =
          vrp.relations.partition{ |r| services_in_multi_shipment_relations.any?{ |s| s.relations.include?(r) } }

        services_in_multi_shipment_relations.each{ |service|
          shipment_relations, non_shipment_relations = service.relations.partition{ |r| r.type == :shipment }

          if non_shipment_relations.any?
            raise 'Cannot handle complex (multi-pickup-single-delivery, single-pickup-multi-delivery) ' \
                  'shipments if the services appear in other relations.'
            # TODO: it is not hard to lift this limitation;
            # if needed these non_shipment_relations can be
            # duplicated for each new service created for shipment_relations
          end

          total_quantity_per_unit_id = Hash.new(0)
          all_shipment_quantities = shipment_relations.collect{ |relation|
            # WARNING: Here we assume that there are two services in the relation -- a pair of pickup and delivery
            relation.linked_services.find{ |i| i != service }.quantities.each{ |quantity|
              total_quantity_per_unit_id[quantity.unit_id] += quantity.value
            }
          }
          extra_per_quantity = service.quantities.collect{ |quantity|
            (quantity.value + total_quantity_per_unit_id[quantity.unit_id]) / shipment_relations.size.to_f
          }

          sequence_relation_ids = []

          shipment_relations.each_with_index{ |relation, index|
            new_service = Helper.deep_copy(service,
                                           override: { relations: [] },
                                           shallow_copy: [:unit, :point])
            sequence_relation_ids << new_service.id

            if index < shipment_relations.size - 1
              # all timing will be handled by the first service (of the sequence relation)
              # correct the TW.end for the succeeding services (so that they can start)
              activity = new_service.activity
              activity.timewindows.each{ |tw| tw.end += activity.duration if tw&.end }
              activity.additional_value = 0
              activity.setup_duration += activity.duration
              activity.duration = 0

              # inserting the remaining parts of a multipart service should be of highest priority
              new_service.priority = 0 # 0 is the highest priority
            end

            # share the quantity between the duplicated services (including the left-overs)
            new_service.quantities.each_with_index{ |quantity, q_index|
              shipment_quantity = all_shipment_quantities[index].find{ |q| q.unit_id == quantity.unit_id }&.value.to_f
              quantity.value = -shipment_quantity + extra_per_quantity[q_index]
            }

            new_shipment_relation = Helper.deep_copy(
              relation,
              override: {
                linked_ids: nil, # this line can be removed when linked_ids is replaced with linked_service_ids
                linked_services: relation.linked_services.map{ |s| s.id == service.id ? new_service : s }
              }
            )

            new_service.relations << new_shipment_relation

            expanded_relations << new_shipment_relation
            expanded_services << new_service
          }

          # For some reason, or-tools performance is better when the sequence relation is defined in the inverse order.
          # Note that, activity.duration's are set to zero except the last duplicated service
          # (so we model exactly the same constraint).
          sequence_relations << Models::Relation.create(type: :sequence, linked_ids: sequence_relation_ids.reverse)
        }

        vrp[:simplified_complex_shipments] = {
          original_services: services_in_multi_shipment_relations,
          original_relations: multi_shipment_relations,
          expanded_services: expanded_services,
          expanded_relations: expanded_relations,
          sequence_relations: sequence_relations,
        }

        # TODO: old services still point to the old relations
        # but the vrp.relations.linked_ids returns the correct services
        vrp.services.concat(expanded_services)
        vrp.relations.concat(sequence_relations)
        vrp.relations.concat(expanded_relations)
      when :rewind
        return nil unless vrp[:simplified_complex_shipments]

        simplification_active = true

        vrp.services -= vrp[:simplified_complex_shipments][:expanded_services]
        vrp.relations -= vrp[:simplified_complex_shipments][:expanded_relations]
        vrp.relations -= vrp[:simplified_complex_shipments][:sequence_relations]
        vrp.services.concat(vrp[:simplified_complex_shipments][:original_services])
        vrp.relations.concat(vrp[:simplified_complex_shipments][:original_relations])
      when :patch_result
        return nil unless vrp[:simplified_complex_shipments]

        simplification_active = true

        simplification_data = vrp[:simplified_complex_shipments]

        simplification_data[:original_services].each{ |service|
          # delete the unassigned expanded version of service and calculate how many of them planned/unassigned
          unassigned_exp_ser_count = result[:unassigned].size
          unassigned_exp_ser_count -= result[:unassigned].delete_if{ |uns| uns[:original_service_id] == service.original_id }.size
          planned_exp_ser_count = simplification_data[:expanded_services].count{ |s| s.original_id == service.original_id } - unassigned_exp_ser_count

          if planned_exp_ser_count == 0
            # if all of them were unplanned
            # replace the deleted unassigned expanded ones with one single original un-expanded service
            result[:unassigned] << {
              original_service_id: service.original_id,
              service_id: service.id,
              point_id: service.activity.point_id,
              detail: build_detail(service, service.activity, service.activity.point, nil, nil, nil),
            }
          else
            # replace the planned one(s) into one single unexpanded original service
            first_exp_ser_activity = nil
            last_exp_ser_activity = nil
            insert_location = nil
            deleted_exp_ser_count = 0
            result[:routes].each{ |route|
              route[:activities].delete_if.with_index{ |activity, index|
                if activity[:original_service_id] == service.original_id
                  insert_location ||= index
                  first_exp_ser_activity ||= activity # first_exp_ser_activity has the travel and timing info
                  last_exp_ser_activity = activity # last_exp_ser_activity has the quantity info
                  deleted_exp_ser_count += 1
                  true
                elsif deleted_exp_ser_count == planned_exp_ser_count
                  break
                end
              }

              next unless insert_location # expanded activity(ies) of service is found in this route

              # stop.. something went wrong if duplicated services are planned on different vehicles
              raise 'Simplification cannot patch the result if duplicated services are planned on different vehicles' unless deleted_exp_ser_count == planned_exp_ser_count

              merged_activity = first_exp_ser_activity.merge(last_exp_ser_activity) { |key, first, last|
                if key == :service_id
                  service.id
                elsif key == :detail && first != last
                  # if only one expanded service is planned (i.e., first == last), then first will be correct
                  # if not correct the quantities
                  first[:quantities].each_with_index{ |first_quantity, q_ind|
                    last_quantity = last[:quantities][q_ind][:unit] == first_quantity[:unit] && last[:quantities][q_ind]
                    last_quantity ||= last[:quantities].find{ |q| q[:unit] == first_quantity[:unit] }
                    value_correction = last_quantity[:current_load] - first_quantity[:current_load]
                    first_quantity[:current_load] = last_quantity[:current_load]

                    next if first_quantity[:value].nil? && value_correction == 0

                    first_quantity[:value] = first_quantity[:value].to_f + value_correction
                  }
                  first
                else
                  first
                end
              }

              route[:activities].insert(insert_location, merged_activity)

              break
            }
          end
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_vehicle_duration(vrp, _result = nil, options = { mode: :simplify })
      # Simplify vehicle durations using timewindows if there is force_start
      simplification_active = false
      case options[:mode]
      when :simplify
        vrp.vehicles&.each{ |vehicle|
          next unless (vehicle.force_start || vehicle.shift_preference == 'force_start') && vehicle.duration && vehicle.timewindow

          simplification_active ||= true
          # Warning: this can make some services infeasible because vehicle cannot work after tw.start + duration
          vehicle.timewindow.end = vehicle.timewindow.start + vehicle.duration
          vehicle.duration = nil
        }
      when :rewind, :patch_result
        nil # TODO: this simplification can be moved to a higher level since it doesn't need rewinding or patching
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_vehicle_pause(vrp, result = nil, options = { mode: :simplify })
      # Simplifies vehicle pauses if there is no reason to keep them -- i.e., no services with timewindows
      simplification_active = false
      case options[:mode]
      when :simplify
        return nil unless !vrp.schedule? &&
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
          next if (vehicle.timewindow&.end && vehicle.cost_late_multiplier) ||
                  vehicle.rests.size > 1 ||
                  vehicle.rests.any?{ |r|
                    r.timewindows&.size.to_i > 1 || r.late_multiplier.to_f.positive? || r.exclusion_cost.to_f.positive?
                  }

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
              rest_end = rest_tw.end || vehicle.timewindow&.end || vehicle.duration && rest.duration && (rest_start + vehicle.duration - rest.duration) || 2147483647
              max_service_duration > rest_end - rest_start
            }
          }

          vehicle.rests.each{ |rest|
            vehicle.duration -= rest.duration if vehicle.duration
            vehicle.timewindow.end -= rest.duration if vehicle.timewindow&.end
          }

          vehicle[:simplified_rests] = vehicle.rests.dup
          vehicle.rests = []

          simplification_active ||= vehicle[:simplified_rests].any?
        }

        vrp[:simplified_rests] = vrp.rests.select{ |r| vrp.vehicles.none?{ |v| v.rests.include?(r) } }
        vrp.rests -= vrp[:simplified_rests]
      when :rewind
        # take the modifications back in case the vehicle is moved to another sub-problem
        vrp.vehicles&.each{ |vehicle|
          next unless vehicle[:simplified_rests]&.any?

          simplification_active ||= true

          vehicle.rests += vehicle[:simplified_rests]
          vehicle[:simplified_rests] = nil

          vehicle.rests.each{ |rest|
            vehicle.duration += rest.duration if vehicle.duration
            vehicle.timewindow.end += rest.duration if vehicle.timewindow&.end
          }
        }

        if vrp[:simplified_rests]
          vrp.rests += vrp[:simplified_rests]
          vrp[:simplified_rests] = nil
        end
      when :patch_result
        # correct the result with respect to simplifications
        pause_and_depot = %w[depot rest].freeze
        vrp.vehicles&.each{ |vehicle|
          next unless vehicle[:simplified_rests]&.any?

          simplification_active ||= true

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


            route[:cost_details]&.time += cost_increase
            result[:cost_details]&.time += cost_increase
            result[:cost] += cost_increase # totals are not calculated yet
          }
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_service_setup_duration_and_vehicle_setup_modifiers(vrp, result = nil, options = { mode: :simplify })
      # Simplifies setup durations if there is no reason to keep them.
      # If all services of a point p has the same setup_duration s_p,
      # and if all vehicles using the same matrix have the same coef_setup and additional_setup;
      # then the time matrix can be modified so that for all i, t'_ip = t_ip + s_p
      # (arriving point p takes longer to include the setup_duration)
      # and the setup duration s_p can be removed from the problem.
      # This way solvers like vroom which does not support setup duration can be used.
      return nil if vrp.periodic_heuristic?
      simplification_active = false

      case options[:mode]
      when :simplify
        # simplifies the constraint
        return nil if vrp.vehicles.group_by(&:matrix_id).any?{ |_m_id, v_group|
                        v_group.group_by{ |v| [v.coef_setup || 1, v.additional_setup.to_i] }.size > 1
                      } || vrp.services.any?{ |s| s.activity.nil? }

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

        return nil unless vrp.services.any?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vrp.vehicles.each{ |vehicle|
          vehicle[:simplified_coef_setup] = vehicle.coef_setup
          vehicle[:simplified_additional_setup] = vehicle.additional_setup
          vehicle.coef_setup = nil
          vehicle.additional_setup = nil
        }
      when :rewind
        # take it back in case in dicho and there will be re-optimization
        return nil unless vrp.services.any?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vehicles_grouped_by_matrix_id = vrp.vehicles.group_by(&:matrix_id)

        vrp.services.group_by{ |s| s.activity.point }.each{ |point, service_group|
          setup_duration = service_group.first.activity[:simplified_setup_duration].to_i

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
            service.activity.setup_duration = service.activity[:simplified_setup_duration]
            service.activity[:simplified_setup_duration] = nil
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
        return nil unless vrp.services.any?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vehicles_grouped_by_vehicle_id = vrp.vehicles.group_by(&:id)
        services_grouped_by_point_id = vrp.services.group_by{ |s| s.activity.point_id }

        overall_total_travel_time_correction = 0
        result[:routes].each{ |route|
          vehicle = vehicles_grouped_by_vehicle_id[route[:vehicle_id]].first
          coef_setup = vehicle[:simplified_coef_setup] || 1
          additional_setup = vehicle[:simplified_additional_setup].to_i

          total_travel_time_correction = 0
          route[:activities].each{ |activity|
            next if activity[:service_id].nil? || activity[:travel_time].to_i.zero?

            setup_duration = services_grouped_by_point_id[activity[:point_id]].first.activity[:simplified_setup_duration].to_i

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
          setup_duration = services_grouped_by_point_id[activity[:point_id]].first.activity[:simplified_setup_duration].to_i

          activity[:detail][:setup_duration] = setup_duration
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def shift_route_times(route, shift_amount, shift_start_index = 0)
      return if shift_amount == 0

      raise 'Cannot shift the route, there are not enough activities' if shift_start_index > route[:activities].size

      route[:start_time] += shift_amount if shift_start_index == 0
      route[:activities].each_with_index{ |activity, index|
        next if index < shift_start_index

        activity[:begin_time] += shift_amount
        activity[:end_time] += shift_amount if activity[:end_time]
        activity[:waiting_time] -= [shift_amount, activity[:waiting_time]].min if activity[:waiting_time]
        activity[:departure_time] += shift_amount if activity[:departure_time]
      }
      route[:total_time] += shift_amount if route[:total_time]
      route[:end_time] += shift_amount if route[:end_time]
    end

    def unassigned_services(vrp, unassigned_reason)
      vrp.services.flat_map{ |service|
        Array.new(service.visits_number) { |visit_index|
          {
            service_id: vrp.schedule? ? "#{service.id}_#{visit_index + 1}_#{service.visits_number}" : service.id,
            type: service.type.to_s,
            point_id: service.activity.point_id,
            detail: build_detail(service, service.activity, service.activity.point, nil, nil, nil),
            reason: unassigned_reason
          }.delete_if{ |_k, v| !v }
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
      vrp.vehicles = expand_vehicles_for_consistent_empty_result(vrp) if vrp.schedule? && !already_expanded
      OptimizerWrapper.parse_result(vrp, {
        solvers: [solver],
        cost: vrp.vehicles.empty? ? Helper.fixnum_max : nil,
        cost_details: Models::CostDetails.create({}),
        iterations: nil,
        routes: vrp.vehicles.collect{ |vehicle|
          OptimizerWrapper.empty_route(vrp, vehicle)
        },
        unassigned: (unassigned_services(vrp, unassigned_reason) +
                     unassigned_rests(vrp)).flatten,
        elapsed: 0,
        total_distance: nil
      })
    end

    def kill; end
  end
end
