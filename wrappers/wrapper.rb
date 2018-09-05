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
      []
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
      vrp.vehicles.size == 1 && !vrp.schedule_range_indices && !vrp.schedule_range_date
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

    def assert_services_no_skills(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.skills.empty?
      }
    end

    def assert_services_no_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.activity.timewindows.empty?
      }
    end

    def assert_services_no_multiple_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity.timewindows.size > 1
      }
    end

    def assert_services_at_most_two_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity.timewindows.size > 2
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
        service.activity.late_multiplier && service.activity.late_multiplier > 0
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

    def assert_correctness_provided_matrix_indices(vrp)
      dimensions = vrp.vehicles.collect(&:dimensions).flatten.uniq
      max_matrix_index = vrp.points.collect(&:matrix_index).max || 0
      vrp.matrices.all?{ |matrix|
        dimensions.all?{ |dimension|
          matrix[dimension].nil? || matrix[dimension].size > max_matrix_index && matrix[dimension].all?{ |line| line.size > max_matrix_index }
        }
      }
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

    def assert_range_date_if_month_duration(vrp)
      !(vrp[:relations] && vrp[:relations].any?{ |relation| relation[:type] == 'vehicle_group_duration_on_months' }) || vrp.schedule_range_date
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
        s_ok = !t_day.nil? ? t_day == day : (service[:unavailable_visit_day_indices] || service[:unavailable_visit_date]) && service[:unavailable_visit_day_indices].include?(day)
        v_ok = vehicle[:unavailable_work_day_indices] && vehicle[:unavailable_work_day_indices].include?(day) || vehicle[:unavailable_work_date] && vehicle[:unavailable_work_date].include?(day)
        s_ok && v_ok
      }
    end

    def find_vehicle(vrp, service, t_start, t_end, t_day)
      vrp[:vehicles].select{ |vehicle| vehicle[:timewindow] }.any?{ |vehicle|
        v_start = vehicle[:timewindow][:start]
        v_end = vehicle[:timewindow][:end]
        v_day = vehicle[:timewindow][:day_index]
        days_compatible = v_day.nil? || t_day.nil? || v_day == t_day
        if service[:unavailable_visit_day_indices] && service[:unavailable_visit_day_indices].include?(v_day)
          days_compatible = false
        end
        if v_day && v_day >= 0 && service[:unavailable_visit_day_date] && service[:unavailable_visit_day_date].include?(vrp[:schedule][:range_date][:start] + v_day)
          days_compatible = false
        end
        days_compatible = compatible_day?(vrp, service, t_day, vehicle) if v_day.nil? && vrp[:schedule] && days_compatible
        days_compatible && (t_start.nil? && (t_end.nil? || v_start.nil? || v_start <= t_end) ||
                            t_end.nil? && (v_end.nil? || t_start <= v_end) ||
                            t_start && t_end && (v_start.nil? || v_start <= t_end) && (v_end.nil? || t_start <= v_end))
      } || vrp[:vehicles].none?{ |vehicle| vehicle[:timewindow] || vehicle[:sequence_timewindows] } ||
        vrp[:vehicles].select{ |vehicle| vehicle[:sequence_timewindows] }.any?{ |vehicle|
          vehicle[:sequence_timewindows].any?{ |tw|
            v_start = tw[:start]
            v_end = tw[:end]
            v_day = tw[:day_index]
            days_compatible = v_day.nil? || t_day.nil? || v_day == t_day
            days_compatible && (t_start.nil? && (t_end.nil? || v_start.nil? || v_start <= t_end) ||
                                t_end.nil? && (v_end.nil? || v_end >= t_start) ||
                                t_start && t_end && v_start <= t_end && v_end >= t_start)
          }
        } || vrp[:vehicles].any?{ |vehicle| vehicle[:cost_late_multiplier] && vehicle[:cost_late_multiplier] > 0 }
    end

    def check(vrp, matrix, unfeasible)
      if !matrix.nil?
        line_cpt = Array.new(matrix.size){ 0 }
        column_cpt = Array.new(matrix.size){ 0 }
        matrix.each_with_index{ |vector, line|
          vector.each_with_index{ |value, col|
            if value.nil? || value >= 2**31 - 1
              line_cpt[line] += 1
              column_cpt[col] += 1
            end
          }
        }

        (0..matrix.size - 1).each{ |index|
          next if (column_cpt[index] == 0 || column_cpt[index] != matrix.size - 1) && (line_cpt[index] == 0 || line_cpt[index] != matrix.size - 1)
          vrp[:services].select{ |service| service[:activity][:point][:matrix_index] == index }.each{ |service|
            if unfeasible.none?{ |unfeas| unfeas[:service_id] == service[:id] }
              unfeasible += add_unassigned(vrp, service, 'Unreachable')
            end
          }
        }
      end

      unfeasible
    end

    def add_unassigned(vrp, service, reason)
      [{
        service_id: service[:id],
        point_id: service[:activity] ? service[:activity][:point_id] : nil,
        detail: {
          lat: service[:activity] && service[:activity][:point][:location] ? service[:activity][:point][:location][:lat] : nil,
          lon: service[:activity] && service[:activity][:point][:location] ? service[:activity][:point][:location][:lon] : nil,
          setup_duration: service[:activity] ? service[:activity][:setup_duration] : nil,
          duration: service[:activity] ? service[:activity][:duration] : nil,
          timewindows: service[:activity][:timewindows] ? service[:activity][:timewindows].collect{ |tw| {start: tw[:start], end: tw[:end] }} : [],
          quantities: service[:quantities] ? service[:quantities].collect{ |qte| { unit: qte[:unit], value: qte[:value] } } : nil
        },
        reason: reason
      }]
    end

    def detect_unfeasible_services(vrp)
      unfeasible = []

      if !vrp[:vehicles] || !vrp[:services]
        return unfeasible
      end

      # check enough capacity
      if vrp[:units] && !vrp[:units].empty?
        # compute vehicle capacities
        capacity = {}
        unlimited = {}
        vrp[:units].each{ |u|
          capacity[u[:id]] = nil
          unlimited[u[:id]] = vrp[:vehicles].any?{ |vehicle| vehicle[:capacities].nil? || vehicle[:capacities].empty? } ||
                              vrp[:vehicles].any?{ |vehicle| vehicle[:capacities] && vehicle[:capacities].none?{ |capa| capa.unit_id == u.id }}
        }

        vrp[:vehicles].select{ |vehicle| vehicle[:capacities] && !vehicle[:capacities].empty? }.each{ |vehicle|
          vehicle[:capacities].each{ |capa|
            if !unlimited[capa[:unit_id]]
              capacity[capa.unit_id] = (capacity[capa.unit_id] || 0) + capa[:limit].to_i
            end
          }
        }

        # check needed capacity
        vrp.services.each{ |service|
          service.quantities.select{ |quantity| quantity.value && !unlimited[quantity.unit_id] && capacity[quantity.unit_id] < quantity.value }.each{
            if unfeasible.none?{ |unfeas| unfeas[:service_id] == service[:id] }
              unfeasible += add_unassigned(vrp, service, 'Unsufficient capacity in vehicles')
            end
          }
        }
      end

      # no need to check service and vehicle skills compatibility
      # if no vehicle has the skills for a given service we consider service's skills are unconsistent for current problem

      # check time-windows compatibility
      vrp[:services].each{ |service|
        found = false
        if service[:activity][:timewindows] && !service[:activity][:timewindows].empty?
          service[:activity][:timewindows].each{ |timewindow|
            next if found
            t_start = timewindow[:start]
            t_end = timewindow[:end]
            t_day = timewindow[:day_index]
            found = find_vehicle(vrp, service, t_start, t_end, t_day)
          }
        else
          found = find_vehicle(vrp, service, nil, nil, nil)
        end

        if !found && unfeasible.none?{ |unfeas| unfeas[:service_id] == service[:id] }
          unfeasible += add_unassigned(vrp, service, 'No vehicle with compatible timewindow')
        end
      }

      # check if one service has minimum lapse
      if vrp.schedule_range_indices || vrp.schedule_range_date
        nb_days = if vrp.schedule_range_indices
          vrp.schedule_range_indices[:end] - vrp.schedule_range_indices[:start] + 1
        else
          (vrp.schedule_range_date[:end].to_date - vrp.schedule_range_date[:start].to_date).to_i + 1
        end
        vrp[:services].select{ |service| service[:minimum_lapse] && service[:visits_number] > 1 }.each{ |service|
          found = service[:minimum_lapse] < nb_days
          if !found && unfeasible.none?{ |unfeas| unfeas[:service_id] == service[:id] }
            unfeasible += add_unassigned(vrp, service, 'Minimum_lapse is too big')
          end
        }
      end
      unfeasible
    end

    def check_distances(vrp, unfeasible)
      vrp[:matrices].each{ |matrix|
        unfeasible = check(vrp, matrix[:time], unfeasible)
        unfeasible = check(vrp, matrix[:distance], unfeasible)
        unfeasible = check(vrp, matrix[:value], unfeasible)
      }

      unfeasible
    end

    def kill
    end
  end
end
