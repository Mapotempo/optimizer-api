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
    def initialize(cache, hash = {})
      @cache = cache
      @tmp_dir = hash[:tmp_dir] || Dir.tmpdir
      @threads = hash[:threads] || 1
    end

    def solver_constraints
      [
       :assert_no_pickup_timewindows_after_delivery_timewindows,
      ]
    end

    def inapplicable_solve?(vrp)
      solver_constraints.select{ |constraint|
        !self.send(constraint, vrp)
      }
    end

    def assert_points_same_definition(vrp)
      (vrp.points.all?(&:location) || vrp.points.none?(&:location)) && (vrp.points.all?(&:matrix_index) || vrp.points.none?(&:matrix_index))
    end

    def assert_units_only_one(vrp)
      vrp.units.size <= 1
    end

    def assert_vehicles_only_one(vrp)
      vrp.vehicles.size == 1 && !vrp.schedule_range_indices
    end

    def assert_vehicles_at_least_one(vrp)
      vrp.vehicles.size >= 1 && (vrp.vehicles.none?(&:duration) || vrp.vehicles.any?{ |vehicle| vehicle.duration && vehicle.duration > 0 })
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

    def assert_vehicles_no_timewindow(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.timewindow.nil?
      }
    end

    def assert_vehicles_no_rests(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.rests.empty?
      }
    end

    def assert_services_no_capacities(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.capacities.empty?
      }
    end

    def assert_vehicles_capacities_only_one(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.size > 1
      }
    end

    def assert_vehicles_no_capacity_initial(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |c| c.initial && c.initial > 0 }
      }
    end

    def assert_vehicles_no_alternative_skills(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.skills || vehicle.skills.size > 1
      }
    end

    def assert_no_shipments(vrp)
      vrp.shipments.empty?
    end

    def assert_no_shipments_with_multiple_timewindows(vrp)
      vrp.shipments.empty? || vrp.shipments.none? { |shipment|
        shipment.pickup.timewindows.size > 1 || shipment.delivery.timewindows.size > 1
      }
    end

    def assert_no_pickup_timewindows_after_delivery_timewindows(vrp)
      vrp.shipments.empty? || vrp.shipments.none? { |shipment|
        first_open = shipment.pickup.timewindows.min_by(&:start)
        last_close = shipment.delivery.timewindows.max_by(&:end)
        first_open && last_close && (first_open.start || 0) + 86400 * (first_open.day_index || 0) >
          (last_close.end || 86399 ) + 86400 * (last_close.day_index || 0)
      }
    end

    def assert_services_no_skills(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.skills.empty?
      }
    end

    def assert_services_no_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity ? !service.activity.timewindows.empty? : service.activities.none?{ |activity| activity.timewindows.size.positive? }
      }
    end

    def assert_services_no_multiple_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity ? service.activity.timewindows.size > 1 : service.activities.none?{ |activity| activity.timewindows.size > 1 }
      }
    end

    def assert_services_at_most_two_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity ? service.activity.timewindows.size > 2 : service.activities.none?{ |activity| activity.timewindows.size > 2 }
      }
    end

    def assert_services_no_priority(vrp)
      vrp.services.empty? || vrp.services.all?{ |service|
        service.priority == 4
      }
    end

    def assert_vehicles_objective(vrp)
      vrp.vehicles.all?{ |vehicle|
        vehicle.cost_time_multiplier && vehicle.cost_time_multiplier > 0 ||
        vehicle.cost_distance_multiplier && vehicle.cost_distance_multiplier > 0 ||
        vehicle.cost_waiting_time_multiplier && vehicle.cost_waiting_time_multiplier > 0 ||
        vehicle.cost_value_multiplier && vehicle.cost_value_multiplier > 0
      }
    end

    def assert_vehicles_no_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.cost_late_multiplier && vehicle.cost_late_multiplier > 0
      }
    end

    def assert_vehicles_no_overload_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |capacity|
          capacity.overload_multiplier && capacity.overload_multiplier > 0
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
        vehicle.duration && vehicle.duration == 0
      }
    end

    def assert_services_no_late_multiplier(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity ? service.activity&.late_multiplier&.positive? : service.activities.none?{ |activity| activity&.late_multiplier.positive? }
      }
    end

    def assert_shipments_no_late_multiplier(vrp)
      vrp.shipments.empty? || vrp.shipments.none?{ |shipment|
        shipment.pickup.late_multiplier && shipment.pickup.late_multiplier > 0 || shipment.delivery.late_multiplier && shipment.delivery.late_multiplier > 0
      }
    end

    def assert_services_quantities_only_one(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.quantities.size > 1
      }
    end

    def assert_matrices_only_one(vrp)
      vrp.vehicles.collect{ |vehicle|
        vehicle.matrix_id || [vehicle.router_mode.to_sym, vehicle.router_dimension, vehicle.speed_multiplier]
      }.uniq.size == 1
    end

    def assert_square_matrix(vrp)
      dimensions = vrp.vehicles.collect(&:dimensions).flatten.uniq
      vrp.matrices.all?{ |matrix|
        dimensions.all?{ |dimension|
          matrix[dimension].nil? || matrix[dimension].all?{ |line| matrix[dimension].size == line.size }
        }
      }
    end

    def assert_correctness_provided_matrix_indices(vrp)
      dimensions = vrp.vehicles.collect(&:dimensions).flatten.uniq
      max_matrix_index = vrp.points.collect(&:matrix_index).max || 0
      vrp.matrices.all?{ |matrix|
        dimensions.all?{ |dimension|
          matrix[dimension].nil? || matrix[dimension].size > max_matrix_index && matrix[dimension].all?{ |line| line.size > max_matrix_index }
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

    def assert_one_vehicle_only_or_no_sticky_vehicle(vrp)
      vrp.vehicles.size <= 1 ||
        (vrp.services.empty? || vrp.services.all?{ |service|
          service.sticky_vehicles.empty?
        }) && (vrp.shipments.empty? || vrp.shipments.all?{ |shipment|
          shipment.sticky_vehicles.empty?
        })
    end

    def assert_no_relations(vrp)
      vrp.relations.empty? || vrp.relations.all?{ |relation| relation.linked_ids.empty? && relation.linked_vehicle_ids.empty? }
    end

    def assert_no_zones(vrp)
      vrp.zones.empty?
    end

    def assert_zones_only_size_one_alternative(vrp)
      vrp.zones.empty? || vrp.zones.all?{ |zone| zone.allocations.none?{ |alternative| alternative.size > 1 }}
    end

    def assert_no_value_matrix(vrp)
      vrp.matrices.none?(&:value)
    end

    def assert_no_routes(vrp)
      vrp.routes.empty? || vrp.routes.all?{ |route| route.mission_ids.empty? }
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

    def assert_at_least_one_mission(vrp)
      !vrp.services.empty? || !vrp.shipments.empty?
    end

    def assert_end_optimization(vrp)
      vrp.resolution_duration || vrp.resolution_iterations_without_improvment
    end

    def assert_vehicles_no_end_time_or_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.all?{ |vehicle|
        !vehicle.timewindow || vehicle.cost_late_multiplier && vehicle.cost_late_multiplier > 0
      }
    end

    def assert_no_distance_limitation(vrp)
      vrp[:vehicles].none?{ |vehicle| vehicle[:distance] }
    end

    def assert_vehicle_tw_if_schedule(vrp)
      vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' ||
      vrp[:vehicles].all?{ |vehicle|
        vehicle[:timewindow] && (vehicle[:timewindow][:start] || vehicle[:timewindow][:end]) ||
        vehicle[:sequence_timewindows] && vehicle[:sequence_timewindows].any?{ |tw| (tw[:start] || tw[:end]) }
      }
    end

    def assert_if_sequence_tw_then_schedule(vrp)
      vrp.vehicles.find{ |vehicle| vehicle[:sequence_timewindows] }.nil? || vrp.schedule_range_indices
    end

    def assert_if_periodic_heuristic_then_schedule(vrp)
      vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' || vrp.schedule_range_indices
    end

    def assert_first_solution_strategy_is_possible(vrp)
      vrp.preprocessing_first_solution_strategy.nil? || !vrp.resolution_evaluate_only && vrp.resolution_several_solutions.nil? && !vrp.resolution_batch_heuristic
    end

    def assert_first_solution_strategy_is_valid(vrp)
      vrp.preprocessing_first_solution_strategy.nil? ||
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

    def assert_no_scheduling_if_evaluation(vrp)
      !vrp.schedule_range_indices || !vrp.resolution_evaluate_only
    end

    def assert_route_if_evaluation(vrp)
      !vrp.resolution_evaluate_only || vrp[:routes] && !vrp[:routes].empty?
    end

    def assert_wrong_vehicle_shift_preference_with_heuristic(vrp)
      (vrp.vehicles.collect{ |vehicle| vehicle[:shift_preference] }.uniq - [:minimize_span] - ['minimize_span']).size == 0 || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_vehicle_overall_duration_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle[:overall_duration] } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_vehicle_distance_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle[:distance] } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_possible_to_get_distances_if_maximum_ride_distance(vrp)
      !vrp.vehicles.any?{ |vehicle| vehicle[:maximum_ride_distance] } || (vrp.points.all?{ |point| point[:location] && point[:location][:lat] } || vrp.matrices.all?{ |matrix| matrix[:distance] && !matrix[:distance].empty? })
    end

    def assert_no_skills_if_heuristic(vrp)
      vrp.services.none?{ |service| !service[:skills].empty? } || vrp.vehicles.none?{ |vehicle| !vehicle[:skills].flatten.empty? } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' || !vrp.preprocessing_partitions.empty?
    end

    def assert_no_vehicle_free_approach_or_return_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle[:free_approach] || vehicle[:free_return] } || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
    end

    def assert_no_service_exclusion_cost_if_heuristic(vrp)
      vrp.services.collect{ |service| service[:exclusion_cost] }.compact.empty? || vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
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
      vrp.preprocessing_first_solution_strategy.nil? || vrp.preprocessing_first_solution_strategy.empty? || vrp.preprocessing_first_solution_strategy == ['self_selection']
    end

    def assert_solver(vrp)
      vrp.resolution_solver
    end

    def assert_solver_if_not_periodic(vrp)
      (vrp.resolution_solver && vrp.resolution_solver_parameter != -1) || vrp.preprocessing_first_solution_strategy && (vrp.preprocessing_first_solution_strategy.first == 'periodic')
    end

    def assert_clustering_compatible_with_scheduling_heuristic(vrp)
      (!vrp.preprocessing_first_solution_strategy || !vrp.preprocessing_first_solution_strategy.include?('periodic')) || !vrp.preprocessing_cluster_threshold && !vrp.preprocessing_max_split_size
    end

    def assert_lat_lon_for_partition(vrp)
      vrp.preprocessing_partition_method.nil? || vrp.points.all?{ |pt| pt[:location] && pt[:location][:lat] && pt[:location][:lon] }
    end

    def assert_work_day_partitions_only_schedule(vrp)
      vrp.preprocessing_partitions.empty? || vrp.preprocessing_partitions.size < 2 ||
      vrp.schedule_range_indices &&
      (vrp.services.none?{ |service| service[:minimum_lapse] } || vrp.services.collect{ |service| service[:minimum_lapse] }.compact.min >= 7)
    end

    def assert_vehicle_entity_only_before_work_day(vrp)
      vehicle_entity_index = vrp.preprocessing_partitions.find_index{ |partition| partition[:entity] == 'vehicle' }
      work_day_entity_index = vrp.preprocessing_partitions.find_index{ |partition| partition[:entity] == 'work_day' }
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

    def assert_no_relation_with_scheduling_heuristic(vrp)
      (!vrp.preprocessing_first_solution_strategy || !vrp.preprocessing_first_solution_strategy.include?('periodic')) || (!vrp.relations || vrp.relations.empty?)
    end

    def assert_no_route_if_clustering(vrp)
      vrp.routes.empty? || vrp.preprocessing_partitions.empty?
    end

    def assert_route_date_or_indice_if_periodic(vrp)
      !vrp.preprocessing_first_solution_strategy.to_a.include?('periodic') || vrp.routes.all?{ |route| route[:indice] }
    end

    def assert_missions_in_routes_do_exist(vrp)
      (vrp.routes.to_a.collect{ |r| r[:mission_ids] }.flatten.uniq - vrp.services.collect{ |s| s[:id] }).empty?
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

    def assert_no_route_if_schedule_without_periodic_heuristic(vrp)
      vrp.routes.empty? || !vrp.schedule_range_indices || vrp.preprocessing_first_solution_strategy.include?('periodic')
    end

    def solve_synchronous?(vrp)
      false
    end

    def build_timewindows(activity, day_index)
      nil
    end

    def build_quantities(job, job_loads)
      nil
    end

    def compatible_day?(vrp, service, t_day, vehicle)
      first_day = vrp[:schedule][:range_indices] ? vrp[:schedule][:range_indices][:start] : vrp[:schedule][:range_date][:start]
      last_day = vrp[:schedule][:range_indices] ? vrp[:schedule][:range_indices][:end] : vrp[:schedule][:range_date][:end]
      (first_day..last_day).any?{ |day|
        s_ok = !t_day.nil? ? t_day == day : !service.unavailable_visit_day_indices&.include?(day)
        v_ok = !vehicle.unavailable_work_day_indices&.include?(day)
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

        days = vrp.schedule_range_indices ? (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |day| day } : [0]
        days.any?{ |day|
          vehicle_work_days.include?(day % 7) && !vehicle.unavailable_work_day_indices.include?(day) &&
            !service.unavailable_visit_day_indices.include?(day) &&
            (service_timewindows.empty? || vehicle_timewindows.empty? ||
              service_timewindows.any?{ |tw|
                (tw.day_index.nil? || tw.day_index == day % 7) &&
                  vehicle_lateness ||
                  service_lateness ||
                  vehicle_timewindows.any?{ |v_tw|
                    days_compatible = !v_tw.day_index || !tw.day_index || v_tw.day_index == tw.day_index
                    days_compatible &&
                      (v_tw.start.nil? || tw.end.nil? || v_tw.start < tw.end) &&
                      (v_tw.end.nil? || tw.start.nil? || v_tw.end > tw.start)
                  }
              })
        }
      }

      available_vehicle
    end

    def check(vrp, dimension, unfeasible)
      return unfeasible if vrp.matrices.any?{ |matrix| matrix[dimension].nil? || matrix[dimension].size == 1 }

      matrix_indices = vrp.points.map(&:matrix_index).uniq
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
        next if (column_cpt[index] < vrp.matrices.first[dimension].size - 1) && (line_cpt[index] < vrp.matrices.first[dimension].size - 1)

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
            service_id: vrp.schedule_range_indices ? "#{service.id}_#{index}_#{service.visits_number}" : service[:id],
            point_id: service.activity ? service.activity.point_id : nil,
            detail: {
              lat: service.activity && service.activity.point.location ? service.activity.point.location.lat : nil,
              lon: service.activity && service.activity.point.location ? service.activity.point.location.lon : nil,
              setup_duration: service.activity ? service.activity.setup_duration : nil,
              duration: service.activity ? service.activity.duration : nil,
              timewindows: service.activity && service.activity.timewindows ? service.activity.timewindows.collect{ |tw| { start: tw.start, end: tw.end }} : [],
              quantities: service.quantities ? service.quantities.collect{ |qte| { unit: qte.unit.id, value: qte.value } } : nil
            },
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
        elsif vehicle.sequence_timewindows.all?{ |tw| tw.start && tw.end }
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
          if vehicle_max_capacities[qty.unit_id] && qty.value && vehicle_max_capacities[qty.unit_id] < qty.value
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
        next if !vrp.schedule_range_indices

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
            if (vehicle.cost_time_multiplier&.positive? && !vehicle.cost_late_multiplier&.positive? && ((vehicle.timewindow&.start && vehicle.timewindow&.end) || vehicle.sequence_timewindows&.size&.positive?)) ||
               (vehicle.cost_distance_multiplier&.positive? && vehicle.distance)

              metric = vehicle.cost_time_multiplier&.positive? ? :time : :distance

              start_index = vehicle.start_point&.matrix_index
              end_index = vehicle.end_point&.matrix_index

              cost = 0
              cost += vrp.matrices[0][metric][start_index][index]                   if start_index
              cost += activity.duration                                             if metric == :time
              cost += vrp.matrices[0][metric][index][end_index]                     if end_index

              if metric == :time
                vehicle_available_time = vehicle.timewindow.end - vehicle.timewindow.start if vehicle.timewindow
                vehicle_available_time = vehicle.sequence_timewindows.collect{ |tw| tw.end - tw.start }.max if vehicle.sequence_timewindows&.size&.positive?
                vehicle_available_time >= cost
              else
                vehicle.distance >= cost
              end
            else
              true
            end
          }
        }

        if !reachable_by_a_vehicle
          add_unassigned(unfeasible, vrp, service, 'Service cannot be served due to vehicle parameters -- e.g., timewindow, distance limit, etc.')
          next
        end

        # Check via service time-windows
        service_unreachable_within_its_tw = false
        if !(service.activity ? service.activity.timewindows : service.activities.collect(&:timewindows).flatten).empty?
          service_unreachable_within_its_tw = vrp.matrices.all?{ |matrix| matrix[:time] } &&  (service.activity ? [service.activity] : service.activites).all?{ |activity|
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
                  tw.start && latest_arrival && latest_arrival < tw.start
                }
              end
              timely_arrival_not_possible || timely_return_not_possible
            }
          }
        end

        add_unassigned(unfeasible, vrp, service, 'Service cannot be reached within its timewindows') if service_unreachable_within_its_tw
      }

      log "Following services marked as infeasible:\n#{unfeasible.group_by{ |u| u[:reason] }.collect{ |g, set| "#{set.collect{ |s| s[:service_id] }.join(', ')}\n with reason '#{g}'" }.join("\n")}", level: :debug unless unfeasible.empty?

      unfeasible
    end

    def simplify_constraints(vrp)
      if vrp[:vehicles] && !vrp[:vehicles].empty?
        vrp[:vehicles].each{ |vehicle|
          if (vehicle[:force_start] || vehicle[:shift_preference] == "force_start") && vehicle[:duration] && vehicle[:timewindow]
            vehicle[:timewindow][:end] = vehicle[:timewindow][:start] + vehicle[:duration]
            vehicle[:duration] = nil
          end
        }
      end

      vrp
    end

    def kill
    end
  end
end
