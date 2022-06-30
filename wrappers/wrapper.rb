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
      (vrp.points.all?(&:location) || vrp.points.none?(&:location)) && (vrp.points.all?(&:matrix_index) ||
        vrp.points.none?(&:matrix_index))
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

    def assert_no_relations_except_simple_shipments(vrp)
      vrp.relations.all?{ |r|
        next true if r.linked_service_ids.empty? && r.linked_vehicle_ids.empty?
        next false unless r.type == :shipment && r.linked_service_ids.size == 2

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
      problem_units =
        vrp.units.collect{ |unit|
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

    def assert_no_empty_or_fill(vrp)
      vrp.services.none?{ |service|
        service.quantities.any?{ |q| q.empty || q.fill }
      }
    end

    def assert_end_optimization(vrp)
      vrp.configuration.resolution.duration || vrp.configuration.resolution.iterations_without_improvment
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
      vrp.configuration.preprocessing.first_solution_strategy.empty? || (!vrp.configuration.resolution.evaluate_only &&
        !vrp.configuration.resolution.batch_heuristic)
    end

    def assert_first_solution_strategy_is_valid(vrp)
      vrp.configuration.preprocessing.first_solution_strategy.empty? ||
        (vrp.configuration.preprocessing.first_solution_strategy[0] != 'self_selection' && !vrp.periodic_heuristic? ||
          vrp.configuration.preprocessing.first_solution_strategy.size == 1) &&
          vrp.configuration.preprocessing.first_solution_strategy.all?{ |strategy|
            strategy == 'self_selection' || strategy == 'periodic' || OptimizerWrapper::HEURISTICS.include?(strategy)
          }
    end

    def assert_no_planning_heuristic(vrp)
      !vrp.periodic_heuristic?
    end

    def assert_only_force_centroids_if_kmeans_method(vrp)
      first_partition = vrp.configuration.preprocessing&.partitions&.first
      first_partition.nil? || first_partition.centroids.nil? || first_partition.technique == 'balanced_kmeans'
    end

    def assert_no_evaluation(vrp)
      !vrp.configuration.resolution.evaluate_only
    end

    def assert_only_one_visit(vrp)
      vrp.services.all?{ |service| service.visits_number == 1 }
    end

    def assert_no_periodic_if_evaluation(vrp)
      !vrp.periodic_heuristic? || !vrp.configuration.resolution.evaluate_only
    end

    def assert_route_if_evaluation(vrp)
      !vrp.configuration.resolution.evaluate_only || vrp.routes && !vrp.routes.empty?
    end

    def assert_wrong_vehicle_shift_preference_with_heuristic(vrp)
      (vrp.vehicles.map(&:shift_preference).uniq - [:minimize_span] - ['minimize_span']).empty? ||
        !vrp.periodic_heuristic?
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
      vrp.vehicles.none?(&:maximum_ride_distance) ||
        (
          vrp.points.all?{ |point| point.location&.lat } ||
          vrp.matrices.all?{ |matrix| matrix.distance && !matrix.distance.empty? }
        )
    end

    def assert_no_vehicle_free_approach_or_return_if_heuristic(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return } || !vrp.periodic_heuristic?
    end

    def assert_no_free_approach_or_return(vrp)
      vrp.vehicles.none?{ |vehicle| vehicle.free_approach || vehicle.free_return }
    end

    def assert_no_vehicle_limit_if_heuristic(vrp)
      vrp.configuration.resolution.vehicle_limit.nil? ||
        vrp.configuration.resolution.vehicle_limit >= vrp.vehicles.size || !vrp.periodic_heuristic?
    end

    def assert_no_same_point_day_if_no_heuristic(vrp)
      !vrp.configuration.resolution.same_point_day || vrp.periodic_heuristic?
    end

    def assert_no_allow_partial_if_no_heuristic(vrp)
      vrp.configuration.resolution.allow_partial_assignment || vrp.periodic_heuristic?
    end

    def assert_no_first_solution_strategy(vrp)
      vrp.configuration.preprocessing.first_solution_strategy.empty? ||
        vrp.configuration.preprocessing.first_solution_strategy == ['self_selection']
    end

    def assert_solver(vrp)
      vrp.configuration.resolution.solver
    end

    def assert_solver_if_not_periodic(vrp)
      vrp.configuration.resolution.solver ||
        vrp.configuration.preprocessing.first_solution_strategy && vrp.periodic_heuristic?
    end

    def assert_clustering_compatible_with_periodic_heuristic(vrp)
      (!vrp.configuration.preprocessing.first_solution_strategy || !vrp.periodic_heuristic?) ||
        !vrp.configuration.preprocessing.cluster_threshold && !vrp.configuration.preprocessing.max_split_size
    end

    def assert_lat_lon_for_partition(vrp)
      vrp.configuration.preprocessing&.partitions.to_a.empty? ||
        vrp.points.all?{ |pt| pt&.location&.lat && pt&.location&.lon }
    end

    def assert_vehicle_entity_only_before_work_day(vrp)
      vehicle_entity_index =
        vrp.configuration.preprocessing.partitions.find_index{ |partition| partition.entity == :vehicle }
      work_day_entity_index =
        vrp.configuration.preprocessing.partitions.find_index{ |partition| partition.entity == :work_day }
      vehicle_entity_index.nil? || work_day_entity_index.nil? || vehicle_entity_index < work_day_entity_index
    end

    def assert_partitions_entity(vrp)
      vrp.configuration.preprocessing.partitions.empty? ||
        vrp.configuration.preprocessing.partitions.all?{ |partition|
          partition.technique != 'balanced_kmeans' || partition.entity
        }
    end

    def assert_no_partitions(vrp)
      vrp.configuration.preprocessing.partitions.empty?
    end

    def assert_valid_partitions(vrp)
      vrp.configuration.preprocessing.partitions.size < 3 &&
        (vrp.configuration.preprocessing.partitions.collect{ |partition|
           partition[:entity]
         }.uniq.size == vrp.configuration.preprocessing.partitions.size)
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
      vrp.vehicles.empty? ||
        (assert_only_time_dimension(vrp) ^ assert_only_distance_dimension(vrp) ^ assert_only_value_dimension(vrp))
    end

    # TODO: Need a better way to represent solver preference
    def assert_small_minimum_duration(vrp)
      vrp.configuration.resolution.minimum_duration.nil? || vrp.vehicles.empty? ||
        vrp.configuration.resolution.minimum_duration / vrp.vehicles.size < 5000
    end

    def assert_no_cost_fixed(vrp)
      vrp.vehicles.all?{ |vehicle| vehicle.cost_fixed.nil? || vehicle.cost_fixed.zero? } ||
        vrp.vehicles.map(&:cost_fixed).uniq.size == 1
    end

    def assert_no_complex_setup_durations(vrp)
      # TODO: This return should be changed once the activity model turned into activites
      return false if vrp.services.any?{ |s| s.activities.any? }

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

    def check_unreachable(vrp, dimension, unfeasible)
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
        next if (column_cpt[index] < vrp.matrices.size * (matrix_indices.size - 1)) &&
                (line_cpt[index] < vrp.matrices.size * (matrix_indices.size - 1))

        vrp.services.select{ |service|
          (service.activity ? [service.activity] : service.activities).any?{ |activity|
            activity.point.matrix_index == matrix_index
          }
        }.each{ |service|
          add_unassigned(unfeasible, vrp, service, 'Unreachable')
        }
      }

      unfeasible
    end

    def add_unassigned(unfeasible, vrp, service, reason)
      # calls add_unassigned_internal for every service in an "ALL_OR_NONE_RELATION" with the service
      service_already_marked_unfeasible = !!unfeasible[service.id]

      unless service_already_marked_unfeasible && reason.start_with?('In a ') &&
             reason =~ /\AIn a \S+ relation with an unfeasible service: /
        add_unassigned_internal(unfeasible, vrp, service, reason)
      end

      unless service_already_marked_unfeasible
        service.relations.each{ |relation|
          remove_start_index =
            case relation.type
            when *Models::Relation::ALL_OR_NONE_RELATIONS
              0
            when *Models::Relation::POSITION_TYPES
              relation.linked_service_ids.index(service.id)
            else
              next
            end
          remove_end_index = -1
          relation.linked_services[remove_start_index..remove_end_index].each{ |service_in|
            next if service_in == service

            add_unassigned(unfeasible, vrp, service_in,
                           "In a #{relation.type} relation with an unfeasible service: #{service.id}")
          }
        }
        vrp.routes.delete_if{ |route|
          route.mission_ids.delete_if{ |mission_id| mission_id == service.id }

          route.mission_ids.empty?
        }
      end

      unfeasible
    end

    def add_unassigned_internal(unfeasible, vrp, service, reason)
      if unfeasible[service.id]
        # we update reason to have more details
        unfeasible[service.id].each{ |un| un.reason += " && #{reason}" }
      else
        unfeasible[service.id] = []
        service.visits_number.times{ |index|
          stop_id = vrp.schedule? ? "#{service.id}_#{index + 1}_#{service.visits_number}" : service.id
          unfeasible[service.id] << Models::Solution::Stop.new(
            service,
            id: service.id,
            service_id: stop_id,
            reason: reason
          )
        }
      end

      unfeasible
    end

    def possible_days_are_consistent(vrp, service)
      return true unless vrp.schedule?

      return false if service.first_possible_days.any?{ |d| d > vrp.configuration.schedule.range_indices[:end] }

      return false if service.last_possible_days.any?{ |d| d < vrp.configuration.schedule.range_indices[:start] }

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
           this_visit_day > vrp.configuration.schedule.range_indices[:end]
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

      vrp.services.each{ |service|
        check_timewindow_inconsistency(vrp, unfeasible, service)

        if no_vehicle_with_compatible_skills(vrp, service) # inits service.vehicle_compatibility
          add_unassigned(unfeasible, vrp, service, 'Service has no compatible vehicle -- i.e., skills and/or sticky')
        end

        if no_compatible_vehicle_with_enough_capacity(vrp, service)
          add_unassigned(unfeasible, vrp, service,
                         'Service has a quantity which is greater than the capacity of any compatible vehicle')
        end

        if no_compatible_vehicle_with_compatible_tw(vrp, service)
          add_unassigned(unfeasible, vrp, service,
                         'Service cannot be performed by any compatible vehicle while '\
                         'respecting duration, timewindow and day limits')
        end

        # Planning inconsistency
        unless possible_days_are_consistent(vrp, service)
          add_unassigned(unfeasible, vrp, service, 'Provided possible days do not allow service to be assigned')
        end

        unless vrp.can_affect_all_visits?(service)
          add_unassigned(unfeasible, vrp, service, 'Inconsistency between visit number and minimum lapse')
        end
      }

      unfeasible
    end

    def sequence_relation_with_no_reachable_vehicle(unfeasible, vrp, relation)
      return false unless Models::Relation::POSITION_TYPES.include?(relation.type)

      vrp.vehicles.each{ |v|
        unreachable_service_id = last_service_reachable_sequence(vrp, v, relation.linked_services)
        next unless unreachable_service_id

        service_met = false
        relation.linked_services.each{ |service|
          service_met = true if service.id == unreachable_service_id
          next unless service_met

          service.vehicle_compatibility[v.id] = false
        }
      }

      previous_removed = false
      to_delete_services = []
      relation.linked_services.each{ |service|
        previous_removed ||=
          vrp.vehicles.none?{ |vehicle|
            service.vehicle_compatibility[vehicle.id]
          }

        if previous_removed
          if Models::Relation::ALL_OR_NONE_RELATIONS.include?(relation.type)
            to_delete_services = relation.linked_services
            break false
          else
            to_delete_services << service
          end
        end
      }

      to_delete_services.each{ |service|
        add_unassigned(unfeasible, vrp, service,
                       "Service belongs to a relation of type #{relation.type} which makes it infeasible")
      }
    end

    def last_service_reachable_sequence(vrp, vehicle, services)
      vehicle_timewindow = vehicle.timewindow || Models::Timewindow.new(start: 0)
      vehicle_duration = [
        vehicle.duration,
        vehicle_timewindow.safe_end(vehicle.cost_late_multiplier&.positive?) - vehicle_timewindow.start
      ].compact.min
      successive_activities =
        services.map{ |service|
          return service.id if service.vehicle_compatibility[vehicle.id] == false

          [service.id, service.activity && [service.activity] || service.activities]
        }
      return nil if successive_activities.all?{ |_id, acts| acts.any?{ |a| a.timewindows.none?(&:end) } }

      matrix = vrp.matrices.find{ |m| m.id == vehicle.matrix_id }

      depot_approach =
        (vehicle.start_point && matrix.time) ? successive_activities.first.last.map{ |act|
                                                 matrix.time[vehicle.start_point.matrix_index][act.point.matrix_index]
                                               }.min : 0
      earliest_arrival = vehicle_timewindow.start + depot_approach

      successive_activities.each.with_index{ |(id, a_activities), a_index|
        time = a_activities.map{ |act| act.timewindows.map{ |tw| tw.safe_end(act.late_multiplier&.positive?) }.max }.max
        time ||= vehicle_timewindow.safe_end(vehicle.cost_late_multiplier&.positive?)
        return id if earliest_arrival > time

        last_duration = a_activities.map{ |a| a.duration_on(vehicle) }.min
        depot_return =
          (vehicle.end_point && matrix.time) ? a_activities.map{ |act|
                                                 matrix.time[act.point.matrix_index][vehicle.end_point.matrix_index]
                                               }.min : 0
        earliest_depot_arrival = earliest_arrival + depot_return + last_duration

        return id if earliest_depot_arrival > vehicle_timewindow.safe_end(vehicle.cost_late_multiplier&.positive?) ||
                     earliest_depot_arrival - vehicle_timewindow.start > vehicle_duration

        break if a_index == successive_activities.size - 1

        _b_id, b_activities = successive_activities[a_index + 1]

        earliest_arrival = a_activities.map{ |a_act|
          b_activities.map{ |b_act|
            travel_time = matrix.time && matrix.time[a_act.point.matrix_index][b_act.point.matrix_index]
            travel_time += a_act.duration_on(vehicle) + travel_time > 0 ? a_act.setup_duration_on(vehicle) : 0
            [b_act.timewindows.map(&:start)&.min || 0, earliest_arrival + travel_time].max
          }.min
        }.min
      }
    end

    def check_timewindow_inconsistency(vrp, unfeasible, service)
      s_activities = [service.activity, service.activities].compact.flatten
      if s_activities.any?{ |a| a.timewindows.any?{ |tw| tw.start && tw.end && tw.start > tw.end } }
        add_unassigned(unfeasible, vrp, service, 'Service timewindow is infeasible')
      end

      # In a POSITION_TYPES relationship s1->s2, s2 cannot be served
      # if its timewindows end before any timewindow of s1 starts
      service.relations.each{ |relation|
        next unless Models::Relation::POSITION_TYPES.include?(relation[:type])

        max_earliest_arrival = 0
        relation.linked_services.map{ |service_in|
          if !service_in.activity && service_in.activities.any?{ |act| act.timewindows.any? }
            # TODO: Should consider alternatives
            log_string = 'Service activities within relations are not considered for timewindow inconsistency check'
            log log_string, relation.as_json.merge(level: :warn)
            next
          end
          next if service_in.activity.nil? || service_in.activity.timewindows.none?

          earliest_arrival = service_in.activity.timewindows.map{ |tw|
            tw.day_index.to_i * 86400 + tw.start
          }.min
          activity_lateness = service_in.activity.late_multiplier&.positive?
          latest_arrival = service_in.activity.timewindows.map{ |tw|
            tw.day_index.to_i * 86400 + tw.safe_end(activity_lateness)
          }.max

          max_earliest_arrival = [max_earliest_arrival, earliest_arrival].compact.max

          if latest_arrival < max_earliest_arrival
            add_unassigned(unfeasible, vrp, service_in, 'Inconsistent timewindows within relations of service')
          end
        }
      }
    end

    def no_vehicle_with_compatible_skills(vrp, service)
      service.vehicle_compatibility ||= {}

      vrp.vehicles.each{ |vehicle|
        service.vehicle_compatibility[vehicle.id] ||=
          service.vehicle_compatibility[vehicle.id].nil? && # if it is true or false, no need to recheck
          (service.skills.empty? || vehicle.skills.any?{ |v_skill_set| (service.skills - v_skill_set).empty? })
      }

      vrp.vehicles.none?{ |v| service.vehicle_compatibility[v.id] } # no compatible vehicles
    end

    def no_compatible_vehicle_with_enough_capacity(vrp, service)
      no_vehicle_with_compatible_skills(vrp, service) if service.vehicle_compatibility.nil?

      s_quantities = service.quantities.map{ |quantity|
        next if quantity.empty # empty operation value is an upper-bound

        [quantity.unit_id, quantity.value.abs]
      }.compact.to_h

      vrp.vehicles.each{ |vehicle|
        next unless service.vehicle_compatibility[vehicle.id] # already eliminated

        service.vehicle_compatibility[vehicle.id] =
          vehicle.capacities.none?{ |capacity|
            s_quantities[capacity.unit_id] && # there is quantity
              capacity.limit && # there is a limit
              !capacity.overload_multiplier&.positive? && # overload not permitted
              s_quantities[capacity.unit_id] > capacity.limit # and capacity is not enough
          }
      }

      vrp.vehicles.none?{ |v| service.vehicle_compatibility[v.id] } # no compatible vehicle with enough capacity
    end

    def no_compatible_vehicle_with_compatible_tw(vrp, service)
      no_vehicle_with_compatible_skills(vrp, service) if service.vehicle_compatibility.nil?

      s_activities = [service.activity, service.activities].compact.flatten

      implicit_timewindow = [Models::Timewindow.new(start: 0)] # need to check time feasibility

      vrp.vehicles.each{ |vehicle|
        next unless service.vehicle_compatibility[vehicle.id] # already eliminated

        vehicle_timewindows = [vehicle.timewindow, vehicle.sequence_timewindows].compact.flatten

        next if !vrp.schedule? && vehicle.duration.nil? && vehicle.distance.nil? &&
                s_activities.all?{ |a| a.timewindows.none?(&:end) } && vehicle_timewindows.none?(&:end)

        vehicle_timewindows = implicit_timewindow if vehicle_timewindows.empty?

        schedule_conf = vrp.configuration.schedule

        service.vehicle_compatibility[vehicle.id] =
          s_activities.any?{ |activity|
            time_to_go, time_to_return, dist_to_go, dist_to_return =
              two_way_time_and_dist(vrp, vehicle, activity) || [0, 0, 0, 0]

            # NOTE: There is no easy way to include the setup duration in the elimination because the
            # setup_duration logic is based of time[point_a][point_b] == 0; so we need to check all
            # services which are 0 distance and then find the minimum (setup_duration + duration) and
            # use this as the setup duration in the check below if it is less than the service.setup_duration

            (vehicle.distance.nil? || dist_to_go + dist_to_return <= vehicle.distance) &&
              (
                vehicle.duration.nil? ||
                time_to_go + activity.duration_on(vehicle) + time_to_return <= vehicle.duration
              ) && (
                (activity.timewindows.empty? ? implicit_timewindow : activity.timewindows).any?{ |s_tw|
                  vehicle_timewindows.any?{ |v_tw|
                    # vehicle has a tw that can serve service in time (incl. travel if it exists)
                    (s_tw.day_index.nil? || v_tw.day_index.nil? || s_tw.day_index == v_tw.day_index) &&
                      v_tw.start + time_to_go <= s_tw.safe_end(activity.late_multiplier&.positive?) &&
                      [s_tw.start, v_tw.start + time_to_go].max + activity.duration_on(vehicle) + time_to_return <=
                        v_tw.safe_end(vehicle.cost_late_multiplier&.positive?) &&
                      ( # either not schedule or there should be a day in which both vehicle and service are available
                        !vrp.schedule? ||
                          schedule_conf.range_indices[:start].upto(schedule_conf.range_indices[:end]).any?{ |day|
                            (s_tw.day_index.nil? || day % 7 == s_tw.day_index) &&
                              (v_tw.day_index.nil? || day % 7 == v_tw.day_index) &&
                              service.unavailable_days.exclude?(day) &&
                              vehicle.unavailable_days.exclude?(day)
                          }
                      )
                  }
                }
              )
          }
      }

      vrp.vehicles.none?{ |v| service.vehicle_compatibility[v.id] } # no compatible vehicle with compatible timewindow
    end

    def two_way_time_and_dist(vrp, vehicle, activity)
      return unless vehicle.matrix_id

      v_start_m_index = vehicle.start_point&.matrix_index
      v_end_m_index = vehicle.end_point&.matrix_index

      return unless v_start_m_index || v_end_m_index

      matrix = vrp.matrices.find{ |m| m.id == vehicle.matrix_id }

      [
        (v_start_m_index && matrix.time) ? matrix.time[v_start_m_index][activity.point.matrix_index] : 0,
        (v_end_m_index && matrix.time) ? matrix.time[activity.point.matrix_index][v_end_m_index] : 0,
        (v_start_m_index && matrix.distance) ? matrix.distance[v_start_m_index][activity.point.matrix_index] : 0,
        (v_end_m_index && matrix.distance) ? matrix.distance[activity.point.matrix_index][v_end_m_index] : 0,
      ]
    end

    def check_distances(vrp, unfeasible)
      unfeasible = check_unreachable(vrp, :time, unfeasible)
      unfeasible = check_unreachable(vrp, :distance, unfeasible)
      unfeasible = check_unreachable(vrp, :value, unfeasible)

      vrp.services.each{ |service|
        if no_compatible_vehicle_with_compatible_tw(vrp, service)
          add_unassigned(unfeasible, vrp, service,
                         'No compatible vehicle can reach this service while respecting all constraints')
        end
      }

      vrp.relations.each{ |relation|
        # If relation becomes empty it is removed by add_unassigned
        sequence_relation_with_no_reachable_vehicle(unfeasible, vrp, relation)
      }

      unless unfeasible.empty?
        infeasible_services =
          unfeasible.values.flatten.group_by{ |u| u[:reason] }.map{ |g, set|
            "#{set.size < 20 ? set.map{ |s| s[:service_id] }.join(', ') : "#{set.size} services"}\n with reason '#{g}'"
          }.join("\n")
        log "Following services marked as infeasible:\n#{infeasible_services}", level: :debug

        reasons = unfeasible.values.flatten.collect{ |u| u[:reason] }.uniq.join(', ')
        log "#{unfeasible.size} services marked as infeasible with the following reasons: #{reasons}", level: :info
      end
      unfeasible
    end

    def simplifications
      # Simplification functions should have the following structure and implement
      # :simplify, :rewind, and :patch_solution modes.
      #
      #       def simplify_X(vrp, solution = nil, options = { mode: :simplify })
      #         # Description of the simplification
      #         simplification_active = false
      #         case options[:mode]
      #         when :simplify
      #           # simplifies the constraint
      #           simplification_active = true if applied
      #         when :rewind
      #           nil # if nothing to do
      #           simplification_active = true if applied
      #         when :patch_solution
      #           # patches the solution
      #           simplification_active = true if applied
      #         else
      #           raise 'Unknown :mode option'
      #         end
      #         simplification_active # returns true if the simplification is applied/rewinded/patched
      #       end
      #
      # (If some modes are not necessary they can be merged -- e.g. `when :rewind, :patch_solution` and have `nil`)
      # :patch_solution is called for interim solutions and for the last solution before the :rewind is called.

      # TODO: We can simplify service timewindows if they are not necessary -- e.g., all service TWs are "larger" than
      # the vehicle TWs. (this modification needs to be rewinded incase we are in dicho or max_split)

      # TODO: infeasibility detection can be done with the simplification interface
      # (especially the part that is done after matrix)

      # Warning: The order might be important if the simplifications are interdependent.
      # The simplifications will be called in the following order and their corresponding rewind
      # and solution patching operations will be called in the opposite order. This can be changed
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
      vrp_subfields_to_check = %i[points relations rests routes services units vehicles].freeze

      simplifications.each{ |simplification|
        expected_vrp_subfield_counts = vrp_subfields_to_check.map{ |subfield| [subfield, vrp.send(subfield).size] }.to_h

        simplification_activated = self.send(simplification, vrp, nil, mode: :simplify)

        if simplification_activated
          log "#{simplification} simplification is activated"
        else
          actual_vrp_subfield_counts = vrp_subfields_to_check.map{ |subfield| [subfield, vrp.send(subfield).size] }.to_h

          next unless expected_vrp_subfield_counts != actual_vrp_subfield_counts

          tags = {
            simplification: simplification,
            expected_counts: expected_vrp_subfield_counts,
            actual_counts: actual_vrp_subfield_counts,
          }

          log_msg = 'Lost objects in a non-active simplification routine'

          log log_msg, tags.merge(level: :warn)
          raise log_msg if ENV['APP_ENV'] != 'production'
        end
      }

      vrp
    end

    def patch_simplified_constraints_in_solution(solution, vrp)
      return solution unless solution.is_a?(Models::Solution)

      simplifications.reverse_each{ |simplification|
        solution_patched = self.send(simplification, vrp, solution, mode: :patch_solution)
        log "#{simplification} simplification is active, solution is patched" if solution_patched
      }

      solution
    end

    def patch_and_rewind_simplified_constraints(vrp, solution)
      # first patch the solutions (before the constraint are rewinded)
      patch_simplified_constraints_in_solution(solution, vrp) if solution.is_a?(Models::Solution)

      # then rewind the simplifications
      simplifications.reverse_each{ |simplification|
        simplification_rewinded = self.send(simplification, vrp, nil, mode: :rewind)
        log "#{simplification} simplification is rewinded" if simplification_rewinded
      }

      vrp
    end

    def prioritize_first_available_trips_and_vehicles(vrp, solution = nil, options = { mode: :simplify })
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
      when :patch_solution
        # patches the solution
        return nil unless vrp.vehicles.any?{ |v| v[:fixed_cost_before_adjustment] }

        simplification_active = true

        solution.routes.each{ |route|
          # correct the costs if the vehicle had cost adjustment and it is used
          next unless route.vehicle[:fixed_cost_before_adjustment] && route.cost_info&.fixed&.positive?

          route.cost_info.fixed = route.vehicle[:fixed_cost_before_adjustment]
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active # returns true if the simplification is applied/rewinded/patched
    end

    def simplify_complex_multi_pickup_or_delivery_shipments(vrp, solution = nil, options = { mode: :simplify })
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
        if services_in_multi_shipment_relations.any?{ |s| vrp.routes.any?{ |r| r.mission_ids.include?(s.id) } }
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
          all_shipment_quantities =
            shipment_relations.collect{ |relation|
              # WARNING: Here we assume that there are two services in the relation -- a pair of pickup and delivery
              relation.linked_services.find{ |i| i != service }.quantities.each{ |quantity|
                total_quantity_per_unit_id[quantity.unit_id] += quantity.value
              }
            }
          extra_per_quantity =
            service.quantities.collect{ |quantity|
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

            relation_hash = relation.as_json
            relation_hash[:linked_service_ids] =
              relation.linked_services.map{ |s| s.id == service.id ? new_service.id : s.id }
            new_shipment_relation = Models::Relation.create(relation_hash)

            new_service.relations << new_shipment_relation

            expanded_relations << new_shipment_relation
            expanded_services << new_service
          }

          # For some reason, or-tools performance is better when the sequence relation is defined in the inverse order.
          # Note that, activity.duration's are set to zero except the last duplicated service
          # (so we model exactly same constraint).
          sequence_relations << Models::Relation.create(type: :sequence,
                                                        linked_service_ids: sequence_relation_ids.reverse)
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
      when :patch_solution
        return nil unless vrp[:simplified_complex_shipments]

        simplification_active = true

        simplification_data = vrp[:simplified_complex_shipments]

        simplification_data[:original_services].each{ |service|
          # delete the unassigned expanded version of service and calculate how many of them planned/unassigned
          unassigned_exp_ser_count = solution.unassigned_stops.size
          unassigned_exp_ser_count -= solution.unassigned_stops.delete_if{ |uns| uns.id == service.original_id }.size
          planned_exp_ser_count =
            simplification_data[:expanded_services].count{ |s| s.original_id == service.original_id } -
            unassigned_exp_ser_count

          if planned_exp_ser_count == 0
            # if all of them were unplanned
            # replace the deleted unassigned expanded ones with one single original un-expanded service
            solution.unassigned_stops << Models::Solution::Stop.new(service)
          else
            # replace the planned one(s) into one single unexpanded original service
            solution.routes.each{ |route|
              stop_info = nil
              first_exp_ser_stop = nil
              last_exp_ser_stop = nil
              insert_location = nil
              deleted_exp_ser_count = 0
              route.stops.delete_if.with_index{ |stop, index|
                if stop.id == service.original_id

                  insert_location ||= index
                  stop_info ||= stop.info
                  first_exp_ser_stop ||= stop # first_exp_ser_stop has the travel and timing info
                  last_exp_ser_stop = stop # last_exp_ser_stop has the quantity info
                  deleted_exp_ser_count += 1
                  true
                elsif deleted_exp_ser_count == planned_exp_ser_count
                  break
                end
              }

              next unless insert_location # expanded activity(ies) of service is found in this route

              # stop.. something went wrong if duplicated services are planned on different vehicles
              unless deleted_exp_ser_count == planned_exp_ser_count
                raise 'Simplification cannot patch the result if duplicated services are planned on different vehicles'
              end

              stop = Models::Solution::Stop.new(service, loads: [], info: stop_info)

              current_firsts = Hash.new { 0 }
              current_lasts = Hash.new { 0 }

              first_exp_ser_stop.loads.each{ |load|
                current_firsts[load.quantity.unit_id] = load.current
              }

              if last_exp_ser_stop != first_exp_ser_stop
                last_exp_ser_stop.loads.each{ |load|
                  current_lasts[load.quantity.unit_id] = load.current
                }
              end
              vrp.units.map{ |unit|
                Models::Solution::Load.new(
                  quantity: Models::Quantity.new(
                    unit: unit,
                    value: current_lasts[unit.id] - current_firsts[unit.id]
                  ),
                  current: current_firsts[unit.id]
                )
              }

              solution.insert_stop(vrp, route, stop, insert_location)

              break
            }
          end
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_vehicle_duration(vrp, _solution = nil, options = { mode: :simplify })
      # Simplify vehicle durations using timewindows if there is force_start
      simplification_active = false
      case options[:mode]
      when :simplify
        vrp.vehicles&.each{ |vehicle|
          next unless (vehicle.force_start || vehicle.shift_preference == 'force_start') &&
                      vehicle.duration &&
                      vehicle.timewindow

          simplification_active ||= true
          # Warning: this can make some services infeasible because vehicle cannot work after tw.start + duration
          vehicle.timewindow.end = vehicle.timewindow.start + vehicle.duration
          vehicle.duration = nil
        }
      when :rewind, :patch_solution
        nil # TODO: this simplification can be moved to a higher level since it doesn't need rewinding or patching
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_vehicle_pause(vrp, solution = nil, options = { mode: :simplify })
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
            next unless (service.sticky_vehicle_ids.empty? || service.sticky_vehicle_ids.include?(vehicle.id)) &&
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
              rest_end = rest_tw.end ||
                         vehicle.timewindow&.end ||
                         vehicle.duration &&
                         rest.duration &&
                         (rest_start + vehicle.duration - rest.duration) || 2147483647
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
        simplification_active ||= vrp[:simplified_rests].any?
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
      when :patch_solution
        # correct the solution with respect to simplifications
        pause_and_depot = %i[depot rest].freeze
        vrp.vehicles&.each{ |vehicle|
          next unless vehicle[:simplified_rests]&.any?

          simplification_active ||= true

          route = solution.routes.find{ |r| r.vehicle.id == vehicle.id }
          no_cost = route.stops.none?{ |a| pause_and_depot.exclude?(a.type) }

          # first shift every activity all the way to the left (earlier) if the route starts after
          # the vehicle TW.start so that it is easier to do the insertions since there is no TW on
          # services, we can do this even if force_start is false
          shift_amount = vehicle.timewindow&.start.to_i - (route.info.start_time || vehicle.timewindow&.start).to_i
          route.shift_route_times(shift_amount) if shift_amount < 0

          # insert the rests back into the route and adjust the info of the stops coming after the pause
          vehicle[:simplified_rests].each{ |rest|
            # find the first service that finishes after the TW.end of pause
            insert_rest_at =
              unless rest.timewindows&.last&.end.nil?
                route.stops.index{ |activity|
                  (activity.info.end_time || activity.info.begin_time) > rest.timewindows.last.end
                }
              end

            insert_rest_at, rest_start =
              if insert_rest_at.nil?
                # reached the end of the route or there is no TW.end on the pause
                # in any case, insert the rest at the end (before the end depot if it exists)
                if route.stops.empty?
                  # no activity
                  [route.stops.size, vehicle.timewindow&.start || 0]
                elsif route.stops.last.type == :depot && vehicle.end_point
                  # last activity is an end depot
                  [route.stops.size - 1, route.stops.last.info.begin_time]
                else
                  # last activity is not an end depot
                  # either the last activity is a service and it has an end_time
                  # or it is the begin depot and we can use the begin_time
                  [route.stops.size, route.stops.last.info.end_time || route.stops.last.info.begin_time]
                end
              else
                # there is a clear position to insert
                stop_after_rest = route.stops[insert_rest_at]
                stop_before_rest = route.stops[insert_rest_at - 1]

                rest_start = stop_after_rest.info.begin_time
                # if this the first service of this location then we need to consider the setup_duration
                if stop_before_rest.activity.point_id != stop_after_rest.activity.point_id
                  rest_start -= stop_after_rest.activity.setup_duration.to_i
                end
                if rest.timewindows&.last&.end && rest_start > rest.timewindows.last.end
                  rest_start -= stop_after_rest.info.travel_time
                  # don't induce idle_time if within travel_time
                  rest_start = [rest_start, rest.timewindows&.first&.start.to_i].max
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
              route.shift_route_times(idle_time_created_by_inserted_pause)
              idle_time_created_by_inserted_pause = 0
            end
            times = { begin_time: rest_start, end_time: rest_start + rest.duration,
                      departure_time: rest_start + rest.duration }
            rest_stop = Models::Solution::Stop.new(rest, info: Models::Solution::Stop::Info.new(times))
            solution.insert_stop(vrp, route, rest_stop, insert_rest_at, idle_time_created_by_inserted_pause)

            next if no_cost

            cost_increase = vehicle.cost_time_multiplier.to_f * rest.duration +
                            vehicle.cost_waiting_time_multiplier.to_f * idle_time_created_by_inserted_pause
            route.cost_info&.time += cost_increase
          }
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end

    def simplify_service_setup_duration_and_vehicle_setup_modifiers(vrp, solution = nil, options = { mode: :simplify })
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
        grouped_services = vrp.services.group_by{ |s| s.activity.point }
        return nil if grouped_services.map{ |point, _s_g| point.matrix_index }.uniq.size != grouped_services.size

        grouped_services.each{ |point, service_group|
          next if service_group.any?{ |s| s.activity.setup_duration.to_i == 0 } || # no need if no setup_duration
                  service_group.uniq{ |s| s.activity.setup_duration }.size > 1 # can't if setup_durations are different

          first_activity = service_group.first.activity

          vrp.matrices.each{ |matrix|
            vehicle = vehicles_grouped_by_matrix_id[matrix.id].first

            # WARNING: In the following logic we assume that matrix indices are unique.
            # This follows the logic setup within optimizer-ortools until we introduce the point_id in protobuf model
            matrix.time.each.with_index{ |row, row_index|
              if point.matrix_index != row_index
                row[point.matrix_index] += first_activity.setup_duration_on(vehicle).to_i
              end
            }
          }

          service_group.each{ |service|
            service.activity[:simplified_setup_duration] = service.activity.setup_duration
            service.activity.setup_duration = 0
          }
        }

        return nil unless vrp.services.any?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vrp.vehicles.each{ |vehicle|
          vehicle[:simplified_coef_setup] = vehicle.coef_setup
          vehicle[:simplified_additional_setup] = vehicle.additional_setup
          vehicle.coef_setup = 1
          vehicle.additional_setup = 0
        }
      when :rewind
        # take it back in case in dicho and there will be re-optimization
        return nil if vrp.services.any?{ |s| s.activities.any? } ||
                      vrp.services.none?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vehicles_grouped_by_matrix_id = vrp.vehicles.group_by(&:matrix_id)

        vrp.services.group_by{ |s| s.activity.point }.each{ |point, service_group|
          setup_duration = service_group.first.activity[:simplified_setup_duration].to_i

          next if setup_duration.zero?

          vrp.matrices.each{ |matrix|
            vehicle = vehicles_grouped_by_matrix_id[matrix.id].first
            coef_setup = vehicle[:simplified_coef_setup] || 1
            additional_setup = vehicle[:simplified_additional_setup].to_i

            # WARNING: In this revert logic we still assume that matrix indices are unique.
            # This follows the logic setup within optimizer-ortools until we indroduce the point_id in protobuf model
            matrix.time.each_with_index{ |row, row_index|
              if point.matrix_index != row_index
                row[point.matrix_index] -= (coef_setup * setup_duration + additional_setup).to_i
              end
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
      when :patch_solution
        # patches the solution
        # the travel_times need to be decreased and setup_duration need to be increased by
        # (coef_setup * setup_duration + additional_setup) if setup_duration > 0 and matrix_indices are different
        return nil if vrp.services.any?{ |s| s.activities.any? } ||
                      vrp.services.none?{ |s| s.activity[:simplified_setup_duration] }

        simplification_active = true

        vehicles_grouped_by_vehicle_id = vrp.vehicles.group_by(&:id)
        services_grouped_by_point_id = vrp.services.group_by{ |s| s.activity.point_id }

        overall_total_travel_time_correction = 0
        solution.routes.each{ |route|
          vehicle = vehicles_grouped_by_vehicle_id[route[:vehicle_id]].first
          vehicle.coef_setup = vehicle[:simplified_coef_setup]
          vehicle.additional_setup = vehicle[:simplified_additional_setup]
          total_travel_time_correction = 0
          previous_point_id = nil
          route.stops.each{ |stop|
            next if previous_point_id == stop.activity.point_id

            previous_point_id = stop.activity.point_id

            next if stop.service_id.nil? || services_grouped_by_point_id[stop.activity.point.id].nil?

            setup_duration = stop.activity[:simplified_setup_duration].to_i

            next if setup_duration.zero?

            # The vehicle adjustement is performed by vrp_result
            stop.activity.setup_duration = setup_duration
            travel_time_correction = stop.activity.setup_duration_on(vehicle).to_i

            total_travel_time_correction += travel_time_correction
            stop.info.travel_time -= travel_time_correction
            previous_point_id = stop.activity.point_id
          }

          overall_total_travel_time_correction += total_travel_time_correction
          route.info.total_travel_time -= total_travel_time_correction.round

          # Solution patcher must let the problem untouched
          vehicle.coef_setup = 1
          vehicle.additional_setup = 0
        }
        solution.info.total_travel_time -= overall_total_travel_time_correction.round

        solution.unassigned_stops.each{ |stop|
          setup_duration = stop.activity[:simplified_setup_duration].to_i

          stop.activity.setup_duration = setup_duration
        }
      else
        raise 'Unknown :mode option'
      end
      simplification_active
    end
  end
end
