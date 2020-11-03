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
require './lib/tsp_helper.rb'
require './lib/output_helper.rb'
require './lib/heuristics/concerns/scheduling_data_initialisation'
require './lib/heuristics/concerns/scheduling_end_phase'

module Heuristics
  class Scheduling
    include SchedulingDataInitialization
    include SchedulingEndPhase

    def initialize(vrp, job = nil)
      return if vrp.services.empty?

      # global data
      @schedule_end = vrp.schedule_range_indices[:end]
      @allow_partial_assignment = vrp.resolution_allow_partial_assignment
      @same_point_day = vrp.resolution_same_point_day
      @relaxed_same_point_day = false
      @duration_in_tw = false # TODO: create parameter for this
      @end_phase = false
      @spread_among_days = !vrp.resolution_minimize_days_worked

      # heuristic data
      @services_data = {}
      @candidate_services_ids = []
      @to_plan_service_ids = []
      @used_to_adjust = []

      @candidate_routes = {}
      @points_vehicles_and_days = {}
      vrp.vehicles.group_by{ |vehicle| vehicle.id.split('_')[0..-2].join('_') }.each{ |vehicle_id, _set|
        @candidate_routes[vehicle_id] = {}
      }

      @indices = {}
      @matrices = vrp[:matrices]

      # same_point_day : service with higher heuristic_period unlocks others
      @services_unlocked_by = {}
      @unlocked = []
      @same_located = {}
      @freq_max_at_point = Hash.new(0)

      @uninserted = {}
      @missing_visits = {}

      @output_tool = OptimizerWrapper.config[:debug][:output_schedule] ? OutputHelper::Scheduling.new(vrp.name, @candidate_vehicles, job, @schedule_end) : nil

      collect_services_data(vrp)
      @max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
      collect_indices(vrp)
      generate_route_structure(vrp)
      compute_latest_authorized
      @cost = 0

      # secondary data
      @previous_candidate_service_ids = nil
      @previous_uninserted = nil
      @previous_candidate_routes = nil
    end

    def compute_initial_solution(vrp, &block)
      if vrp.services.empty?
        # TODO : create and use result structure instead of using wrapper function
        vrp[:preprocessing_heuristic_result] = Wrappers::Wrapper.new.empty_result('heuristic', vrp)
        return []
      end

      block&.call(nil, nil, nil, 'scheduling heuristic - start solving', nil, nil, nil)
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
      if vrp.resolution_solver && !@candidate_services_ids.empty?
        block&.call(nil, nil, nil, 'scheduling heuristic - re-ordering routes', nil, nil, nil)
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

      block&.call(nil, nil, nil, 'scheduling heuristic - preparing result', nil, nil, nil)
      routes = prepare_output_and_collect_routes(vrp)
      routes
    end

    def compute_consistent_positions_to_insert(position_requirement, service_points_ids, route)
      first_index = 0
      last_index = route.size

      first_unforced_first = (0..route.size).find{ |position| route[position].nil? || (route[position][:requirement] != :always_first && route[position][:requirement] != :never_middle) }
      first_forced_last = (0..route.size).find{ |position| route[position].nil? || route[position][:requirement] == :always_last || position > first_unforced_first && route[position][:requirement] == :never_middle }

      positions_to_try = if position_requirement == :always_first
        (first_index..first_unforced_first).to_a
      elsif position_requirement == :always_middle
        full = (first_unforced_first..first_forced_last).to_a
        cleaned = full - (0..first_unforced_first - 1).to_a - (first_forced_last + 1..last_index).to_a
        cleaned.delete(0)           # can not be the very first
        cleaned.delete(route.size)  # can not be the very last
        cleaned
      elsif position_requirement == :always_last
        (first_forced_last..last_index).to_a
      elsif position_requirement == :never_first
        route.empty? ? [] : ([1, first_unforced_first].max..first_forced_last).to_a
      elsif position_requirement == :never_middle
        ((first_index..first_unforced_first).to_a + (first_forced_last..last_index).to_a).uniq
      elsif position_requirement == :never_last
        route.empty? || [route.size - 1, first_forced_last].min < first_unforced_first ? [] : (first_unforced_first..[(route.size - 1), first_forced_last].min).to_a
      else # position_requirement == :neutral
        (first_unforced_first..first_forced_last).to_a
      end

      if service_points_ids.size == 1 && positions_to_try.find{ |position| route[position] && route[position][:point_id] == service_points_ids.first }
        same_location_position = positions_to_try.select{ |position| route[position] && route[position][:point_id] == service_points_ids.first }
        positions_to_try.delete_if{ |position|
          !same_location_position.include?(position) &&
            !same_location_position.include?(position - 1)
        }
      end

      positions_to_try
    end

    def check_solution_validity
      @candidate_routes.each{ |_vehicle_id, all_routes|
        all_routes.each{ |_day, route_data|
          next if route_data[:stops].empty?

          time_back_to_depot = route_data[:stops].last[:end] + matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is starting too soon' if route_data[:stops][0][:start] < route_data[:tw_start]
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is ending too late' if time_back_to_depot > route_data[:tw_end]
        }
      }

      @candidate_routes.each{ |_vehicle_id, all_routes|
        all_routes.each{ |day, route_data|
          route_data[:stops].each_with_index{ |s, i|
            next if @services_data[s[:id]][:tws_sets].flatten.empty? || i.positive? && can_ignore_tw(route_data[:stops][i - 1][:id], s[:id])

            compatible_tw = find_corresponding_timewindow(day, s[:arrival], @services_data[s[:id]][:tws_sets][s[:activity]], s[:end] - s[:arrival])
            next if compatible_tw &&
                    s[:arrival].round.between?(compatible_tw[:start], compatible_tw[:end]) &&
                    (!@duration_in_tw || s[:end] <= compatible_tw[:end])

            raise OptimizerWrapper::SchedulingHeuristicError, 'One service timewindows violated'
          }
        }
      }
    end

    private

    def plan_next_visits(vehicle_id, service_id, first_unseen_visit)
      return if @services_data[service_id][:raw].visits_number == 1

      days_available = @candidate_routes[vehicle_id].keys
      next_day = @services_data[service_id][:used_days].max + @services_data[service_id][:heuristic_period]
      day_to_insert = days_available.select{ |day| day >= next_day.round }.min
      impacted_days = []
      if day_to_insert
        diff = day_to_insert - next_day.round
        next_day += diff
      end

      cleaned_service = false
      need_to_add_visits = false
      (first_unseen_visit..@services_data[service_id][:raw].visits_number).each{ |visit_number|
        inserted_day = nil
        while inserted_day.nil? && day_to_insert && day_to_insert <= @schedule_end && !cleaned_service
          inserted_day = try_to_insert_at(vehicle_id, day_to_insert, service_id, visit_number) if days_available.include?(day_to_insert)
          impacted_days |= [inserted_day]

          next_day += @services_data[service_id][:heuristic_period]
          day_to_insert = days_available.select{ |day| day >= next_day.round }.min

          next if day_to_insert.nil?

          diff = day_to_insert - next_day.round
          next_day += diff
        end

        next if inserted_day

        if !@allow_partial_assignment
          clean_stops(service_id, vehicle_id)
          cleaned_service = true
          impacted_days = []
        else
          need_to_add_visits = true # only if allow_partial_assignment, do not add_missing_visits otherwise
          @uninserted["#{service_id}_#{visit_number}_#{@services_data[service_id][:raw].visits_number}"] = {
            original_service: service_id,
            reason: "Visit not assignable by heuristic, first visit assigned at day #{@services_data[service_id][:used_days].min}"
          }
        end
      }

      @missing_visits[vehicle_id] << service_id if need_to_add_visits

      impacted_days.compact
    end

    def adjust_candidate_routes(vehicle_id, day_finished)
      ### assigns all visits of services in [services] that where newly scheduled on [vehicle_id] at [day_finished] ###
      @candidate_routes[vehicle_id][day_finished][:stops].sort_by{ |stop| @services_data[stop[:id]][:priority] }.flat_map{ |stop|
        next if @used_to_adjust.include?(stop[:id])

        @used_to_adjust << stop[:id]
        @output_tool&.insert_visits(@services_data[stop[:id]][:used_days], stop[:id], @services_data[stop[:id]][:raw].visits_number)

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
          tw = find_corresponding_timewindow(route_data[:global_day_index], previous_end + route_time + stop[:considered_setup_duration], @services_data[stop[:id]][:tws_sets][stop[:activity]], stop[:end] - stop[:arrival])
          raise OptimizerWrapper::SchedulingHeuristicError, 'No timewindow found to update route' if !@services_data[stop[:id]][:tws_sets][stop[:activity]].empty? && tw.nil?

          stop[:start] = tw ? [tw[:start] - route_time - stop[:considered_setup_duration], previous_end].max : previous_end
          stop[:arrival] = stop[:start] + route_time + stop[:considered_setup_duration]
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:durations][stop[:activity]]
          stop[:max_shift] = tw ? tw[:end] - stop[:arrival] : nil
        end

        previous_id = stop[:id]
        previous_point_id = stop[:point_id]
        previous_end = stop[:end]
      }

      raise OptimizerWrapper::SchedulingHeuristicError, 'Vehicle end violated after updating route' if route.size.positive? &&
                                                                                                       route.last[:end] + matrix(route_data, route.last[:point_id], route_data[:end_point_id]) > route_data[:tw_end]

      route
    end

    def collect_unassigned
      unassigned = []

      @candidate_services_ids.each{ |id|
        service_in_vrp = @services_data[id][:raw]
        (1..service_in_vrp.visits_number).each{ |index|
          unassigned << get_unassigned_info("#{id}_#{index}_#{service_in_vrp.visits_number}", service_in_vrp, 'Heuristic could not affect this service before all vehicles are full')
        }
      }

      @uninserted.each_key{ |service|
        id = @uninserted[service][:original_service]
        service_in_vrp = @services_data[id][:raw]
        unassigned << get_unassigned_info(service, service_in_vrp, @uninserted[service][:reason])
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
          route_vrp.services = provide_group_tws(route_vrp.services, day) if @same_point_day || @relaxed_same_point_day # to have same data in ORtools and scheduling. Customers should ensure all timewindows are the same for same points

          result = OptimizerWrapper.solve(service: :ortools, vrp: route_vrp)

          next if result.nil? || !result[:unassigned].empty?

          time_back_to_depot = route_data[:stops].last[:end] + matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id])
          scheduling_route_time = time_back_to_depot - route_data[:stops].first[:start]
          solver_route_time = (result[:routes].first[:activities].last[:begin_time] - result[:routes].first[:activities].first[:begin_time]) # last activity is vehicle depot

          next if scheduling_route_time - solver_route_time < @candidate_services_ids.flat_map{ |s| @services_data[s][:durations] }.min ||
                  result[:routes].first[:activities].collect{ |stop| @indices[stop[:service_id]] }.compact == route_data[:stops].collect{ |s| @indices[s[:id]] } # we did not change our points order

          begin
            route_data[:stops] = compute_route_from(route_data, result[:routes].first[:activities]) # this will change @candidate_routes, but it should not be a problem since OR-tools returns a valid solution
          rescue OptimizerWrapper::SchedulingHeuristicError
            log 'Failing to construct route from OR-tools solution'
          end
        }
      }
    end

    def clean_position_dependent_services(vehicle_id, stops, removed_index)
      if removed_index == stops.size
        index = removed_index - 1
        while stops[index] && [:never_last, :always_middle].include?(stops[index][:requirement])
          clean_stops(stops[index][:id], vehicle_id, true)
          # index removed so no need to increment index
        end
      end

      index = removed_index
      while stops[index] && [:never_first, :always_middle].include?(stops[index][:requirement])
        clean_stops(stops[index][:id], vehicle_id, true)
        # index removed so no need to increment index
      end
    end

    def clean_stops(service_id, vehicle_id, reaffect = false)
      ### when allow_partial_assignment is false, removes all affected visits of [service_id] because we can not affect all visits ###
      @candidate_routes[vehicle_id].collect{ |day, route_data|
        remove_index = route_data[:stops].find_index{ |stop| stop[:id] == service_id }
        next unless remove_index

        used_point = route_data[:stops][remove_index][:point_id]
        route_data[:stops].slice!(remove_index)
        @services_data[service_id][:capacity].each{ |need, qty| route_data[:capacity_left][need] += qty }

        update_point_vehicle_and_days(used_point)
        clean_position_dependent_services(vehicle_id, route_data[:stops], remove_index) unless route_data[:stops].empty?
        route_data[:stops] = update_route(route_data, remove_index)
        @services_data[service_id][:used_days] = []
        @services_data[service_id][:used_vehicles] = []
      }.compact.size

      if reaffect
        @candidate_services_ids << service_id
        @candidate_routes.each{ |_vehicle_id, all_routes|
          all_routes.each{ |day, route_data|
            next unless day <= @services_data[service_id][:raw].last_possible_days.first # first is for first visit

            route_data[:available_ids] |= service_id
          }
        }
        @uninserted.each{ |id, info|
          @uninserted.delete(id) if info[:original_service] == service_id
        }
      else
        (1..@services_data[service_id][:raw].visits_number).each{ |number_in_sequence|
          @uninserted["#{service_id}_#{number_in_sequence}_#{@services_data[service_id][:raw].visits_number}"] = {
            original_service: service_id,
            reason: 'Partial assignment only'
          }
        }
      end

      return if reaffect

      # unaffected all points at this location
      points_at_same_location = @candidate_services_ids.select{ |id| @services_data[id][:points_ids] == @services_data[service_id][:points_ids] }
      points_at_same_location.each{ |id|
        (1..@services_data[id][:raw].visits_number).each{ |visit|
          @uninserted["#{id}_#{visit}_#{@services_data[id][:raw].visits_number}"] = {
            original_service: id,
            reason: 'Partial assignment only'
          }
        }
        @candidate_services_ids.delete(id)
        @to_plan_service_ids.delete(id)
      }
    end

    def update_point_vehicle_and_days(point)
      @points_vehicles_and_days[point][:vehicles].delete_if{ |vehicle_id|
        @candidate_routes[vehicle_id].none?{ |_day, route_data| route_data[:stops].any?{ |stop| stop[:point_id] == point } }
      }

      @points_vehicles_and_days[point][:days].delete_if{ |day|
        @points_vehicles_and_days[point][:vehicles].none?{ |vehicle_id|
          @candidate_routes[vehicle_id][day][:stops].find{ |stop| stop[:point_id] == point }
        }
      }
    end

    def compute_route_from(new_route, solver_route)
      solver_order = solver_route.collect{ |s| s[:service_id] }.compact
      new_route[:stops].sort_by!{ |stop| solver_order.find_index(stop[:id]) }.collect{ |s| s[:id] }
      update_route(new_route, 0, solver_route.first[:begin_time])
    end

    def compute_costs_for_route(route_data, set = nil)
      vehicle_id = route_data[:vehicle_id].split('_')[0..-2].join('_')
      day = route_data[:vehicle_id].split('_').last.to_i

      ### compute the cost, for each remaining service to assign, of assigning it to [route_data] ###
      insertion_costs = []
      set ||= @same_point_day ? @to_plan_service_ids.reject{ |id| @services_data[id][:raw].visits_number == 1 } : @to_plan_service_ids
      # we will assign services with one vehicle in relaxed_same_point_day part
      set.select{ |service_id|
        # quantities are respected
        ((@same_point_day && @services_data[service_id][:group_capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] }) ||
          (!@same_point_day && @services_data[service_id][:capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] })) &&
          # service is available at this day
          !@services_data[service_id][:raw].unavailable_visit_day_indices.include?(day) &&
          (@services_data[service_id][:sticky_vehicles_ids].empty? || @services_data[service_id][:sticky_vehicles_ids].include?(vehicle_id))
      }.each{ |service_id|
        next if @services_data[service_id][:used_days] && !days_respecting_lapse(service_id, vehicle_id).include?(day)

        point = @services_data[service_id][:points_ids].first if @same_point_day || @relaxed_same_point_day # there can be only on point in points_ids
        next if @relaxed_same_point_day &&
                !@points_vehicles_and_days[point][:vehicles].empty? &&
                (!@points_vehicles_and_days[point][:vehicles].include?(vehicle_id) || !(@points_vehicles_and_days[point][:maximum_visits_number] < @services_data[service_id][:raw].visits_number || @points_vehicles_and_days[point][:days].include?(day)))

        next if @same_point_day && @unlocked.include?(service_id) && (!@points_vehicles_and_days[point][:vehicles].include?(vehicle_id) || !@points_vehicles_and_days[point][:days].include?(day))

        period = @services_data[service_id][:heuristic_period]

        next if !(period.nil? ||
                route_data[:available_ids].include?(service_id) && (day + period..@schedule_end).step(period).find{ |current_day| @candidate_routes[vehicle_id][current_day.floor] && @candidate_routes[vehicle_id][current_day.floor][:completed] || @candidate_routes[vehicle_id][current_day.ceil] && @candidate_routes[vehicle_id][current_day.ceil][:completed] }.nil? &&
                same_point_compatibility(service_id, vehicle_id, day))

        next if two_visits_and_can_not_assign_second(vehicle_id, day, service_id)

        other_indices = find_best_index(service_id, route_data)
        insertion_costs << other_indices if other_indices
      }

      insertion_costs.compact
    end

    def two_visits_and_can_not_assign_second(vehicle_id, day, service_id)
      return false unless @services_data[service_id][:raw].visits_number == 2 # || @end_phase ?

      next_day = day + @services_data[service_id][:heuristic_period]
      day_to_insert = @candidate_routes[vehicle_id].keys.select{ |potential_day| potential_day >= next_day.round }.min

      !(day_to_insert && find_best_index(service_id, @candidate_routes[vehicle_id][day_to_insert], false))
    end

    def same_point_compatibility(service_id, vehicle_id, day)
      # reminder : services in (relaxed_)same_point_day relation have only one point_id
      same_point_compatible_day = true

      return same_point_compatible_day if @services_data[service_id][:heuristic_period].nil?

      last_visit_day = day + (@services_data[service_id][:raw].visits_number - 1) * @services_data[service_id][:heuristic_period]
      if @relaxed_same_point_day
        # we know only one activity/point_id because @same_point_day was activated
        involved_days = (day..last_visit_day).step(@services_data[service_id][:heuristic_period]).collect{ |d| d }
        already_involved = @candidate_routes[vehicle_id].select{ |_d, r| r[:stops].any?{ |s| s[:point_id] == @services_data[service_id][:points_ids].first } }.collect{ |d, _r| d }
        if !already_involved.empty? &&
           @services_data[service_id][:raw].visits_number > @freq_max_at_point[@services_data[service_id][:points_ids].first] &&
           (involved_days & already_involved).size < @freq_max_at_point[@services_data[service_id][:points_ids].first]
          same_point_compatible_day = false
        elsif !already_involved.empty? && (involved_days & already_involved).size < involved_days.size
          same_point_compatible_day = false
        end
      elsif @unlocked.include?(service_id)
        # can not finish later (over whole period) than service at same_point
        stop = @candidate_routes[vehicle_id][day][:stops].select{ |s| s[:point_id] == @services_data[service_id][:points_ids].first }.max_by{ |s| @services_data[s[:id]][:raw].visits_number }
        stop_last_visit_day = day + (@services_data[stop[:id]][:raw].visits_number - stop[:number_in_sequence]) * @services_data[stop[:id]][:heuristic_period]
        same_point_compatible_day = last_visit_day <= stop_last_visit_day if same_point_compatible_day
      end

      same_point_compatible_day
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
          next_end = compute_tw_for_next(inserted_final_time, next_service, time_to_next, route_data[:global_day_index])
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
        sooner_start = tw[:start] - dist_from_inserted - setup_duration if tw && tw[:start]
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

      shift, activity, time_back_to_depot, tw_accepted = (0..nb_activities_index).collect{ |activity|
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
        time_back_to_depot = if position == route_data[:stops].size
          timewindow[:final_time] + matrix(route_data, service[:point_id], route_data[:end_point_id])
        else
          route_data[:stops].last[:end] + matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id]) + computed_shift
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

      [activity, tw_accepted, shift, time_back_to_depot]
    end

    def ensure_routes_will_not_be_rejected(vehicle_id, impacted_days)
      while impacted_days.size.positive?
        started_day = impacted_days.first
        can_not_insert_more = false
        while @candidate_routes[vehicle_id][started_day][:stops].map{ |stop| @services_data[stop[:id]][:raw].exclusion_cost || 0 }.reduce(&:+) < @candidate_routes[vehicle_id][started_day][:cost_fixed] || can_not_insert_more
          inserted_id, _unlocked_ids = try_to_add_new_point(vehicle_id, started_day)
          impacted_days |= adjust_candidate_routes(vehicle_id, started_day)
          can_not_insert_more = true unless inserted_id
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
        @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, r_d| r_d[:available_ids].delete(service_id) } }
        @services_data[service_id][:used_days] << route_data[:global_day_index]
        route_data[:stops].insert(best_index[:position] + i + 1,
                                          id: service_id,
                                          point_id: best_index[:point],
                                          start: start,
                                          arrival: start,
                                          end: start + @services_data[service_id][:durations].first,
                                          considered_setup_duration: 0,
                                          max_shift: max_shift ? max_shift - additional_durations : nil,
                                          number_in_sequence: 1,
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

      unlocked_ids = if @services_unlocked_by[best_index[:id]] && !@services_unlocked_by[best_index[:id]].empty? && !@relaxed_same_point_day
        services_to_add = @services_unlocked_by[best_index[:id]] - @uninserted.collect{ |_un, data| data[:original_service] }
        @to_plan_service_ids += services_to_add
        @unlocked += services_to_add

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
      duration = (@same_point_day && options[:first_visit] && !@end_phase) ? service_data[:group_duration] : service_data[:durations][activity]
      potential_tws = find_timewindows(previous, { id: service_id, point_id: service_data[:points_ids][activity], setup_duration: service_data[:setup_durations][activity], duration: duration, tw: service_data[:tws_sets][activity] }, route_data)

      potential_tws.collect{ |tw|
        next_activity, tw_accepted, shift, back_depot = insertion_cost_with_tw(tw, route_data, { id: service_id, point_id: service_data[:points_ids][activity], duration: duration }, options[:position])
        service_info = { id: service_id, tw: service_data[:tws_sets][activity], duration: service_data[:durations][activity] }
        acceptable_shift_for_group = options[:first_visit] ? acceptable_for_group?(service_info, tw) : true

        next if !(tw_accepted && acceptable_shift_for_group)

        {
          id: service_id,
          vehicle: route_data[:vehicle_id].split('_')[0..-2].join('_'),
          day: route_data[:global_day_index],
          point: service_data[:points_ids][activity],
          start: tw[:start_time],
          arrival: tw[:arrival_time],
          end: tw[:final_time],
          position: options[:position],
          considered_setup_duration: tw[:setup_duration],
          next_activity: next_activity,
          potential_shift: tw[:max_shift],
          additional_route_time: if route_data[:stops].empty?
            matrix(route_data, route_data[:start_point_id], service_data[:points_ids][activity]) + matrix(route_data, service_data[:points_ids][activity], route_data[:end_point_id])
          else
            [0, shift - duration - tw[:setup_duration]].max
          end,
          back_to_depot: back_depot,
          activity: activity,
        }
      }.compact.min_by{ |cost| cost[:back_to_depot] }
    end

    def find_best_index(service_id, route_data, first_visit = true)
      ### find the best position in [route_data] to insert [service] ###
      route = route_data[:stops]
      service_data = @services_data[service_id]

      (0..service_data[:nb_activities] - 1).collect{ |activity|
        positions_to_try = compute_consistent_positions_to_insert(@services_data[service_id][:positions_in_route][activity], @services_data[service_id][:points_ids], route)
        positions_to_try.collect{ |position|
          ### compute cost of inserting service activity [activity] at [position] in [route_data]
          previous = get_previous_info(route_data, position)

          next_point = (position == route_data[:stops].size) ? route_data[:end_point_id] : route[position][:point_id]
          next if position.positive? && position < route.size && # not first neither last position
                  previous[:point_id] == next_point && previous[:point_id] != @services_data[service_id][:points_ids][activity] # there is no point in testing a position that will imply useless route time

          next if route_data[:maximum_ride_time] &&
                  (position.positive? && matrix(route_data, previous[:point_id], service_data[:points_ids][activity], :time) > route_data[:maximum_ride_time] ||
                  position < route_data[:stops].size && matrix(route_data, service_data[:points_ids][activity], route[position][:point_id], :time) > route_data[:maximum_ride_time])

          next if route_data[:maximum_ride_distance] &&
                  (position.positive? && matrix(route_data, previous[:point_id], service_data[:points_ids][activity], :distance) > route_data[:maximum_ride_distance] ||
                  position < route_data[:stops].size && matrix(route_data, service_data[:points_ids][activity], route[position][:point_id], :distance) > route_data[:maximum_ride_distance])

          best_cost_according_to_tws(route_data, service_id, service_data, previous, position: position, activity: activity, first_visit: first_visit)
        }
      }.flatten.compact.min_by{ |cost| cost[:back_to_depot] }
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
        inserted_service[:tw].select{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:global_day_index] % 7 }.each{ |tw|
          start = tw[:start] ? [previous[:end], tw[:start] - route_time - setup_duration].max : previous[:end]
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

    def get_unassigned_info(custom_id, service_in_vrp, reason)
      {
        original_service_id: service_in_vrp.id,
        service_id: custom_id,
        point_id: service_in_vrp.activity&.point_id,
        detail: {
          lat: service_in_vrp.activity&.point&.location&.lat,
          lon: service_in_vrp.activity&.point&.location&.lon,
          setup_duration: service_in_vrp.activity&.setup_duration,
          duration: service_in_vrp.activity&.duration,
          timewindows: service_in_vrp.activity&.timewindows ? service_in_vrp.activity.timewindows.collect{ |tw| { start: tw.start, end: tw.end } }.sort_by{ |t| t[:start] } : [],
          quantities: service_in_vrp.quantities.collect{ |qte| { unit: qte.unit.id, value: qte.value, label: qte.unit.label } }
        },
        type: 'service',
        reason: reason
      }
    end

    def insert_point_in_route(route_data, point_to_add, first_visit = true)
      ### modify [route_data] such that [point_to_add] is in the route ###
      current_route = route_data[:stops]
      @candidate_services_ids.delete(point_to_add[:id])

      @services_data[point_to_add[:id]][:used_days] << point_to_add[:day]
      @services_data[point_to_add[:id]][:used_vehicles] |= [point_to_add[:vehicle]]
      @points_vehicles_and_days[point_to_add[:point]][:vehicles] = @points_vehicles_and_days[point_to_add[:point]][:vehicles] | [route_data[:vehicle_id].split('_')[0..-2].join('_')]
      @points_vehicles_and_days[point_to_add[:point]][:days] = @points_vehicles_and_days[point_to_add[:point]][:days] | [route_data[:global_day_index]]
      @points_vehicles_and_days[point_to_add[:point]][:maximum_visits_number] = [@points_vehicles_and_days[point_to_add[:point]][:maximum_visits_number], @services_data[point_to_add[:id]][:raw].visits_number].max
      @services_data[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }

      @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, r_d| r_d[:available_ids].delete(point_to_add[:id]) } } if first_visit
      @freq_max_at_point[point_to_add[:point]] = [@freq_max_at_point[point_to_add[:point]], @services_data[point_to_add[:id]][:raw].visits_number].max

      current_route.insert(point_to_add[:position],
                           id: point_to_add[:id],
                           point_id: point_to_add[:point],
                           start: point_to_add[:start],
                           arrival: point_to_add[:arrival],
                           end: point_to_add[:end],
                           considered_setup_duration: point_to_add[:considered_setup_duration],
                           max_shift: point_to_add[:potential_shift],
                           number_in_sequence: 1,
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

        @matrices.find{ |matrix| matrix[:id] == route_data[:matrix_id] }[dimension][start][arrival]
      end
    end

    def get_stop(vrp, stop, options = {})
      associated_point = vrp[:points].find{ |point| point[:id] == stop }

      {
        point_id: stop,
        detail: {
          lat: (associated_point[:location][:lat] if associated_point[:location]),
          lon: (associated_point[:location][:lon] if associated_point[:location]),
          quantities: [],
          begin_time: options[:begin_time],
          departure_time: options[:departure_time]
        }.delete_if{ |_k, v| !v }
      }
    end

    def get_activities(day, vrp, route_activities)
      day_name = { 0 => 'mon', 1 => 'tue', 2 => 'wed', 3 => 'thu', 4 => 'fri', 5 => 'sat', 6 => 'sun' }[day % 7]
      size_weeks = (@schedule_end.to_f / 7).ceil.to_s.size
      route_activities.collect.with_index{ |point, point_index|
        service_in_vrp = vrp.services.find{ |s| s.id == point[:id] }
        associated_point = vrp.points.find{ |pt| pt.id == point[:point_id] || pt.matrix_index == point[:point_id] }
        {
          day_week_num: "#{day % 7}_#{Helper.string_padding(day / 7 + 1, size_weeks)}",
          day_week: "#{day_name}_#{Helper.string_padding(day / 7 + 1, size_weeks)}",
          original_service_id: service_in_vrp.id,
          service_id: "#{point[:id]}_#{point[:number_in_sequence]}_#{service_in_vrp.visits_number}",
          point_id: service_in_vrp.activity&.point&.id || service_in_vrp.activities[point[:activity]]&.point&.id,
          begin_time: point[:arrival],
          departure_time: route_activities[point_index + 1] ? route_activities[point_index + 1][:start] : point[:end],
          detail: {
            lat: associated_point.location&.lat,
            lon: associated_point.location&.lon,
            skills: @services_data[point[:id]][:skills].to_a << day_name,
            setup_duration: point[:considered_setup_duration],
            duration: point[:end] - point[:arrival],
            timewindows: (service_in_vrp.activity&.timewindows || service_in_vrp.activities[point[:activity]].timewindows).select{ |t| t.day_index == day % 7 }.collect{ |tw| { start: tw.start, end: tw.end } },
            quantities: service_in_vrp.quantities&.collect{ |qte| { unit: qte.unit.id, value: qte.value, label: qte.unit.label } }
          }
        }
      }.flatten
    end

    def prepare_output_and_collect_routes(vrp)
      routes = []
      solution = []

      @candidate_routes.each{ |vehicle_id, all_routes|
        all_routes.keys.sort.each{ |day|
          route_data = all_routes[day]

          computed_activities = []
          start_time, end_time = if route_data[:stops].empty?
            computed_activities << get_stop(vrp, route_data[:start_point_id]) if route_data[:start_point_id]
            computed_activities << get_stop(vrp, route_data[:end_point_id]) if route_data[:end_point_id]

            [route_data[:tw_start], route_data[:tw_start]]
          else
            end_of_route = route_data[:end_point_id] ? route_data[:stops].last[:end] + matrix(route_data, route_data[:stops].last[:point_id], route_data[:end_point_id]) : route_data[:stops].last[:end]
            computed_activities << get_stop(vrp, route_data[:start_point_id], departure_time: route_data[:stops].first[:start]) if route_data[:start_point_id]
            computed_activities += get_activities(day, vrp, route_data[:stops])
            computed_activities << get_stop(vrp, route_data[:end_point_id], begin_time: end_of_route) if route_data[:end_point_id]

            [route_data[:stops].first[:start], end_of_route]
          end

          routes << {
            vehicle: {
              id: route_data[:vehicle_id]
            },
            mission_ids: computed_activities.collect{ |stop| stop[:service_id] }.compact
          }

          solution << {
            vehicle_id: route_data[:vehicle_id],
            original_vehicle_id: vehicle_id,
            start_time: start_time,
            end_time: end_time,
            activities: computed_activities
          }
        }
      }

      unassigned = collect_unassigned
      vrp[:preprocessing_heuristic_result] = {
        cost: @cost,
        solvers: ['heuristic'],
        iterations: 0,
        routes: solution,
        unassigned: unassigned,
        elapsed: (Time.now - @starting_time) * 1000 # ms
      }

      routes
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

    def try_to_insert_at(vehicle_id, day, service_id, visit_number)
      # when adjusting routes, tries to insert [service_id] at [day] for [vehicle]
      if !@candidate_routes[vehicle_id][day][:completed] &&
         @services_data[service_id][:capacity].all?{ |need, qty| @candidate_routes[vehicle_id][day][:capacity_left][need] - qty >= 0 } &&
         @services_data[service_id][:sticky_vehicles_ids].empty? || @services_data[service_id][:sticky_vehicles_ids].include?(vehicle_id)

        best_index = find_best_index(service_id, @candidate_routes[vehicle_id][day], false)

        if best_index
          insert_point_in_route(@candidate_routes[vehicle_id][day], best_index, false)
          @candidate_routes[vehicle_id][day][:stops].find{ |stop| stop[:id] == service_id }[:number_in_sequence] = visit_number

          day
        end
      end
    end

    def find_corresponding_timewindow(day, arrival_time, timewindows, duration)
      timewindows.select{ |tw|
        (tw[:day_index].nil? || tw[:day_index] == day % 7) && # compatible days
          (tw[:start].nil? && tw[:end].nil? ||
            (arrival_time.between?(tw[:start], tw[:end]) || arrival_time <= tw[:start]) && # arrival_time is accepted
            (!@duration_in_tw || ([tw[:start], arrival_time].max + duration <= tw[:end]))) # duration accepted in tw
      }.min_by{ |tw| tw[:start] }
    end

    def find_referent(route_data)
      if route_data[:stops].empty?
        nil
      else
        route_data[:stops].max_by{ |stop|
          matrix(route_data, route_data[:start_point_id], stop[:point_id]) + matrix(route_data, stop[:point_id], route_data[:end_point_id])
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

      route_vrp.services.delete_if{ |service| !current_route.collect{ |service| service[:id] }.include?(service[:id]) }
      route_vrp.services.each{ |service|
        next if service.activity

        service.activity = service.activities[current_route.find{ |stop| stop[:id] == service.id }[:activity]]
        service.activities = nil
      }
      route_vrp.vehicles = [vehicle]

      # configuration
      route_vrp.schedule_range_indices = nil

      route_vrp.resolution_minimum_duration = 100
      route_vrp.resolution_time_out_multiplier = 5
      route_vrp.resolution_solver = true
      route_vrp.restitution_intermediate_solutions = false

      route_vrp.preprocessing_first_solution_strategy = nil
      # NOT READY YET :
      # route_vrp.preprocessing_cluster_threshold = 0
      # route_vrp.preprocessing_force_cluster = true
      route_vrp.preprocessing_partitions = []
      route_vrp.restitution_csv = false

      # TODO : write conf by hand to avoid mistakes
      # will need load ? use route_vrp[:configuration] ... or route_vrp.preprocessing_first_sol

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
      @previous_uninserted = Marshal.load(Marshal.dump(@uninserted))
      @previous_candidate_service_ids = Marshal.load(Marshal.dump(@candidate_services_ids))
    end

    def restore
      @candidate_routes = @previous_candidate_routes
      @uninserted = @previous_uninserted
      @candidate_services_ids = @previous_candidate_service_ids
    end
  end
end
