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

# Second end of the algorithm after scheduling heuristic
module SchedulingDataInitialization
  extend ActiveSupport::Concern

  def generate_route_structure(vrp)
    vrp.vehicles.each{ |vehicle|
      original_vehicle_id = vehicle[:id].split('_').slice(0, vehicle[:id].split('_').size - 1).join('_')
      capacity = compute_capacities(vehicle[:capacities], true)
      vrp.units.reject{ |unit| capacity.has_key?(unit[:id]) }.each{ |unit| capacity[unit[:id]] = 0.0 }
      @candidate_routes[original_vehicle_id][vehicle.global_day_index] = {
        vehicle_id: vehicle.id,
        global_day_index: vehicle.global_day_index,
        tw_start: (vehicle.timewindow.start < 84600) ? vehicle.timewindow.start : vehicle.timewindow.start - vehicle.global_day_index * 86400,
        tw_end: (vehicle.timewindow.end < 84600) ? vehicle.timewindow.end : vehicle.timewindow.end - vehicle.global_day_index * 86400,
        start_point_id: vehicle.start_point&.id,
        end_point_id: vehicle.end_point&.id,
        duration: vehicle.duration || (vehicle.timewindow.end - vehicle.timewindow.start),
        matrix_id: vehicle.matrix_id,
        current_route: [],
        capacity: capacity,
        capacity_left: Marshal.load(Marshal.dump(capacity)),
        maximum_ride_time: vehicle.maximum_ride_time,
        maximum_ride_distance: vehicle.maximum_ride_distance,
        router_dimension: vehicle.router_dimension.to_sym,
        cost_fixed: vehicle.cost_fixed,
      }
      @vehicle_day_completed[original_vehicle_id][vehicle.global_day_index] = false
      @missing_visits[original_vehicle_id] = []
    }

    initialize_routes(vrp.routes) unless vrp.routes.empty?
  end

  def initialize_routes(routes)
    considered_ids = []
    routes.sort_by(&:day_index).each{ |defined_route|
      associated_route = @candidate_routes[defined_route.vehicle_id][defined_route.day_index.to_i]
      defined_route.mission_ids.each{ |id|
        next if !@services_data.has_key?(id) # id has been removed when detecting unfeasible services in wrapper

        best_index = find_best_index(id, associated_route) if associated_route
        if best_index
          insert_point_in_route(associated_route, best_index, false)

          # unlock corresponding services
          services_to_add = @services_unlocked_by[id].to_a - @uninserted.collect{ |_un, data| data[:original_service] }
          @to_plan_service_ids += services_to_add
          @unlocked += services_to_add
        else
          @uninserted["#{id}_#{considered_ids.count(id) + 1}_#{@services_data[id][:visits_number]}"] = {
            original_service: id,
            reason: "Can not add this service to route (vehicle #{defined_route.vehicle_id}, day #{defined_route.day_index}) : already #{associated_route ? associated_route[:current_route].size : 0} elements in route"
          }
        end

        @candidate_services_ids.delete(id)
        @to_plan_service_ids.delete(id)
        @used_to_adjust << id
      }
    }

    routes.sort_by(&:day_index).each{ |defined_route|
      plan_routes_missing_in_routes(defined_route.vehicle_id, defined_route.day_index.to_i)
    }

    # TODO : try to affect missing visits with add_missing visits functions

    @uninserted.group_by{ |_k, v| v[:original_service] }.each{ |id, set|
      (set.size + 1..@services_data[id][:visits_number]).each{ |visit|
        @uninserted["#{id}_#{visit}_#{@services_data[id][:visits_number]}"] = {
          original_service: id,
          reason: 'Routes provided do not allow to assign this visit because previous visit could not be planned in specified route'
        }
      }
    }
  end

  def plan_routes_missing_in_routes(vehicle, day)
    max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
    return unless @candidate_routes[vehicle][day]

    @candidate_routes[vehicle][day][:current_route].sort_by{ |stop|
      id = stop[:id]
      @services_data[id][:priority].to_f + 1 / (max_priority * @services_data[id][:visits_number]**2)
    }.each{ |stop|
      id = stop[:id]

      next if @services_data[id][:used_days].size == @services_data[id][:visits_number]

      plan_next_visits(vehicle, id, @services_data[id][:used_days], @services_data[id][:used_days].size + 1)
    }
  end

  def collect_services_data(vrp)
    available_units = vrp.vehicles.collect{ |vehicle| vehicle[:capacities] ? vehicle[:capacities].collect{ |capacity| capacity[:unit_id] } : nil }.flatten.compact.uniq
    vrp.services.each{ |service|
      has_only_one_day = vrp.vehicles.collect{ |v| v.global_day_index % 7 }.uniq.size == 1
      period = if service.visits_number == 1
                  nil
                elsif has_only_one_day
                  service[:minimum_lapse] ? (service[:minimum_lapse].to_f / 7).ceil * 7 : 7
                else
                  service[:minimum_lapse] || 1
                end
      @services_data[service.id] = {
        capacity: compute_capacities(service.quantities, false, available_units),
        setup_durations: service.activity ? [service.activity.setup_duration] : service.activities.collect(&:setup_duration),
        durations: service.activity ? [service.activity.duration] : service.activities.collect(&:duration),
        heuristic_period: period,
        minimum_lapse: service.minimum_lapse,
        maximum_lapse: service.maximum_lapse,
        visits_number: service.visits_number,
        points_ids: service.activity ? [service.activity.point.id || service.activity.point.matrix_id] : service.activities.collect{ |a| a.point.id || a.point.matrix_id },
        tws_sets: service.activity ? [service.activity.timewindows] : service.activities.collect(&:timewindows),
        unavailable_days: service.unavailable_visit_day_indices,
        used_days: [],
        used_vehicles: [],
        priority: service.priority,
        sticky_vehicles_ids: service.sticky_vehicles.collect(&:id),
        positions_in_route: service.activity ? [service.activity.position] : service.activities.collect(&:position),
        nb_activities: service.activity ? 1 : service.activities.size,
        exclusion_cost: service.exclusion_cost || 0,
      }

      @candidate_services_ids << service.id
      @to_plan_service_ids << service.id
    }

    adapt_services_data(vrp) if @same_point_day
  end

  def adapt_services_data(vrp)
    # reminder : services in (relaxed_)same_point_day relation have only one point_id

    @to_plan_service_ids = []
    vrp.points.each{ |point|
      same_located_set = vrp.services.select{ |service|
        (service.activity ? [service.activity] : service.activities).any?{ |activity|
          activity.point.id == point.id
        }
      }.sort_by(&:visits_number)

      next if same_located_set.empty?

      raise OptimizerWrapper.UnsupportedProblemError, 'Same_point_day is not supported if a set has one service with several activities' if same_located_set.any?{ |s| !s.activities.empty? }

      group_tw = best_common_tw(same_located_set)
      if group_tw.empty? && !same_located_set.all?{ |service| @services_data[service[:id]][:tws_sets].first.empty? }
        reject_group(same_located_set)
      else
        representative_ids = []
        # one representative per freq
        same_located_set.group_by{ |service| @services_data[service[:id]][:heuristic_period] }.each{ |_period, sub_set|
          representative_id = sub_set[0][:id]
          representative_ids << representative_id
          @services_data[representative_id][:tws_sets] = [group_tw]
          @services_data[representative_id][:group_duration] = sub_set.sum{ |s| s.activity.duration }
          @same_located[representative_id] = sub_set.delete_if{ |s| s[:id] == representative_id }.collect{ |s| s[:id] }
          @services_data[representative_id][:group_capacity] = Marshal.load(Marshal.dump(@services_data[representative_id][:capacity]))
          @same_located[representative_id].each{ |service_id|
            @services_data[service_id][:capacity].each{ |unit, value| @services_data[representative_id][:group_capacity][unit] += value }
            @services_data[service_id][:tws_sets] = [group_tw]
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
      [service.activity ? [service.activity] : service.activities].flatten.each{ |activity|
        @indices[activity.point.id] = activity.point.matrix_index
      }
    }

    @indices.each_key{ |point_id|
      @points_vehicles_and_days[point_id] = { vehicles: [], days: [], maximum_visits_number: 0 }
    }
  end

  def reject_group(group)
    group.each{ |service|
      (1..service.visits_number).each{ |index|
        @candidate_services_ids.delete(service[:id])
        @uninserted["#{service[:id]}_#{index}_#{service.visits_number}"] = {
          original_service: service[:id],
          reason: 'Same_point_day conflict : services at this geografical point have no compatible timewindow'
        }
      }
    }
  end

  def compute_latest_authorized
    all_days = @candidate_routes.collect{ |_vehicle, data| data.keys }.flatten.uniq.sort

    @services_data.group_by{ |_id, data| [data[:visits_number], data[:heuristic_period]] }.each{ |parameters, set|
      visits_number, lapse = parameters
      @max_day[visits_number] = {} unless @max_day[visits_number]
      @max_day[visits_number][lapse] = compute_last_authorized_day(all_days, visits_number, lapse)
    }
  end

  def compute_last_authorized_day(available_days, visits_number, lapse)
    current_day = available_days.last
    real_day = available_days.last

    return current_day if visits_number == 1

    visits_done = 1
    while visits_done < visits_number
      real_day -= lapse
      current_day = available_days.select{ |day| day <= real_day.round }.max
      visits_done += 1
    end

    current_day
  end

  def best_common_tw(set)
    ### finds the biggest tw common to all services in [set] ###
    first_with_tw = set.find{ |service| !@services_data[service[:id]][:tws_sets].first.empty? }
    if first_with_tw
      group_tw = @services_data[first_with_tw[:id]][:tws_sets].first.collect{ |tw| { day_index: tw[:day_index], start: tw[:start], end: tw[:end] } }
      # all timewindows are assigned to a day
      group_tw.select{ |timewindow| timewindow[:day_index].nil? }.each{ |tw|
        (0..6).each{ |day|
          group_tw << { day_index: day, start: tw[:start], end: tw[:end] }
        }
      }
      group_tw.delete_if{ |tw| tw[:day_index].nil? }

      # finding minimal common timewindow
      set.each{ |service|
        next if @services_data[service[:id]][:tws_sets].first.empty?

        # remove all tws with no intersection with this service tws
        group_tw.delete_if{ |tw1|
          @services_data[service[:id]][:tws_sets].first.none?{ |tw2|
            (tw1[:day_index].nil? || tw2[:day_index].nil? || tw1[:day_index] == tw2[:day_index]) &&
              (tw1[:start].nil? || tw2[:end].nil? || tw1[:start] <= tw2[:end]) &&
              (tw1[:end].nil? || tw2[:start].nil? || tw1[:end] >= tw2[:start])
          }
        }

        next if group_tw.empty?

        # adjust all tws with intersections with this point tws
        @services_data[service[:id]][:tws_sets].first.each{ |tw1|
          intersecting_tws = group_tw.select{ |tw2|
            (tw1[:day_index].nil? || tw2[:day_index].nil? || tw1[:day_index] == tw2[:day_index]) &&
              (tw2[:start].nil? || tw2[:start].between?(tw1[:start], tw1[:end]) || tw2[:start] <= tw1[:start]) &&
              (tw2[:end].nil? || tw2[:end].between?(tw1[:start], tw1[:end]) || tw2[:end] >= tw1[:end])
          }
          next if intersecting_tws.empty?

          intersecting_tws.each{ |tw2|
            tw2[:start] = [tw2[:start], tw1[:start]].max
            tw2[:end] = [tw2[:end], tw1[:end]].min
          }
        }
      }

      group_tw.delete_if{ |tw| tw[:start] && tw[:end] && tw[:start] == tw[:end] }
      group_tw
    else
      []
    end
  end

  def compute_capacities(quantities, vehicle, available_units = [])
    return {} if quantities.nil?

    capacities = {}
    quantities.each{ |unit|
      if vehicle
        if capacities[unit[:unit][:id]]
          capacities[unit[:unit][:id]] += unit[:limit].to_f
        else
          capacities[unit[:unit][:id]] = unit[:limit].to_f
        end
      elsif available_units.include?(unit[:unit][:id])
        # if vehicled do not have this unit then this unit should be ignored
        # with clustering, issue is open about assigning vehicles with right capacities to services
        if capacities[unit[:unit][:id]]
          capacities[unit[:unit][:id]] += unit[:value].to_f
        else
          capacities[unit[:unit][:id]] = unit[:value].to_f
        end
      end
    }

    capacities
  end
end
