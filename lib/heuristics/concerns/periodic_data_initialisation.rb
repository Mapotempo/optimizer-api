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

  # Generate one route per vehicle and day combination.
  # Provide all route constraints and specificities.
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
        completed: false,
      }
    }
  end

  # In the case routes were provided in vrp,
  # feel routes accordingly
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
      plan_visits_missing_in_routes(defined_route.vehicle_id, defined_route.day_index.to_i, considered_ids)
    }

    considered_ids.each{ |id|
      @services_assignment[id][:missing_visits] = @services_data[id][:raw].visits_number - @services_assignment[id][:days].size
      next unless @services_assignment[id][:missing_visits].positive?

      @services_assignment[id][:unassigned_reasons] |=
        ['Routes provided do not allow to assign this visit because previous visit could not be planned in specified route']
    }
  end

  # In the case routes were provided in vrp, plan missing visits of services
  # whom some visits were partially assigned in routes.
  def plan_visits_missing_in_routes(vehicle_id, day, considered_ids)
    max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
    return unless @candidate_routes[vehicle_id][day]

    @candidate_routes[vehicle_id][day][:stops].sort_by{ |stop|
      @services_data[stop[:id]][:priority].to_f + 1 / (max_priority * @services_data[stop[:id]][:raw].visits_number**2)
    }.each{ |stop|
      next if @services_assignment[stop[:id]][:days].size == @services_data[stop[:id]][:raw].visits_number ||
              # if we assigned less visits (days) than number of times we considered id
              # this implies we could not insert one visit to its route. Therefore planning missing
              # visits might generate unconsistency with provided data
              @services_assignment[stop[:id]][:days].size < considered_ids.count(stop[:id])

      # TODO : try to affect missing visits with add_missing visits functions
      # (because plan_next_visits only plans after last planned day, not in between)
      plan_next_visits(vehicle_id, stop[:id], @services_assignment[stop[:id]][:days].size + 1)
      @output_tool&.insert_visits(@services_assignment[stop[:id]][:days], stop[:id], @services_data[id][:visits_number])
    }
  end

  # Deduce lapse to use in heuristic according to minimum/maximum_lapse
  # and the fact of being in a work_day configuration or not.
  # This could be improved (issue 452, 664)
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

  # Provide all services's visits and activities specificities
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

    adapt_services_data
  end

  # Fill correspondance with common timewindows from set_timewindows
  def fill_correspondance_for(set_timewindows, correspondance)
    # set_timewindows may contain same timewindow (start/end/day_index) several times
    # but we can not know because timewindow.id is different :
    uniq_set_timewindows =
      set_timewindows.map{ |tw_set|
        tw_set.collect{ |tw|
          [[:start, tw.start], [:end, tw.end], [:day_index, tw.day_index]].to_h
        }
      }.uniq
    correspondance[set_timewindows] = best_common_tws(uniq_set_timewindows)
  end

  # In the case same_point_day option is activated, choose one representative
  # per point_id. Representative is one service with highest number of visits.
  # Only when representative is assigned we can assign remaining services at this point,
  # with same and lower frequence.
  # This is relaxed at @relaxed_same_point_day stage.
  def adapt_services_data
    # REMINDER : services in (relaxed_)same_point_day relation can only have one point_id
    return unless @same_point_day

    @to_plan_service_ids = []
    correspondance = {}
    @services_data.group_by{ |_id, data| data[:points_ids].first }.each{ |_point_id, same_located_set|
      same_located_set.sort_by!{ |_id, data| data[:raw].visits_number }
      set_timewindows = same_located_set.map{ |_id, data| data[:tws_sets].flatten }.uniq
      fill_correspondance_for(set_timewindows, correspondance) unless correspondance[set_timewindows]
      if correspondance[set_timewindows].empty? && !same_located_set.all?{ |_id, data| data[:tws_sets].first.empty? }
        reject_group(same_located_set,
                     'Same_point_day conflict : services at this geographical point have no compatible timewindow')
      else
        representative_ids = [] # also one representative per freq
        same_located_set.group_by{ |_id, data| data[:raw].visits_number }.sort_by{ |visits_number, _sub_set|
          visits_number
        }.each{ |_visits_number, sub_set|
          representative_id = sub_set[0][0]
          representative_ids << representative_id
          sub_set[0][1][:tws_sets] = [correspondance[set_timewindows]]
          sub_set[0][1][:group_duration] = sub_set.sum{ |_id, data| data[:durations].first }
          @same_freq_and_location[representative_id] = sub_set.collect(&:first) - [representative_id]
          sub_set[0][1][:group_capacity] = Marshal.load(Marshal.dump(sub_set[0][1][:capacity]))
          @same_freq_and_location[representative_id].each{ |id|
            @services_data[id][:capacity].each{ |unit, value| sub_set[0][1][:group_capacity][unit] += value }
            @services_data[id][:tws_sets] = [correspondance[set_timewindows]]
          }
        }

        @to_plan_service_ids << representative_ids.last
        @services_unlocked_by[representative_ids.last] = representative_ids.slice(0, representative_ids.size - 1).to_a
      end
    }
  end

  # Simplifies time/distance computation between stops
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
      @points_assignment[point_id] = { vehicles: [], days: [] }
    }
  end

  # Reject all vists of each service in group with specified reason
  def reject_group(group, specified_reason)
    group.each{ |id, data| reject_all_visits(id, data[:raw].visits_number, specified_reason) }
  end

  # Return wether timewindow and other_timewindow have any overlap
  def compatible_timewindows?(timewindow, other_timewindow)
    # TODO : it would be better to use this function from timewindow.rb
    # However, if we work with timewindows we can not, for now, use 'uniq' on
    # timewindows because we sometimes have same ID for timewindows with same start/end/day_index.
    # Therefor we might recursively call best_common_tws more than needed
    return false if timewindow[:day_index] && other_timewindow[:day_index] &&
                    timewindow[:day_index] != other_timewindow[:day_index]

    (timewindow[:end].nil? || other_timewindow[:start].nil? || other_timewindow[:start] <= timewindow[:end]) &&
      (timewindow[:start].nil? || other_timewindow[:end].nil? || other_timewindow[:end] >= timewindow[:start])
  end

  # Compute biggest common timewindows for all services in set
  def best_common_tws(all_timewindows_sets)
    # TODO : improve with issue272

    return [] if all_timewindows_sets == [[]]

    return all_timewindows_sets.first if all_timewindows_sets.size == 1

    if all_timewindows_sets.size > 2

      return best_common_tws([all_timewindows_sets.first, best_common_tws(all_timewindows_sets[1..-1])])
    end

    referent_tws, other_tws = all_timewindows_sets.dup
    referent_tws.delete_if{ |tw|
      other_tws.none?{ |other_tw| compatible_timewindows?(tw, other_tw) }
    }
    other_tws.delete_if{ |other_tw|
      referent_tws.none?{ |tw| compatible_timewindows?(other_tw, tw) }
    }

    return [] if [referent_tws.size, other_tws.size].min.zero?

    biggest_set, smallest_set = referent_tws.size > other_tws.size ? [referent_tws, other_tws] : [other_tws, referent_tws]
    biggest_set.flat_map{ |tw|
      compatible_set = smallest_set.select{ |other_tw| compatible_timewindows?(tw, other_tw) }
      compatible_set << tw

      Models::Timewindow.create(start: compatible_set.map{ |t| t[:start] }.max,
                                end: compatible_set.map{ |t| t[:end] }.min,
                                day_index: compatible_set.map{ |t| t[:day_index] }.compact.first)
    }
  end

  # Unifies quantities and capacities
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
