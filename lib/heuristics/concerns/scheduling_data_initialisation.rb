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
    @expanded_vehicles.each{ |vehicle|
      @indices[vehicle[:start_point_id]] = vrp[:points].find{ |pt| pt[:id] == vehicle[:start_point_id] }[:matrix_index] if vehicle[:start_point_id]
      @indices[vehicle[:end_point_id]] = vrp[:points].find{ |pt| pt[:id] == vehicle[:end_point_id] }[:matrix_index] if vehicle[:end_point_id]

      original_vehicle_id = vehicle[:id].split('_').slice(0, vehicle[:id].split('_').size - 1).join('_')
      capacity = compute_capacities(vehicle[:capacities], true)
      vrp.units.reject{ |unit| capacity.keys.include?(unit[:id]) }.each{ |unit| capacity[unit[:id]] = 0.0 }
      @candidate_routes[original_vehicle_id][vehicle[:global_day_index]] = {
        vehicle_id: vehicle[:id],
        global_day_index: vehicle[:global_day_index],
        tw_start: vehicle.timewindow.start < 84600 ? vehicle.timewindow.start : vehicle.timewindow.start - ((vehicle.global_day_index + @shift) % 7) * 86400,
        tw_end: vehicle.timewindow.end < 84600 ? vehicle.timewindow.end : vehicle.timewindow.end - ((vehicle.global_day_index + @shift) % 7) * 86400,
        start_point_id: vehicle[:start_point_id],
        end_point_id: vehicle[:end_point_id],
        duration: vehicle[:duration] || (vehicle.timewindow.end - vehicle.timewindow.start),
        matrix_id: vehicle[:matrix_id],
        current_route: [],
        capacity: capacity,
        capacity_left: Marshal.load(Marshal.dump(capacity)),
        maximum_ride_time: vehicle[:maximum_ride_time],
        maximum_ride_distance: vehicle[:maximum_ride_distance],
        router_dimension: vehicle[:router_dimension].to_sym
      }
      @vehicle_day_completed[original_vehicle_id][vehicle.global_day_index] = false
    }

    initialize_routes(vrp.routes) unless vrp.routes.empty?
  end

  def collect_services_data(vrp)
    epoch = Date.new(1970, 1, 1)
    available_units = vrp.vehicles.collect{ |vehicle| vehicle[:capacities] ? vehicle[:capacities].collect{ |capacity| capacity[:unit_id] } : nil }.flatten.compact.uniq
    vrp.services.each{ |service|
      service[:unavailable_visit_day_indices] += service[:unavailable_visit_day_date].to_a.collect{ |unavailable_date|
        (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
      }.compact
      has_only_one_day = vrp.vehicles.all?{ |v| v.timewindow&.day_index || v.sequence_timewindows.size == 1 && v.sequence_timewindows.first.day_index }
      period = if service[:visits_number] == 1
                  nil
                elsif has_only_one_day
                  service[:minimum_lapse] ? (service[:minimum_lapse].to_f / 7).ceil * 7 : 7
                else
                  service[:minimum_lapse] ? service[:minimum_lapse] : 1
                end
      @services_data[service.id] = {
        capacity: compute_capacities(service[:quantities], false, available_units),
        setup_duration: service[:activity][:setup_duration],
        duration: service[:activity][:duration],
        heuristic_period: period,
        nb_visits: service[:visits_number],
        point_id: service[:activity][:point][:location] ? service[:activity][:point][:location][:id] : service[:activity][:point][:matrix_index],
        tw: service[:activity][:timewindows] || [],
        unavailable_days: service[:unavailable_visit_day_indices],
        priority: service.priority,
        sticky_vehicles_ids: service.sticky_vehicles.collect(&:id),
      }

      @candidate_services_ids << service.id
      @to_plan_service_ids << service.id

      @indices[service[:id]] = vrp[:points].find{ |pt| pt[:id] == service[:activity][:point][:id] }[:matrix_index]
    }

    adapt_services_data(vrp) if @same_point_day
  end

  def adapt_services_data(vrp)
    @to_plan_service_ids = []
    vrp.points.each{ |point|
      same_located_set = vrp.services.select{ |service|
        service[:activity][:point][:location] && service[:activity][:point][:location][:id] == point[:location][:id] ||
          service[:activity][:point_id] == point[:id]
      }.sort_by{ |s| s[:visits_number] }

      next if same_located_set.empty?

      group_tw = best_common_tw(same_located_set)
      if group_tw.empty? && !same_located_set.all?{ |service| @services_data[service[:id]][:tw].nil? || @services_data[service[:id]][:tw].empty? }
        reject_group(same_located_set)
      else
        representative_ids = []
        # one representative per freq
        same_located_set.group_by{ |service| @services_data[service[:id]][:heuristic_period] }.each{ |period, sub_set|
          representative_id = sub_set[0][:id]
          representative_ids << representative_id
          @services_data[representative_id][:tw] = group_tw
          @services_data[representative_id][:group_duration] = sub_set.sum{ |s| s[:activity][:duration] }
          @same_located[representative_id] = sub_set.delete_if{ |s| s[:id] == representative_id }.collect{ |s| s[:id] }
          @services_data[representative_id][:group_capacity] = Marshal.load(Marshal.dump(@services_data[representative_id][:capacity]))
          @same_located[representative_id].each{ |service_id|
            @services_data[service_id][:capacity].each{ |unit, value| @services_data[representative_id][:group_capacity][unit] += value }
          }
        }

        @to_plan_service_ids << representative_ids.last
        @services_unlocked_by[representative_ids.last] = representative_ids.slice(0, representative_ids.size - 1).to_a
      end
    }
  end

  def reject_group(group)
    group.each{ |service|
      (1..service[:visits_number]).each{ |index|
        @candidate_services_ids.delete(service[:id])
        @uninserted["#{service[:id]}_#{index}_#{service[:visits_number]}"] = {
          original_service: service[:id],
          reason: 'Same_point_day conflict : services at this geografical point have no compatible timewindow'
        }
      }
    }
  end

  def compute_latest_authorized
    all_days = @candidate_routes.collect{ |_vehicle, data| data.keys }.flatten.uniq.sort

    @services_data.group_by{ |_id, data| [data[:nb_visits], data[:heuristic_period]] }.each{ |parameters, set|
      nb_visits, lapse = parameters
      @max_day[nb_visits][lapse] = compute_last_authorized_day(all_days, nb_visits, lapse)
    }
  end

  def compute_last_authorized_day(available_days, nb_visits, lapse)
    current_day = available_days.last
    real_day = available_days.last

    return current_day if nb_visits == 1

    visits_done = 1
    while visits_done < nb_visits
      real_day -= lapse
      current_day = available_days.select{ |day| day <= real_day.round }.max
      visits_done += 1
    end

    current_day
  end

  def best_common_tw(set)
    ### finds the biggest tw common to all services in [set] ###
    first_with_tw = set.find{ |service| @services_data[service[:id]][:tw] && !@services_data[service[:id]][:tw].empty? }
    if first_with_tw
      group_tw = @services_data[first_with_tw[:id]][:tw].collect{ |tw| { day_index: tw[:day_index], start: tw[:start], end: tw[:end] } }
      # all timewindows are assigned to a day
      group_tw.select{ |timewindow| timewindow[:day_index].nil? }.each{ |tw|
        (0..6).each{ |day|
          group_tw << { day_index: day, start: tw[:start], end: tw[:end] }
        }
      }
      group_tw.delete_if{ |tw| tw[:day_index].nil? }

      # finding minimal common timewindow
      set.each{ |service|
        next if @services_data[service[:id]][:tw].empty?

        # remove all tws with no intersection with this service tws
        group_tw.delete_if{ |tw1|
          @services_data[service[:id]][:tw].none?{ |tw2|
            (tw1[:day_index].nil? || tw2[:day_index].nil? || tw1[:day_index] == tw2[:day_index]) &&
              (tw1[:start].nil? || tw2[:end].nil? || tw1[:start] <= tw2[:end]) &&
              (tw1[:end].nil? || tw2[:start].nil? || tw1[:end] >= tw2[:start])
          }
        }

        next if group_tw.empty?

        # adjust all tws with intersections with this point tws
        @services_data[service[:id]][:tw].each{ |tw1|
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
