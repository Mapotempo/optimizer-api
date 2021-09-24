# Copyright © Mapotempo, 2020
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
require 'active_support/concern'

module PeriodicDataInitialization
  extend ActiveSupport::Concern

  def generate_route_structure(vrp)
    vrp.vehicles.each{ |vehicle|
      capacity = compute_capacities(vrp, vehicle.capacities, true)
      @candidate_routes[vehicle.original_id] ||= {}
      @candidate_routes[vehicle.original_id][vehicle.global_day_index] = {
        # vehicle: vehicle # it is costly to use this
        vehicle_original_id: vehicle.original_id,
        day: vehicle.global_day_index,
        tw_start: vehicle.timewindow.start % 86400,
        tw_end: vehicle.timewindow.end % 86400,
        start_point_id: vehicle.start_point&.id,
        end_point_id: vehicle.end_point&.id,
        duration: vehicle.duration || (vehicle.timewindow.end - vehicle.timewindow.start),
        matrix_id: vehicle.matrix_id,
        stops: [],
        capacity: capacity,
        capacity_left: Marshal.load(Marshal.dump(capacity)),
        skills: vehicle.skills,
        maximum_ride_time: vehicle.maximum_ride_time,
        maximum_ride_distance: vehicle.maximum_ride_distance,
        router_dimension: vehicle.router_dimension.to_sym,
        cost_fixed: vehicle.cost_fixed,
        available_ids: [],
        completed: false,
      }
    }
  end

  def initialize_routes(routes)
    @output_tool&.add_comment('INITIALIZE_ROUTES')
    considered_ids = []
    routes.sort_by(&:day_index).each{ |defined_route|
      associated_route = @candidate_routes[defined_route.vehicle_id][defined_route.day_index.to_i]
      defined_route.mission_ids.each{ |id|
        next if !@services_data.key?(id) # id has been removed when detecting unfeasible services in wrapper

        best_index = find_best_index(id, associated_route, false) if associated_route
        considered_ids << id
        if best_index
          insert_visit_in_route(associated_route, best_index, false)

          # unlock corresponding services
          services_to_add = @services_unlocked_by[id].to_a & @candidate_services_ids
          @to_plan_service_ids += services_to_add
          services_to_add.each{ |service_id| @unlocked[service_id] = nil }
        else
          @services_assignment[id][:unassigned_reasons] |= ['Can not add this service to its corresponding route']
        end

        @candidate_services_ids.delete(id)
        @to_plan_service_ids.delete(id)
        @used_to_adjust << id
      }
    }

    routes.sort_by(&:day_index).each{ |defined_route|
      # TODO : try to affect missing visits with add_missing visits functions (because plan_next_visits only plans after last planned day, not in between)
      # Should plan_next_visits use this logic always ?
      plan_visits_missing_in_routes(defined_route.vehicle_id, defined_route.day_index.to_i)
    }

    considered_ids.each{ |id|
      @services_assignment[id][:missing_visits] = @services_data[id][:raw].visits_number - @services_assignment[id][:days].size
      next unless @services_assignment[id][:missing_visits].positive?

      @services_assignment[id][:unassigned_reasons] |=
        ['Routes provided do not allow to assign this visit because previous visit could not be planned in specified route']
    }
  end

  def plan_visits_missing_in_routes(vehicle_id, day)
    max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
    return unless @candidate_routes[vehicle_id][day]

    @candidate_routes[vehicle_id][day][:stops].sort_by{ |stop|
      id = stop[:id]
      @services_data[id][:priority].to_f + 1 / (max_priority * @services_data[id][:raw].visits_number**2)
    }.each{ |stop|
      id = stop[:id]

      next if @services_assignment[id][:days].size == @services_data[id][:raw].visits_number ||
              # if we rejected services this implies we could not affect one service to its corresponding route
              # therefore, trying to insert more visits might cause inconsistency
              @services_assignment[id][:unassigned_reasons].any?

      plan_next_visits(vehicle_id, id, @services_assignment[id][:days].size + 1)
      @output_tool&.insert_visits(@services_assignment[id][:days], id, @services_data[id][:visits_number])
    }
  end

  def compute_period(service, one_working_day_per_vehicle)
    if service.visits_number == 1
      nil
    elsif one_working_day_per_vehicle
      ideal_lapse = service.minimum_lapse ? (service.minimum_lapse.to_f / 7).ceil * 7 : 7
      if service.maximum_lapse.nil? || service.maximum_lapse >= ideal_lapse
        ideal_lapse
      else
        reject_all_visits(service.id, service.visits_number,
                          'Vehicles have only one working day, no lapse will allow to affect more than one visit.')
        nil
      end
    else
      service.minimum_lapse || 1
    end
  end

  def collect_services_data(vrp)
    available_units = vrp.vehicles.flat_map{ |v| v.capacities.collect{ |capacity| capacity.unit.id } }.uniq
    one_working_day_per_vehicle = @candidate_routes.all?{ |_vehicle_id, all_routes| all_routes.keys.uniq{ |day| day % 7 }.size == 1 }
    vrp.services.each{ |service|
      @services_assignment[service.id] = { vehicles: [], days: [], missing_visits: service.visits_number, unassigned_reasons: [] }
      @services_data[service.id] = {
        raw: service,
        capacity: compute_capacities(vrp, service.quantities, false, available_units),
        setup_durations: service.activity ? [service.activity.setup_duration] : service.activities.collect(&:setup_duration),
        durations: service.activity ? [service.activity.duration] : service.activities.collect(&:duration),
        heuristic_period: compute_period(service, one_working_day_per_vehicle),
        points_ids: service.activity ? [service.activity.point.id || service.activity.point.matrix_id] : service.activities.collect{ |a| a.point.id || a.point.matrix_id },
        tws_sets: service.activity ? [service.activity.timewindows] : service.activities.collect(&:timewindows),
        priority: service.priority,
        sticky_vehicles_ids: service.sticky_vehicles.collect(&:id),
        positions_in_route: service.activity ? [service.activity.position] : service.activities.collect(&:position),
        nb_activities: service.activity ? 1 : service.activities.size,
      }

      if possible_days_are_consistent(vrp, service)
        @candidate_services_ids << service.id
        @to_plan_service_ids << service.id
      else
        reject_all_visits(service.id, service.visits_number, 'First and last possible days do not allow this service planification')
      end
    }

    adapt_services_data(vrp) if @same_point_day
  end

  def adapt_services_data(vrp)
    # REMINDER : services in (relaxed_)same_point_day relation can only have one point_id

    @to_plan_service_ids = []
    vrp.points.each{ |point|
      same_located_set = @services_data.select{ |_id, data| data[:points_ids].include?(point.id) }.sort_by{ |_id, data| data[:raw].visits_number }

      next if same_located_set.empty?

      group_tw = best_common_tw(same_located_set)
      if group_tw.empty? && !same_located_set.all?{ |_id, data| data[:tws_sets].first.empty? }
        reject_group(same_located_set,
                     'Same_point_day conflict : services at this geographical point have no compatible timewindow')
      else
        representative_ids = []
        # one representative per freq
        same_located_set.group_by{ |_id, data| data[:raw].visits_number }.sort_by{ |visits_number, _sub_set|
          visits_number
        }.each{ |_visits_number, sub_set|
          representative_id = sub_set[0][0]
          representative_ids << representative_id
          sub_set[0][1][:tws_sets] = [group_tw]
          sub_set[0][1][:group_duration] = sub_set.sum{ |_id, data| data[:durations].first }
          @same_located[representative_id] = sub_set.collect(&:first) - [representative_id]
          sub_set[0][1][:group_capacity] = Marshal.load(Marshal.dump(sub_set[0][1][:capacity]))
          @same_located[representative_id].each{ |id|
            @services_data[id][:capacity].each{ |unit, value| sub_set[0][1][:group_capacity][unit] += value }
            @services_data[id][:tws_sets] = [group_tw]
          }
        }

        @to_plan_service_ids << representative_ids.last
        @services_unlocked_by[representative_ids.last] = representative_ids.slice(0, representative_ids.size - 1).to_a
      end
    }
  end

  def collect_indices(vrp)
    vrp.vehicles.each{ |vehicle|
      @indices[vehicle.start_point.id] = vehicle.start_point.matrix_index if vehicle.start_point
      @indices[vehicle.end_point.id] = vehicle.end_point.matrix_index if vehicle.end_point
    }

    vrp.services.each{ |service|
      (service.activity ? [service.activity] : service.activities).each{ |activity|
        @indices[activity.point.id] = activity.point.matrix_index
      }
    }

    @indices.each_key{ |point_id|
      @points_assignment[point_id] = { vehicles: [], days: [], services_ids: [] }
    }
  end

  def reject_group(group, specified_reason)
    group.each{ |id, data| reject_all_visits(id, data[:raw].visits_number, specified_reason) }
  end

  def compute_latest_authorized
    @services_data.group_by{ |_id, data| [data[:raw].visits_number, data[:heuristic_period]] }.each{ |_parameters, set|
      latest_day = set.max_by{ |_service, data| data[:raw].last_possible_days.first }.last[:raw].last_possible_days.first # first is for first visit

      @candidate_routes.each{ |vehicle_id, all_routes|
        all_routes.each_key{ |day|
          next if day > latest_day

          @candidate_routes[vehicle_id][day][:available_ids] += set.collect(&:first)
        }
      }
    }
  end

  def best_common_tw(set)
    ### finds the biggest tw common to all services in [set] ###
    first_with_tw = set.find{ |_id, data| !data[:tws_sets].first.empty? }
    if first_with_tw
      group_tw = @services_data[first_with_tw[0]][:tws_sets].first.collect{ |tw| { day_index: tw[:day_index], start: tw[:start], end: tw[:end] } }
      # all timewindows are assigned to a day
      group_tw.select{ |timewindow| timewindow[:day_index].nil? }.each{ |tw|
        (0..6).each{ |day|
          group_tw << { day_index: day, start: tw[:start], end: tw[:end] }
        }
      }
      group_tw.delete_if{ |tw| tw[:day_index].nil? }

      # finding minimal common timewindow
      set.each{ |_id, data|
        next if data[:tws_sets].first.empty?

        # remove all tws with no intersection with this service tws
        group_tw.delete_if{ |tw1|
          data[:tws_sets].first.none?{ |tw2|
            (tw1[:day_index].nil? || tw2[:day_index].nil? || tw1[:day_index] == tw2[:day_index]) &&
              (tw2[:end].nil? || tw1[:start] <= tw2[:end]) &&
              (tw1[:end].nil? || tw1[:end] >= tw2[:start])
          }
        }

        next if group_tw.empty?

        # adjust all tws with intersections with this point tws
        data[:tws_sets].first.each{ |tw1|
          intersecting_tws = group_tw.select{ |tw2|
            (tw1[:day_index].nil? || tw2[:day_index].nil? || tw1[:day_index] == tw2[:day_index]) &&
              (tw2[:start] <= tw1[:start] || tw1[:end].nil? || tw2[:start].between?(tw1[:start], tw1[:end])) &&
              (tw2[:end].nil? || tw1[:end].nil? || tw2[:end].between?(tw1[:start], tw1[:end]) || tw2[:end] >= tw1[:end])
          }
          next if intersecting_tws.empty?

          intersecting_tws.each{ |tw2|
            tw2[:start] = [tw2[:start], tw1[:start]].max
            tw2[:end] = [tw2[:end], tw1[:end]].min
          }
        }
      }

      group_tw.delete_if{ |tw| tw[:start] == tw[:end] }
      group_tw
    else
      []
    end
  end

  def compute_capacities(vrp, quantities, is_vehicle, available_units = [])
    return {} if quantities.nil?

    capacities = {}
    quantities.each{ |data|
      if is_vehicle
        if capacities[data.unit.id]
          capacities[data.unit.id] += data.limit.to_f
        else
          capacities[data.unit.id] = data.limit.to_f
        end
      elsif available_units.include?(data.unit.id)
        # if vehicled do not have this unit then this unit should be ignored
        # with clustering, issue is open about assigning vehicles with right capacities to services
        if capacities[data.unit.id]
          capacities[data.unit.id] += data.value.to_f
        else
          capacities[data.unit.id] = data.value.to_f
        end
      end
    }

    vrp.units.reject{ |unit| capacities.key?(unit.id) }.each{ |missing_unit|
      capacities[missing_unit.id] = 0.0
    }

    capacities
  end
end
