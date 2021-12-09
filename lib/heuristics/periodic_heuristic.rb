# Copyright © Mapotempo, 2018
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

require './lib/helper.rb'
require './wrappers/wrapper.rb'
require './lib/heuristics/concerns/periodic_data_initialisation'
require './lib/heuristics/concerns/periodic_end_phase'

module Wrappers
  class PeriodicHeuristic < Wrapper
    include PeriodicDataInitialization
    include PeriodicEndPhase

    def initialize(vrp, job = nil)
      return if vrp.services.empty?

      # global data
      @schedule_end = vrp.configuration.schedule.range_indices[:end]
      @allow_partial_assignment = vrp.configuration.resolution.allow_partial_assignment
      @same_point_day = vrp.configuration.resolution.same_point_day
      @relaxed_same_point_day = false
      @duration_in_tw = false # TODO: create parameter for this
      @spread_among_days = !vrp.configuration.resolution.minimize_days_worked

      # heuristic data
      @services_data = {}
      @candidate_services_ids = []
      @to_plan_service_ids = []
      @used_to_adjust = []

      @candidate_routes = {}
      @services_assignment = {} # For each service_id, specifies how it has been assigned
      @points_assignment = {} # For each service_id, specifies how it has been assigned
      vrp.vehicles.group_by(&:original_id).each{ |vehicle_id, _set|
        @candidate_routes[vehicle_id] = {}
      }

      @indices = {}
      @matrices = vrp[:matrices]

      # same_point_day : service with higher heuristic_period unlocks others
      @services_unlocked_by = {}
      @unlocked = {}
      @same_located = {}

      @output_tool =
        if OptimizerWrapper.config[:debug][:output_periodic]
          OutputHelper::PeriodicHeuristic.new(vrp.name, @candidate_vehicles, job, @schedule_end)
        end

      generate_route_structure(vrp)
      collect_services_data(vrp)
      @max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
      collect_indices(vrp)
      compute_latest_authorized
      @cost = 0
      initialize_routes(vrp.routes) unless vrp.routes.empty?

      # secondary data
      @previous_candidate_service_ids = nil
      @previous_uninserted = nil
      @previous_candidate_routes = nil
    end

    def compute_initial_solution(vrp, &block)
      if vrp.services.empty?
        # TODO : create and use result structure instead of using wrapper function
        vrp.configuration.preprocessing.heuristic_result = vrp.empty_solution(:heuristic)
        return []
      end

      block&.call(nil, nil, nil, 'periodic heuristic - start solving', nil, nil, nil)
      @starting_time = Time.now
      @output_tool&.add_comment('COMPUTE_INITIAL_SOLUTION')

      fill_days

      # Relax same_point_day constraint
      if @same_point_day && !@candidate_services_ids.empty?
        # If there are still unassigned visits
        # relax the @same_point_day constraint but
        # keep the logic of unlocked for less frequent visits.
        # We still call fill_days but with same_point_day = false
        @output_tool&.add_comment('RELAX_SAME_POINT_DAY')
        @to_plan_service_ids = @candidate_services_ids
        @same_point_day = false
        @relaxed_same_point_day = true
        fill_days
      end

      save_status

      # Reorder routes with solver and try to add more visits
      if vrp.configuration.resolution.solver && !@candidate_services_ids.empty?
        block&.call(nil, nil, nil, 'periodic heuristic - re-ordering routes', nil, nil, nil)
        reorder_stops(vrp)
        @output_tool&.add_comment('FILL_AFTER_REORDERING')
        fill_days
      end

      refine_solution(&block)

      begin
        check_solution_validity
      rescue StandardError
        log 'Solution after calling solver to reorder routes is unfeasible.', level: :warn
        restore
      end

      check_solution_validity

      @output_tool&.close_file

      block&.call(nil, nil, nil, 'periodic heuristic - preparing result', nil, nil, nil)
      prepare_output_and_collect_routes(vrp)
    end

    def compute_consistent_positions_to_insert(position_requirement, service_points_ids, route)
      first_index = 0
      last_index = route.size

      first_unforced_first = (0..route.size).find{ |position|
        route[position].nil? || (route[position][:requirement] != :always_first &&
          route[position][:requirement] != :never_middle)
      }
      first_forced_last = (0..route.size).find{ |position|
        route[position].nil? || route[position][:requirement] == :always_last || position > first_unforced_first &&
          route[position][:requirement] == :never_middle
      }
      positions_to_try =
        case position_requirement
        when :always_first
          (first_index..first_unforced_first).to_a
        when :always_middle
          full = (first_unforced_first..first_forced_last).to_a
          cleaned = full - (0..first_unforced_first - 1).to_a - (first_forced_last + 1..last_index).to_a
          cleaned.delete(0)           # can not be the very first
          cleaned.delete(route.size)  # can not be the very last
          cleaned
        when :always_last
          (first_forced_last..last_index).to_a
        when :never_first
          route.empty? ? [] : ([1, first_unforced_first].max..first_forced_last).to_a
        when :never_middle
          ((first_index..first_unforced_first).to_a + (first_forced_last..last_index).to_a).uniq
        when :never_last
          route.empty? || [route.size - 1, first_forced_last].min < first_unforced_first ?
            [] : (first_unforced_first..[(route.size - 1), first_forced_last].min).to_a
        else # position_requirement == :neutral
          (first_unforced_first..first_forced_last).to_a
        end

      if service_points_ids.size == 1 &&
         positions_to_try.find{ |position| route[position] && route[position][:point_id] == service_points_ids.first }
        same_location_position = positions_to_try.select{ |position|
          route[position] && route[position][:point_id] == service_points_ids.first
        }
        positions_to_try.delete_if{ |position|
          !same_location_position.include?(position) &&
            !same_location_position.include?(position - 1)
        }
      end

      positions_to_try
    end

    def check_stops_timewindows_respected(route_data)
      route_data[:stops].each_with_index{ |s, i|
        next if @services_data[s[:id]][:tws_sets].flatten.empty? ||
                i.positive? && can_ignore_tw(route_data[:stops][i - 1][:id], s[:id])

        compatible_tw =
          find_corresponding_timewindow(
            route_data[:day], s[:arrival], @services_data[s[:id]][:tws_sets][s[:activity]], s[:end] - s[:arrival])
        next if compatible_tw &&
                s[:arrival].round.between?(compatible_tw[:start], compatible_tw[:end]) &&
                (!@duration_in_tw || s[:end] <= compatible_tw[:end])

        raise OptimizerWrapper::PeriodicHeuristicError.new('One service timewindows violated')
      }
    end

    def check_consistent_generated_ids
      return false unless @services_assignment[@services_data.keys.first][:assigned_indices]

      @services_assignment.each{ |id, data|
        generated_indices = data[:assigned_indices] + data[:unassigned_indices]

        next unless generated_indices.size != generated_indices.uniq.size ||
                    generated_indices.size != @services_data[id][:raw].visits_number ||
                    generated_indices.max > @services_data[id][:raw].visits_number ||
                    generated_indices.max < 1 ||
                    data[:unassigned_indices].size != data[:missing_visits]

        raise OptimizerWrapper::PeriodicHeuristicError.new('Inconsistent IDs generated')
      }
    end

    def check_solution_validity
      @candidate_routes.each{ |_vehicle_id, all_routes|
        all_routes.each{ |_day, route_data|
          next if route_data[:stops].empty?

          back_to_depot = route_data[:stops].last[:end] +
                          matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])

          if route_data[:stops][0][:start] < route_data[:tw_start]
            raise OptimizerWrapper::PeriodicHeuristicError.new('One vehicle is starting too soon')
          end

          if back_to_depot > route_data[:tw_end]
            raise OptimizerWrapper::PeriodicHeuristicError.new('One vehicle is ending too late')
          end

          check_stops_timewindows_respected(route_data)
        }
      }
    end

    private

    # Ensures `day` is compatible with other already assigned visits with this ID
    # regarding first/last_possible_days available ranges : it is possible to find a
    # pair of first/last_possible_day for each and every day used for this service_id
    def day_in_possible_interval(service_id, day)
      all_days = (@services_assignment[service_id][:days] + [day]).sort
      seen_visits = 0

      return false if all_days.size > @services_data[service_id][:raw].visits_number

      @services_data[service_id][:raw].visits_number.times{ |tried_indices|
        next unless all_days[seen_visits].between?(@services_data[service_id][:raw].first_possible_days[tried_indices],
                                                   @services_data[service_id][:raw].last_possible_days[tried_indices])

        seen_visits += 1 # This combination can accept this day

        break if seen_visits == all_days.size
      }

      seen_visits == all_days.size
    end

    def reject_according_to_allow_partial_assignment(service_id, impacted_days)
      if @allow_partial_assignment
        @services_assignment[service_id][:unassigned_reasons] |=
          ['Visit not assignable by heuristic because of previous visits assignment']
        [impacted_days, false]
      else
        clean_stops(service_id)
        [[], true]
      end
    end

    def plan_next_visits(vehicle_id, service_id, first_unseen_visit)
      return if @services_data[service_id][:raw].visits_number == 1

      impacted_days = []
      next_day = @services_assignment[service_id][:days].max + @services_data[service_id][:heuristic_period]
      day_to_insert = @candidate_routes[vehicle_id].keys.select{ |day| day >= next_day.round }.min

      cleaned_service = false
      (first_unseen_visit..@services_data[service_id][:raw].visits_number).each{ |_visit_number|
        inserted_day = nil
        while inserted_day.nil? && day_to_insert && day_to_insert <= @schedule_end && !cleaned_service
          diff = day_to_insert - next_day.round
          next_day += diff

          inserted_day = try_to_insert_at(vehicle_id, day_to_insert, service_id)

          next_day += @services_data[service_id][:heuristic_period]
          day_to_insert = @candidate_routes[vehicle_id].keys.select{ |day| day >= next_day.round }.min
        end

        if inserted_day
          impacted_days |= [inserted_day]
        else
          impacted_days, cleaned_service =
            reject_according_to_allow_partial_assignment(service_id, impacted_days)
        end
      }

      impacted_days
    end

    def adjust_candidate_routes(vehicle_id, day_finished)
      ### assigns all visits of services in [services] that where newly scheduled on [vehicle_id] at [day_finished] ###
      @candidate_routes[vehicle_id][day_finished][:stops].sort_by{ |stop| @services_data[stop[:id]][:priority] }.flat_map{ |stop|
        next if @used_to_adjust.include?(stop[:id])

        @used_to_adjust << stop[:id]
        @output_tool&.insert_visits(@services_assignment[stop[:id]][:days], stop[:id], @services_data[stop[:id]][:raw].visits_number)

        plan_next_visits(vehicle_id, stop[:id], 2)
      }.compact
    end

    def update_route(route_data, first_index, first_start = nil)
      # recomputes each stop associated values (start, arrival, setup ... times) only according to their insertion order
      route = route_data[:stops]
      return route if route.empty? || first_index > route.size

      previous_id = first_index.zero? ? route_data[:start_point_id] : route[first_index - 1][:id]
      previous_point_id = first_index.zero? ? previous_id : route[first_index - 1][:point_id]
      previous_end = first_index.zero? ? route_data[:tw_start] : route[first_index - 1][:end]
      if first_start
        previous_end = first_start
      end

      (first_index..route.size - 1).each{ |position|
        stop = route[position]
        route_time = matrix(route_data, previous_point_id, stop[:point_id])
        stop[:considered_setup_duration] = route_time.zero? ? 0 : @services_data[stop[:id]][:setup_durations][stop[:activity]]

        if can_ignore_tw(previous_id, stop[:id])
          stop[:start] = previous_end
          stop[:arrival] = previous_end
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:durations][stop[:activity]]
          stop[:max_shift] = route[position - 1][:max_shift]
        else
          tw = find_corresponding_timewindow(route_data[:day],
                                             previous_end + route_time + stop[:considered_setup_duration],
                                             @services_data[stop[:id]][:tws_sets][stop[:activity]], stop[:end] - stop[:arrival])
          if @services_data[stop[:id]][:tws_sets][stop[:activity]].any? && tw.nil?
            raise OptimizerWrapper::PeriodicHeuristicError.new('No timewindow found to update route')
          end

          stop[:start] = tw ? [tw[:start] - route_time - stop[:considered_setup_duration], previous_end].max : previous_end
          stop[:arrival] = stop[:start] + route_time + stop[:considered_setup_duration]
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:durations][stop[:activity]]
          stop[:max_shift] = tw ? tw[:end] - stop[:arrival] : nil
        end

        previous_id = stop[:id]
        previous_point_id = stop[:point_id]
        previous_end = stop[:end]
      }

      if route.any? &&
         route.last[:end] + matrix(route_data, route.last[:point_id], route_data[:end_point_id]) > route_data[:tw_end]
        raise OptimizerWrapper::PeriodicHeuristicError.new('Vehicle end violated after updating route')
      end

      route
    end

    def exist_possible_first_route_according_to_same_point_day?(service_id, point_id)
      # TODO : eventually consider unavailable_days here
      return true unless @same_point_day || @relaxed_same_point_day

      return true unless @unlocked.key?(service_id) && @services_data[service_id][:raw].visits_number > 1

      available_days = @points_assignment[point_id][:days]
      current_day = available_days.first
      seen_visits = 1
      while seen_visits < @services_data[service_id][:raw].visits_number && current_day
        current_day = available_days.find{ |day| day >= current_day + @services_data[service_id][:heuristic_period] }
        seen_visits += 1 if current_day
      end

      seen_visits == @services_data[service_id][:raw].visits_number
    end

    def provide_fair_reason(service_id)
      reason = 'Heuristic could not affect this service before all vehicles are full'

      # if no capacity limitation, would there be a way to assign this service
      # while respecting same_point_day constraints ?
      point_id = @services_data[service_id][:points_ids][0]
      unless exist_possible_first_route_according_to_same_point_day?(service_id, point_id)
        reason = "All this service's visits can not be assigned with other services at same location"
      end
      reason
    end

    def collect_unassigned
      unassigned = []

      @services_assignment.each{ |id, data|
        next unless data[:unassigned_indices].any?

        if @candidate_services_ids.include?(id)
          @services_assignment[id][:unassigned_reasons] = [provide_fair_reason(id)]
        end

        data[:unassigned_indices].each{ |index|
          service_in_vrp = @services_data[id][:raw]
          unassigned_id = "#{id}_#{index}_#{@services_data[id][:raw].visits_number}"
          unassigned << Models::Solution::Stop.new(service_in_vrp,
                                                   service_id: unassigned_id,
                                                   reason: @services_assignment[id][:unassigned_reasons].join(','))
        }
      }

      unassigned
    end

    def provide_group_tws(services, day)
      services_from_same_point_day_relation = @services_unlocked_by.flat_map{ |id, set| [id, set].flatten }

      services.each{ |service|
        next if !services_from_same_point_day_relation.include?(service.id) ||
                @services_data[service[:id]][:tws_sets].all?(&:empty?)

        start_with_tw = !service.activity.timewindows.empty?
        service.activity.timewindows.delete_if{ |tw| tw.day_index && tw.day_index != day % 7 }

        # since service is in a same_point_day_relation then it has only one timewindow_set and duration :

        service.activity.timewindows.each{ |original_tw|
          corresponding = find_corresponding_timewindow(day, original_tw.start, @services_data[service[:id]][:tws_sets].first, @services_data[service[:id]][:durations].first)
          corresponding = find_corresponding_timewindow(day, original_tw.end, @services_data[service[:id]][:tws_sets].first, @services_data[service[:id]][:durations].first) if corresponding.nil?

          if corresponding.nil?
            service.activity.timewindows.delete(original_tw)
          else
            original_tw.start = corresponding[:start]
            original_tw.end = corresponding[:end]
            original_tw.day_index = corresponding[:day_index]
          end
        }

        log 'No group timewindow was found even if it shoud', level: :warn if start_with_tw && service.activity.timewindows.empty?
      }
    end

    def reorder_stops(vrp)
      @candidate_routes.each{ |vehicle_id, all_routes|
        all_routes.each{ |day, route_data|
          next if route_data[:stops].uniq{ |s| s[:point_id] }.size <= 1

          corresponding_vehicle = vrp.vehicles.find{ |v| v.id == "#{vehicle_id}_#{day}" }
          corresponding_vehicle.timewindow.start = route_data[:tw_start]
          corresponding_vehicle.timewindow.end = route_data[:tw_end]
          route_vrp = construct_sub_vrp(vrp, corresponding_vehicle, route_data[:stops])

          log "Re-ordering route for #{vehicle_id} at day #{day} : #{route_data[:stops].size}"

          # TODO : test with and without providing initial solution ?
          route_vrp.routes = collect_generated_routes(route_vrp.vehicles.first, route_data[:stops])
          route_vrp.services = provide_group_tws(route_vrp.services, day) if @same_point_day || @relaxed_same_point_day # to have same data in ORtools and periodic. Customers should ensure all timewindows are the same for same points

          solution = OptimizerWrapper.solve(service: :ortools, vrp: route_vrp)

          next if solution.nil? || !solution.unassigned.empty?

          back_to_depot = route_data[:stops].last[:end] +
                          matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])
          periodic_route_time = back_to_depot - route_data[:stops].first[:start]
          solver_route_time = (solution.routes.first.stops.last.info.begin_time -
                              solution.routes.first.stops.first.info.begin_time) # last activity is vehicle depot

          minimum_duration = @candidate_services_ids.flat_map{ |s| @services_data[s][:durations] }.min
          original_indices = route_data[:stops].collect{ |s| @indices[s[:id]] }
          next if periodic_route_time - solver_route_time < minimum_duration ||
                  solution.routes.first.stops.collect{ |act| @indices[act.service_id] }.compact == original_indices # we did not change our points order

          route_data[:stops] = compute_route_from(route_data, solution.routes.first.stops)
        }
      }
    end

    def clean_position_dependent_services(stops, removed_index)
      return if stops.empty?

      if removed_index == stops.size
        index = removed_index - 1
        while stops[index] && [:never_last, :always_middle].include?(stops[index][:requirement])
          clean_stops(stops[index][:id], true)
          # index removed so no need to increment index
        end
      end

      index = removed_index
      while stops[index] && [:never_first, :always_middle].include?(stops[index][:requirement])
        clean_stops(stops[index][:id], true)
        # index removed so no need to increment index
      end
    end

    def make_available(service_id)
      @candidate_services_ids << service_id
      @candidate_routes.each{ |_vehicle_id, all_routes|
        all_routes.each{ |day, route_data|
          next unless day <= @services_data[service_id][:raw].last_possible_days.first # first is for first visit

          route_data[:available_ids] |= service_id
        }
      }
      @services_assignment[service_id][:missing_visits] = @services_data[service_id][:raw].visits_number
      @services_assignment[:unassigned_reasons] = []
    end

    def clean_stops(service_id, reaffect = false)
      ### when allow_partial_assignment is false, removes all affected visits of [service_id] because we can not affect all visits ###
      @services_assignment[service_id][:vehicles].each{ |vehicle_id|
        @services_assignment[service_id][:days].each{ |day|
          route_data = @candidate_routes[vehicle_id][day]
          removed_index = route_data[:stops].find_index{ |stop| stop[:id] == service_id }
          next unless removed_index

          service_point = route_data[:stops][removed_index][:point_id]
          route_data[:stops].slice!(removed_index)
          @services_data[service_id][:capacity].each{ |need, qty| route_data[:capacity_left][need] += qty }

          if route_data[:stops].none?{ |s| s[:point_id] == service_point }
            @points_assignment[service_point][:days].delete(day)
            vehicle_still_used =
              @points_assignment[service_point][:days].any?{ |d|
                @candidate_routes[vehicle_id][d][:stops].any?{ |stop| stop[:point_id] == service_point }
              }
            @points_assignment[service_point][:vehicles].delete(vehicle_id) unless vehicle_still_used
          end

          clean_position_dependent_services(route_data[:stops], removed_index)
          route_data[:stops] = update_route(route_data, removed_index)
        }
      }
      @services_assignment[service_id] = {
        vehicles: [], days: [], missing_visits: @services_data[service_id][:raw].visits_number, unassigned_reasons: []
      }

      if reaffect
        make_available(service_id)
        return
      else
        reject_all_visits(service_id, @services_data[service_id][:raw].visits_number, 'Partial assignment only')
      end

      # Unaffect all points at this location
      # FIXME : do we really want to unaffect those ?
      points_at_same_location = @candidate_services_ids.select{ |id| @services_data[id][:points_ids] == @services_data[service_id][:points_ids] }
      points_at_same_location.each{ |id|
        @services_assignment[id][:unassigned_reasons] |= ['Partial assignment only']
        @candidate_services_ids.delete(id)
        @to_plan_service_ids.delete(id)
      }
    end

    def compute_route_from(new_route, solver_route)
      solver_order = solver_route.collect{ |s| s[:service_id] }.compact
      new_route[:stops].sort_by!{ |stop| solver_order.find_index(stop[:id]) }.collect{ |s| s[:id] }
      update_route(new_route, 0, solver_route.first.info.begin_time)
    end

    def compute_costs_for_route(route_data, set = nil)
      ### for each remaining service to assign, computes the cost of assigning it to [route_data] ###
      unless set
        set = @to_plan_service_ids
        set.delete_if{ |id| @services_data[id][:raw].visits_number == 1 } if @same_point_day
      end

      day = route_data[:day]
      set.collect{ |service_id|
        next if @services_assignment[service_id][:days] &&
                !days_respecting_lapse(service_id, @candidate_routes[route_data[:vehicle_original_id]]).include?(day)

        find_best_index(service_id, route_data)
      }.compact
    end

    def same_point_compatibility(service_id, day)
      # REMINDER : services in (relaxed_)same_point_day relation can only have one point_id
      same_point = @services_data[service_id][:points_ids].first
      return true unless (@relaxed_same_point_day || @same_point_day) && @points_assignment[same_point][:days].any?

      if @services_data[service_id][:heuristic_period].nil?
        return @points_assignment[same_point][:days].include?(day)
      end

      min_overall_lapse =
        (@services_data[service_id][:raw].visits_number - 1) * @services_data[service_id][:heuristic_period]
      if @relaxed_same_point_day
        involved_days = (day..day + min_overall_lapse).step(@services_data[service_id][:heuristic_period]).to_a
        common_days = involved_days & @points_assignment[same_point][:days]
        expected_number =
          if @services_data[service_id][:raw].visits_number > @points_assignment[same_point][:maximum_visits_number]
            @points_assignment[same_point][:maximum_visits_number]
          else
            involved_days.size
          end

        return common_days.size == expected_number
      elsif @unlocked.key?(service_id)
        # can not finish later (over whole period) than service at same point
        last_visit_day = day + min_overall_lapse
        last_possible_day = @points_assignment[same_point][:days].max
        return last_visit_day <= last_possible_day
      end

      true
    end

    def compute_shift(route_data, service_inserted, inserted_final_time, next_service)
      if next_service
        shift = 0
        time_to_next = matrix(route_data, service_inserted[:point_id], next_service[:point_id])
        if can_ignore_tw(service_inserted[:id], next_service[:id])
          prospective_next_end = inserted_final_time + @services_data[next_service[:id]][:durations][next_service[:activity]]
          shift += prospective_next_end - next_service[:end]
        else
          next_service[:tw] = @services_data[next_service[:id]][:tws_sets][next_service[:activity]]
          next_service[:duration] = @services_data[next_service[:id]][:durations][next_service[:activity]]
          next_end = compute_tw_for_next(inserted_final_time, next_service, time_to_next, route_data[:day])
          shift += next_end - next_service[:end]
        end

        shift
      elsif !route_data[:stops].empty?
        inserted_final_time - route_data[:stops].last[:end]
      end
    end

    def compute_tw_for_next(inserted_final_time, route_next, dist_from_inserted, current_day)
      ### compute new start and end times for the service just after inserted point ###
      sooner_start = inserted_final_time
      setup_duration = dist_from_inserted.zero? ? 0 : @services_data[route_next[:id]][:setup_durations][route_next[:activity]]
      if !route_next[:tw].empty?
        tw = find_corresponding_timewindow(current_day, route_next[:arrival], @services_data[route_next[:id]][:tws_sets][route_next[:activity]], route_next[:end] - route_next[:arrival])
        sooner_start = tw[:start] - dist_from_inserted - setup_duration if tw
      end
      new_start = [sooner_start, inserted_final_time].max
      new_arrival = new_start + dist_from_inserted + setup_duration
      new_end = new_arrival + route_next[:duration]

      new_end
    end

    def acceptable?(shift, route_data, position)
      return [true, nil] if route_data[:stops].empty?

      computed_shift = shift
      acceptable = (route_data[:stops][position] && route_data[:stops][position][:max_shift]) ? route_data[:stops][position][:max_shift] >= shift : true

      if acceptable && route_data[:stops][position + 1]
        (position + 1..route_data[:stops].size - 1).each{ |pos|
          initial_shift_with_previous = route_data[:stops][pos][:start] - (route_data[:stops][pos - 1][:end])
          computed_shift = [shift - initial_shift_with_previous, 0].max
          if route_data[:stops][pos][:max_shift] && route_data[:stops][pos][:max_shift] < computed_shift
            acceptable = false
            break
          end
        }
      end

      [acceptable, computed_shift]
    end

    def acceptable_for_group?(service, timewindow)
      return true unless @same_point_day && service[:tw].size.positive? && @same_located[service[:id]]

      acceptable_for_group = true

      additional_durations = service[:duration] + timewindow[:setup_duration]
      @same_located[service[:id]].each{ |id|
        acceptable_for_group = timewindow[:max_shift] - additional_durations >= 0
        additional_durations += @services_data[id][:durations][0] # services in a group relation have only one activity
      }

      acceptable_for_group
    end

    def insertion_cost_with_tw(timewindow, route_data, service, position)
      original_next_activity = route_data[:stops][position][:activity] if route_data[:stops][position]
      nb_activities_index = route_data[:stops][position] ? @services_data[route_data[:stops][position][:id]][:nb_activities] - 1 : 0

      shift, activity_out, time_back_to_depot, tw_accepted = (0..nb_activities_index).collect{ |activity|
        if route_data[:stops][position]
          route_data[:stops][position][:activity] = activity
          route_data[:stops][position][:point_id] = @services_data[route_data[:stops][position][:id]][:points_ids][activity]
        end

        shift = compute_shift(route_data, service, timewindow[:final_time], route_data[:stops][position])
        if route_data[:stops][position + 1] && activity != original_next_activity
          next_id = route_data[:stops][position][:id]
          next_next_point_id = route_data[:stops][position + 1][:point_id]
          shift += matrix(route_data, @services_data[next_id][:points_ids][activity], next_next_point_id) -
                   matrix(route_data, @services_data[next_id][:points_ids][original_next_activity], next_next_point_id)
        end
        acceptable_shift, computed_shift = acceptable?(shift, route_data, position)
        time_back_to_depot =
          if position == route_data[:stops].size
            timewindow[:final_time] + matrix(route_data, service[:point_id], route_data[:end_point_id])
          else
            route_data[:stops].last[:end] + computed_shift +
              matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])
          end

        end_respected = timewindow[:end_tw] ? timewindow[:arrival_time] <= timewindow[:end_tw] : true
        route_start = position.zero? ? timewindow[:start_time] : route_data[:stops].first[:start]
        duration_respected = route_data[:duration] ? time_back_to_depot - route_start <= route_data[:duration] : true
        acceptable_shift_for_itself = end_respected && duration_respected
        tw_accepted = acceptable_shift && acceptable_shift_for_itself && time_back_to_depot <= route_data[:tw_end]

        [shift, activity, time_back_to_depot, tw_accepted]
      }.min_by{ |next_info| next_info[2] }

      route_data[:stops][position][:activity] = original_next_activity if route_data[:stops][position]
      route_data[:stops][position][:point_id] = @services_data[route_data[:stops][position][:id]][:points_ids][original_next_activity] if route_data[:stops][position]

      [activity_out, tw_accepted, shift, time_back_to_depot]
    end

    def ensure_routes_will_not_be_rejected(vehicle_id, impacted_days)
      while impacted_days.size.positive?
        started_day = impacted_days.first
        can_not_insert_more = false
        route_cost_fixed = @candidate_routes[vehicle_id][started_day][:cost_fixed]
        route_exclusion_costs =
          @candidate_routes[vehicle_id][started_day][:stops].map{ |stop|
            @services_data[stop[:id]][:raw].exclusion_cost || 0
          }.reduce(&:+)
        while route_exclusion_costs < route_cost_fixed || can_not_insert_more
          inserted_id, _unlocked_ids = try_to_add_new_point(vehicle_id, started_day)
          impacted_days |= adjust_candidate_routes(vehicle_id, started_day)
          if inserted_id
            route_exclusion_costs += @services_data[inserted_id][:raw].exclusion_cost.to_f
          else
            can_not_insert_more = true
          end
        end

        impacted_days.sort!.delete(started_day)
      end
    end

    def fill_days
      @candidate_routes.each{ |current_vehicle_id, all_routes|
        current_vehicle_index = 0
        break if all_routes.all?{ |_day, route_data| route_data[:completed] }

        possible_to_fill = !@to_plan_service_ids.empty?
        already_considered_days = []
        nb_of_days = all_routes.keys.size
        impacted_days = []

        while possible_to_fill
          best_day = if @spread_among_days
            all_routes.reject{ |day, _route_data| already_considered_days.include?(day) }.min_by{ |_day, route_data|
              route_data[:stops].empty? ? 0 : route_data[:stops].sum{ |stop| stop[:end] - stop[:start] }
            }[0]
          else
              best_day || (all_routes.keys - already_considered_days).min
          end
          break unless best_day

          inserted_id, unlocked_ids = try_to_add_new_point(current_vehicle_id, best_day)
          already_considered_days |= [best_day] unless inserted_id
          already_considered_days = [] unless unlocked_ids.empty?
          possible_to_fill = false if @to_plan_service_ids.empty? || nb_of_days == already_considered_days.size

          if @spread_among_days
            adjust_candidate_routes(current_vehicle_id, best_day)
          elsif inserted_id.nil? || !possible_to_fill
            impacted_days = adjust_candidate_routes(current_vehicle_id, best_day)
            all_routes[best_day][:completed] = true
            ensure_routes_will_not_be_rejected(current_vehicle_id, impacted_days.sort) if @candidate_services_ids.size >= @services_data.size * 0.5 # shouldn't it be < ?

            current_vehicle_index += 1
            if current_vehicle_index == @candidate_routes.keys.size
              best_day = nil
              current_vehicle_index = 0
            end

            current_vehicle_id = @candidate_routes.keys[current_vehicle_index]
          end
        end
      }
    end

    def add_same_freq_located_points(best_index, route_data)
      start = best_index[:end]
      max_shift = best_index[:potential_shift]
      additional_durations = @services_data[best_index[:id]][:durations].first + best_index[:considered_setup_duration]
      @same_located[best_index[:id]].each_with_index{ |service_id, i|
        @services_assignment[service_id][:missing_visits] -= 1
        @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, r_d| r_d[:available_ids].delete(service_id) } }
        @services_assignment[service_id][:days] << route_data[:day]
        @services_assignment[service_id][:vehicles] |= [route_data[:vehicle_original_id]]
        route_data[:stops].insert(best_index[:position] + i + 1,
                                  id: service_id,
                                  point_id: best_index[:point],
                                  start: start,
                                  arrival: start,
                                  end: start + @services_data[service_id][:durations].first,
                                  considered_setup_duration: 0,
                                  max_shift: max_shift ? max_shift - additional_durations : nil,
                                  activity: 0) # when using same_point_day, points in same_located relation can not have serveral activities

        additional_durations += @services_data[service_id][:durations].first
        @to_plan_service_ids.delete(service_id)
        @candidate_services_ids.delete(service_id)
        start += @services_data[service_id][:durations].first
        @services_data[service_id][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
      }
    end

    def try_to_add_new_point(vehicle_id, day)
      insertion_costs = compute_costs_for_route(@candidate_routes[vehicle_id][day])

      return [nil, [], []] if insertion_costs.empty?

      best_index = select_point(insertion_costs, @candidate_routes[vehicle_id][day][:stops].empty?)

      return [nil, [], []] if best_index.nil?

      best_index[:end] = best_index[:end] - @services_data[best_index[:id]][:group_duration] + @services_data[best_index[:id]][:durations].first if @same_point_day
      insert_point_in_route(@candidate_routes[vehicle_id][day], best_index)

      @to_plan_service_ids.delete(best_index[:id])

      unlocked_ids =
        if @services_unlocked_by[best_index[:id]] && !@services_unlocked_by[best_index[:id]].empty? && !@relaxed_same_point_day
          services_to_add = @services_unlocked_by[best_index[:id]] & @candidate_services_ids
          @to_plan_service_ids += services_to_add
          services_to_add.each{ |service_id| @unlocked[service_id] = nil }
          services_to_add
        end

      [best_index[:id], unlocked_ids.to_a]
    end

    def get_previous_info(route_data, position)
      previous_info = @services_data[route_data[:stops][position - 1][:id]] if position.positive?
      {
        id: position.zero? ? route_data[:start_point_id] : route_data[:stops][position - 1][:id],
        point_id: position.zero? ? route_data[:start_point_id] : route_data[:stops][position - 1][:point_id],
        setup_duration: position.zero? ? 0 : previous_info[:setup_durations][route_data[:stops][position - 1][:activity]],
        duration: position.zero? ? 0 : previous_info[:durations][route_data[:stops][position - 1][:activity]],
        tw: position.zero? ? [] : previous_info[:tws_sets][route_data[:stops][position - 1][:activity]],
        end: position.zero? ? route_data[:tw_start] : route_data[:stops][position - 1][:end]
      }
    end

    def best_cost_according_to_tws(route_data, service_id, service_data, previous, options)
      activity = options[:activity]
      duration = (@same_point_day && options[:first_visit]) ? service_data[:group_duration] : service_data[:durations][activity]
      potential_tws = find_timewindows(previous, { id: service_id, point_id: service_data[:points_ids][activity], setup_duration: service_data[:setup_durations][activity], duration: duration, tw: service_data[:tws_sets][activity] }, route_data)

      potential_tws.collect{ |tw|
        next_activity, tw_accepted, shift, back_depot = insertion_cost_with_tw(tw, route_data, { id: service_id, point_id: service_data[:points_ids][activity], duration: duration }, options[:position])
        service_info = { id: service_id, tw: service_data[:tws_sets][activity], duration: service_data[:durations][activity] }
        acceptable_shift_for_group = options[:first_visit] ? acceptable_for_group?(service_info, tw) : true

        next if !(tw_accepted && acceptable_shift_for_group)

        {
          id: service_id,
          vehicle: route_data[:vehicle_original_id],
          day: route_data[:day],
          point: service_data[:points_ids][activity],
          start: tw[:start_time],
          arrival: tw[:arrival_time],
          end: tw[:final_time],
          position: options[:position],
          considered_setup_duration: tw[:setup_duration],
          next_activity: next_activity,
          potential_shift: tw[:max_shift],
          additional_route_time:
            if route_data[:stops].empty?
              matrix(route_data, route_data[:start_point_id], service_data[:points_ids][activity]) +
                matrix(route_data, service_data[:points_ids][activity], route_data[:end_point_id])
            else
              [0, shift - duration - tw[:setup_duration]].max
            end,
          back_to_depot: back_depot,
          activity: activity,
        }
      }.compact.min_by{ |cost| cost[:back_to_depot] }
    end

    def compatible_days(service_id, day)
      !@services_data[service_id][:raw].unavailable_days.include?(day) &&
        !@services_assignment[service_id][:days].include?(day) &&
        day_in_possible_interval(service_id, day)
    end

    def compatible_vehicle(service_id, route_data)
      # WARNING : this does not consider vehicle alternative skills properly
      # we would need to know which skill_set is required in order that all services on same vehicle are compatible
      service_data = @services_data[service_id]
      point = @services_data[service_id][:points_ids].first
      (!@same_point_day && !@relaxed_same_point_day || @points_assignment[point][:vehicles].empty? ||
        @points_assignment[point][:vehicles].include?(route_data[:vehicle_original_id])) &&
        route_data[:skills].any?{ |skill_set| (service_data[:raw].skills - skill_set).empty? } &&
        (service_data[:sticky_vehicles_ids].empty? ||
          service_data[:sticky_vehicles_ids].include?(route_data[:vehicle_original_id]))
    end

    def service_does_not_violate_capacity(service_id, route_data, first_visit)
      needed_capacity = @services_data[service_id][:group_capacity] if first_visit && @same_point_day
      needed_capacity ||= @services_data[service_id][:capacity] # if no same point day or not its group representative
      needed_capacity.all?{ |need, quantity| quantity <= route_data[:capacity_left][need] }
    end

    def relaxed_or_same_point_day_constraint_respected(service_id, vehicle_id, day)
      return true unless @same_point_day || @relaxed_same_point_day

      # there can be only on point in points_ids because of these options :
      point = @services_data[service_id][:points_ids].first

      return true if @points_assignment[point][:vehicles].empty?

      if @relaxed_same_point_day
        @points_assignment[point][:vehicles].include?(vehicle_id) &&
          (@points_assignment[point][:days].include?(day) ||
          @points_assignment[point][:maximum_visits_number] < @services_data[service_id][:raw].visits_number)
      else # @same_point_day is on :
        !@unlocked.key?(service_id) ||
          @points_assignment[point][:vehicles].include?(vehicle_id) &&
            @points_assignment[point][:days].include?(day)
      end
    end

    def service_compatible_with_route(service_id, route_data, first_visit)
      vehicle_id = route_data[:vehicle_original_id]
      day = route_data[:day]

      compatible_days(service_id, day) &&
        compatible_vehicle(service_id, route_data) &&
        service_does_not_violate_capacity(service_id, route_data, first_visit) &&
        (!first_visit ||
          route_data[:available_ids].include?(service_id) &&
          relaxed_or_same_point_day_constraint_respected(service_id, vehicle_id, day) &&
          same_point_compatibility(service_id, day))
    end

    def find_best_index(service_id, route_data, first_visit = true)
      return nil unless service_compatible_with_route(service_id, route_data, first_visit)

      ### find the best position in [route_data] to insert [service] ###
      route = route_data[:stops]
      service_data = @services_data[service_id]

      (0..service_data[:nb_activities] - 1).collect{ |activity|
        positions_to_try = compute_consistent_positions_to_insert(@services_data[service_id][:positions_in_route][activity], @services_data[service_id][:points_ids], route)
        positions_to_try.collect{ |position|
          index_cost(route_data, service_id, position, activity, first_visit)
        }
      }.flatten.compact.min_by{ |cost| cost[:back_to_depot] }
    end

    def find_feasible_index(service_id, route_data, first_visit = true)
      return nil unless service_compatible_with_route(service_id, route_data, first_visit)

      ### find the best position in [route_data] to insert [service] ###
      route = route_data[:stops]
      service_data = @services_data[service_id]

      (0..service_data[:nb_activities] - 1).find{ |activity|
        positions_to_try = compute_consistent_positions_to_insert(@services_data[service_id][:positions_in_route][activity], @services_data[service_id][:points_ids], route)
        positions_to_try.find{ |position|
          index_cost(route_data, service_id, position, activity, first_visit)
        }
      }
    end

    def index_cost(route_data, service_id, position, activity, first_visit)
      ### compute cost of inserting service activity [activity] at [position] in [route_data]
      service_data = @services_data[service_id]
      route = route_data[:stops]
      previous = get_previous_info(route_data, position)
      current = service_data[:points_ids][activity]
      next_point = position == route_data[:stops].size ? route_data[:end_point_id] : route[position][:point_id]

      # TODO : this needs to be improved because when we insert a point at same location as start or end_point_id
      # we still might create a detour because we can insert at first and/or last position
      # we should not generate useless route time :
      return if position.between?(1, route.size - 2) && # not first neither last position
                matrix(route_data, previous[:point_id], next_point, :time).zero? &&
                matrix(route_data, previous[:point_id], @services_data[service_id][:points_ids][activity], :time) > 0

      return if position.positive? && position < route.size && # not first neither last position
                previous[:point_id] == next_point && previous[:point_id] != @services_data[service_id][:points_ids][activity] # there is no point in testing a position that will imply useless route time

      return if route_data[:maximum_ride_time] &&
                (position.positive? && matrix(route_data, previous[:point_id], current, :time) > route_data[:maximum_ride_time] ||
                position < route_data[:stops].size - 2 && matrix(route_data, current, next_point, :time) > route_data[:maximum_ride_time])

      return if route_data[:maximum_ride_distance] &&
                (position.positive? && matrix(route_data, previous[:point_id], current, :distance) > route_data[:maximum_ride_distance] ||
                position < route_data[:stops].size - 2 && matrix(route_data, current, next_point, :distance) > route_data[:maximum_ride_distance])

      best_cost_according_to_tws(route_data, service_id, service_data, previous,
                                 position: position, activity: activity, first_visit: first_visit)
    end

    def can_ignore_tw(previous_service_id, service_id)
      ### true if arriving on time at previous_service is enough to consider we are on time at service ###
      # when same point day is activated we can consider two points at same location are the same
      # when @duration_in_tw is disabled, only arrival time of first point at a given location matters in tw
      (@same_point_day || @relaxed_same_point_day) &&
        !@duration_in_tw &&
        @services_data.has_key?(previous_service_id) && # not coming from depot
        @services_data[previous_service_id][:points_ids].first == @services_data[service_id][:points_ids].first # same location as previous
        # reminder : services in (relaxed_)same_point_day relation have only one point_id
    end

    def find_timewindows(previous, inserted_service, route_data)
      ### find [inserted_service] timewindow which allows to insert it in [route_data] ###
      list = []
      route_time = matrix(route_data, previous[:point_id], inserted_service[:point_id])
      setup_duration = route_time.zero? ? 0 : inserted_service[:setup_duration]

      if inserted_service[:tw].empty?
        start = previous[:end]
        list << {
          start_time: start,
          arrival_time: start + route_time + setup_duration,
          final_time: start + route_time + setup_duration + inserted_service[:duration],
          end_tw: nil,
          max_shift: nil,
          setup_duration: setup_duration
        }
      else
        inserted_service[:tw].select{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:day] % 7 }.each{ |tw|
          start = [previous[:end], tw[:start] - route_time - setup_duration].max
          arrival = start + route_time + setup_duration
          final = arrival + inserted_service[:duration]

          next if tw[:end] && arrival > tw[:end] && (!@duration_in_tw || final <= tw[:end]) &&
                  !can_ignore_tw(previous[:id], inserted_service[:id])

          list << {
            start_time: start,
            arrival_time: arrival,
            final_time: final,
            end_tw: tw[:end],
            max_shift: tw[:end] ? tw[:end] - (start + route_time + setup_duration) : nil,
            setup_duration: setup_duration
          }
        }
      end

      list
    end

    def insert_point_in_route(route_data, point_to_add, first_visit = true)
      ### modify [route_data] such that [point_to_add] is in the route ###
      current_route = route_data[:stops]
      @candidate_services_ids.delete(point_to_add[:id])

      @services_assignment[point_to_add[:id]][:missing_visits] -= 1
      @services_assignment[point_to_add[:id]][:days] << point_to_add[:day]
      @services_assignment[point_to_add[:id]][:vehicles] |= [point_to_add[:vehicle]]
      @points_assignment[point_to_add[:point]][:vehicles] |= [route_data[:vehicle_original_id]]
      @points_assignment[point_to_add[:point]][:days] |= [route_data[:day]]
      @points_assignment[point_to_add[:point]][:maximum_visits_number] =
        [@points_assignment[point_to_add[:point]][:maximum_visits_number],
         @services_data[point_to_add[:id]][:raw].visits_number].max
      @points_assignment[point_to_add[:point]][:vehicles] |= [route_data[:vehicle_original_id]]
      @services_data[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }

      @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, r_d| r_d[:available_ids].delete(point_to_add[:id]) } } if first_visit

      current_route.insert(point_to_add[:position],
                           id: point_to_add[:id],
                           point_id: point_to_add[:point],
                           start: point_to_add[:start],
                           arrival: point_to_add[:arrival],
                           end: point_to_add[:end],
                           considered_setup_duration: point_to_add[:considered_setup_duration],
                           max_shift: point_to_add[:potential_shift],
                           activity: point_to_add[:activity],
                           requirement: @services_data[point_to_add[:id]][:positions_in_route][point_to_add[:activity]])

      add_same_freq_located_points(point_to_add, route_data) if @same_point_day && first_visit

      if point_to_add[:position] < current_route.size - 1
        current_route[point_to_add[:position] + 1][:activity] = point_to_add[:next_activity]
        current_route[point_to_add[:position] + 1][:point_id] = @services_data[current_route[point_to_add[:position] + 1][:id]][:points_ids][point_to_add[:next_activity]]

        update_route(route_data, point_to_add[:position] + 1)
      end
    end

    def matrix(route_data, start, arrival, dimension = :time)
      ### return [dimension] between [start] and [arrival] ###
      if start.nil? || arrival.nil?
        0
      else
        start = @indices[start] if start.is_a?(String)
        arrival = @indices[arrival] if arrival.is_a?(String)

        return nil unless @matrices.find{ |matrix| matrix[:id] == route_data[:matrix_id] }[dimension]

        @matrices.find{ |matrix| matrix[:id] == route_data[:matrix_id] }[dimension][start][arrival]
      end
    end

    def get_stop(day, type, vehicle, data = {})
      size_weeks = (@schedule_end.to_f / 7).ceil.to_s.size
      week = Helper.string_padding(day / 7 + 1, size_weeks)
      times = Models::Solution::Stop::Info.new(begin_time: data[:arrival],
                                               day_week_num: "#{day % 7}_#{week}",
                                               day_week: "#{OptimizerWrapper::WEEKDAYS[day % 7]}_#{week}")

      case type
      when 'start'
        Models::Solution::Stop.new(vehicle.start_point, info: times)
      when 'end'
        Models::Solution::Stop.new(vehicle.end_point, info: times)
      when 'service'
        service = @services_data[data[:id]][:raw] if type == 'service'
        loads = service.quantities.map{ |quantity|
          Models::Solution::Load.new(quantity: Models::Quantity.new(unit: quantity.unit))
        }
        number_in_sequence =
          @services_assignment[data[:id]][:assigned_indices][@services_assignment[data[:id]][:days].find_index(day)]
        Models::Solution::Stop.new(
          service,
          service_id: "#{data[:id]}_#{number_in_sequence}_#{service.visits_number}",
          visit_index: number_in_sequence,
          info: times,
          index: data[:activity],
          loads: loads
        )
      end
    end

    def get_route_data(route_data)
      route_start = route_data[:stops].empty? ? route_data[:tw_start] : route_data[:stops].first[:start]

      route_end, final_travel_time, final_travel_distance =
        if route_data[:stops].empty?
          if route_data[:end_point_id] && route_data[:start_point_id]
            time_btw_stops = matrix(route_data, route_data[:start_point_id], route_data[:end_point_id])
            distance_btw_stops = matrix(route_data, route_data[:start_point_id], route_data[:end_point_id], :distance)
            [route_start + time_btw_stops, time_btw_stops, distance_btw_stops]
          else
            [route_start, 0, 0]
          end
        elsif route_data[:end_point_id]
          time_to_end = matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])
          [route_data[:stops].last[:end] + time_to_end,
           time_to_end,
           matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id], :distance)]
        else
          [route_data[:stops].last[:end], nil, nil]
        end

      [route_start, route_end, final_travel_time, final_travel_distance]
    end

    def get_activities(day, route_data, vehicle)
      computed_stops = []
      route_start, route_end, _final_travel_time, _final_travel_distance = get_route_data(route_data)

      computed_stops << get_stop(day, 'start', vehicle, arrival: route_start) if route_data[:start_point_id]
      computed_stops += route_data[:stops].map{ |stop| get_stop(day, 'service', vehicle, stop) }
      computed_stops << get_stop(day, 'end', vehicle, arrival: route_end) if route_data[:end_point_id]

      [computed_stops, route_start, route_end]
    end

    # At the end of algorithm, deduces which visit number is assigned
    # and which is not. For now, we assume all first visits are assigned.
    # TODO : This could be improved by detecting if there is one intermediate visit missing vis-à-vis maximum_lapse
    # (see test_compute_visits_number).
    # This is hard because we may overpass maximum_lapse (in days) without overpassing
    # maximum_lapse (in open days).
    def compute_visits_number
      @services_assignment.each{ |id, data|
        data[:days].sort! # this ensures assigned_indices order will correspond to days order
        assigned_indices = (1..@services_assignment[id][:days].size).to_a
        unassigned_indices = []
        current_visit_index = @services_assignment[id][:days].size + 1
        until assigned_indices.size + unassigned_indices.size == @services_data[id][:raw].visits_number
          unassigned_indices << current_visit_index
          current_visit_index += 1
        end

        @services_assignment[id][:assigned_indices] = assigned_indices
        @services_assignment[id][:unassigned_indices] = unassigned_indices
      }

      check_consistent_generated_ids
    end

    def prepare_output_and_collect_routes(vrp)
      vrp_routes = []
      solution_routes = []

      compute_visits_number

      @candidate_routes.each{ |original_vehicle_id, all_routes|
        all_routes.sort_by{ |day, _route_data| day }.each{ |day, route_data|
          vrp_vehicle = vrp.vehicles.find{ |v|
            v.original_id == original_vehicle_id && v.global_day_index == day &&
              # in case two vehicles have same global_day_index :
              v.timewindow.start % 86400 == route_data[:tw_start] && v.timewindow.end % 86400 == route_data[:tw_end]
          }
          computed_stops, _start_time, _end_time = get_activities(day, route_data, vrp_vehicle)

          vrp_routes << {
            vehicle_id: vrp_vehicle.id,
            mission_ids: computed_stops.collect{ |stop| stop[:service_id] }.compact
          }

          solution_routes << Models::Solution::Route.new(stops: computed_stops,
                                                         vehicle: vrp_vehicle)
        }
      }
      unassigned = collect_unassigned
      # TODO: fulfill cost_details with solution_routes costs
      solution = Models::Solution.new(cost: @cost,
                                      solvers: [:heuristic],
                                      routes: solution_routes,
                                      unassigned: unassigned,
                                      elapsed: (Time.now - @starting_time) * 1000) # ms
      solution.parse(vrp)
      vrp.configuration.preprocessing.heuristic_result = solution
      vrp_routes
    end

    def select_point(insertion_costs, empty_route)
      ### chose the most interesting point to insert according to [insertion_costs] ###
      if empty_route
        if @candidate_routes.all?{ |_vehicle_id, all_routes| all_routes.all?{ |_day, route_data| route_data[:stops].empty? } }
          # chose closest with highest frequency
          to_consider_set = insertion_costs.group_by{ |s| @services_data[s[:id]][:raw].visits_number }.max_by{ |nb, _set| nb }[1]
          return to_consider_set.min_by{ |s| ((@services_data[s[:id]][:priority].to_f + 1) / @max_priority) * s[:additional_route_time] }
        else
          # chose distant service with highest frequency
          # max_priority + 1 so that priority never equal to max_priority and no multiplication by 0
          referents = @candidate_routes.collect{ |_vehicle_id, all_routes| all_routes.collect{ |_day, route_data| find_referent(route_data) } }.flatten.compact
          return insertion_costs.max_by{ |s| (1 - (@services_data[s[:id]][:priority].to_f + 1) / @max_priority + 1) * distance_from_set(referents, s).min * @services_data[s[:id]][:raw].visits_number**2 }
        end
      end

      costs = insertion_costs.collect{ |s| s[:additional_route_time] }
      if costs.min != 0
        insertion_costs.min_by{ |s| ((@services_data[s[:id]][:priority].to_f + 1) / @max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:raw].visits_number**2) }
      else
        freq = insertion_costs.collect{ |s| @services_data[s[:id]][:raw].visits_number }
        zero_idx = (0..(costs.size - 1)).select{ |i| costs[i].zero? }
        potential = zero_idx.select{ |i| freq[i] == freq.max }
        if !potential.empty?
          # the one with biggest duration will be the hardest to plan
          insertion_costs[potential.max_by{ |p| @services_data[insertion_costs[p][:id]][:durations][insertion_costs[p][:activity]] }]
        else
          # TODO : more tests to improve.
          # we can consider having a limit such that if additional route is > limit then we keep service with additional_route = 0 (and freq max among those)
          insertion_costs.reject{ |s| s[:additional_route_time].zero? }.min_by{ |s| ((@services_data[s[:id]][:priority].to_f + 1) / @max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:raw].visits_number**2) }
        end
      end
    end

    def try_to_insert_at(vehicle_id, day, service_id)
      # when adjusting routes, tries to insert [service_id] at [day] for [vehicle]
      return if @candidate_routes[vehicle_id][day].nil? ||
                @candidate_routes[vehicle_id][day][:completed]

      best_index = find_best_index(service_id, @candidate_routes[vehicle_id][day], false)
      return unless best_index

      insert_point_in_route(@candidate_routes[vehicle_id][day], best_index, false)
      day
    end

    def find_corresponding_timewindow(day, arrival_time, timewindows, duration)
      timewindows.select{ |tw|
        (tw[:day_index].nil? || tw[:day_index] == day % 7) &&
          (tw[:end].nil? || arrival_time <= tw[:end]) &&
          (!@duration_in_tw || [tw[:start], arrival_time].max + duration <= tw[:end])
      }.min_by{ |tw| tw[:start] }
    end

    def find_referent(route_data)
      if route_data[:stops].empty?
        nil
      else
        route_data[:stops].max_by{ |stop|
          matrix(route_data, route_data[:start_point_id], stop[:point_id]) +
            matrix(route_data, stop[:point_id], route_data[:end_point_id])
        }[:point_id]
      end
    end

    def distance_from_set(set, current)
      set.collect{ |point_id|
        matrix(@candidate_routes[@candidate_routes.keys.first].first[1], point_id, current[:point])
      }
    end

    def construct_sub_vrp(vrp, vehicle, current_route)
      # TODO : make private

      # TODO : check initial vrp is not modified.
      # Now it is ok because marshall dump, but do not use mashall dump
      route_vrp = Marshal.load(Marshal.dump(vrp))

      service_hash = current_route.map{ |service| [service[:id], service] }.to_h
      route_vrp.services.select!{ |service| service_hash.key?(service[:id]) }
      route_vrp.services.each{ |service|
        next if service.activity

        service.activity = service.activities[service_hash[service.id][:activity]]
        service.activities = nil
      }
      route_vrp.vehicles = [vehicle]

      # configuration
      route_vrp.configuration.schedule.range_indices = nil
      route_vrp.configuration.schedule.start_date = nil

      route_vrp.configuration.resolution.minimum_duration = 100
      route_vrp.configuration.resolution.time_out_multiplier = 5
      route_vrp.configuration.resolution.solver = true
      route_vrp.configuration.restitution.intermediate_solutions = false

      route_vrp.configuration.preprocessing.first_solution_strategy = nil
      # NOT READY YET :
      # route_vrp.configuration.preprocessing.cluster_threshold = 0
      # route_vrp.configuration.preprocessing.force_cluster = true
      route_vrp.configuration.preprocessing.partitions = []
      route_vrp.configuration.restitution.csv = false

      # TODO : write conf by hand to avoid mistakes
      # will need load ? use route_vrp[:configuration] ... or route_vrp.configuration.preprocessing.first_sol

      route_vrp
    end

    def collect_generated_routes(vehicle, services)
      [{
        vehicle: vehicle,
        mission_ids: services.collect{ |service| service[:id] }
      }]
    end

    def save_status
      @previous_candidate_routes = Marshal.load(Marshal.dump(@candidate_routes))
      @previous_services_assignment = Marshal.load(Marshal.dump(@services_assignment))
      @previous_points_assignment = Marshal.load(Marshal.dump(@points_assignment))
      @previous_candidate_service_ids = Marshal.load(Marshal.dump(@candidate_services_ids))
    end

    def restore
      @candidate_routes = @previous_candidate_routes
      @services_assignment = @previous_services_assignment
      @points_assignment = @previous_points_assignment
      @candidate_services_ids = @previous_candidate_service_ids
    end

    def reject_all_visits(service_id, visits_number, specified_reason)
      @services_assignment[service_id][:missing_visits] = visits_number
      @services_assignment[service_id][:unassigned_reasons] = [specified_reason]
      @candidate_services_ids.delete(service_id)
      @to_plan_service_ids.delete(service_id)
    end
  end
end
