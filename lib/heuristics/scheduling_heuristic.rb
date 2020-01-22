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
require './lib/heuristics/concerns/scheduling_data_initialisation.rb'
require './lib/heuristics/concerns/scheduling_end_phase'

module Heuristics
  class Scheduling
    include SchedulingDataInitialization
    include SchedulingEndPhase

    def initialize(vrp, expanded_vehicles, schedule, job = nil)
      # heuristic data
      @candidate_vehicles = []
      @vehicle_day_completed = {}
      @to_plan_service_ids = []
      @services_data = {}
      @previous_candidate_service_ids = nil
      @candidate_services_ids = []

      @indices = {}
      @matrices = vrp[:matrices]

      # in the case of same_point_day, service with higher heuristic period unlocks others
      @services_unlocked_by = {}
      @unlocked = []
      @same_located = {}
      @freq_max_at_point = Hash.new(0)
      @max_day = Hash.new({}) # max_day[nb_visits][minimum_lapse] = last day authorized

      @used_to_adjust = []
      @previous_uninserted = nil
      @uninserted = {}
      @missing_visits = {}

      @previous_candidate_routes = nil
      @candidate_routes = {}

      # heuristic options
      @allow_partial_assignment = vrp.resolution_allow_partial_assignment
      @same_point_day = vrp.resolution_same_point_day
      @relaxed_same_point_day = false
      @duration_in_tw = false # TODO: create parameter for this

      # global data
      @real_schedule_start = schedule[:start]
      @schedule_end = schedule[:end]
      @shift = schedule[:shift]
      @expanded_vehicles = expanded_vehicles
      vrp.vehicles.each{ |vehicle|
        @candidate_vehicles << vehicle.id
        @candidate_routes[vehicle.id] = {}
        @vehicle_day_completed[vehicle.id] = {}
      }

      collect_services_data(vrp)
      collect_indices(vrp)
      generate_route_structure(vrp)
      compute_latest_authorized
      @starting_time = Time.now
      @cost = 0

      vehicle_names = expanded_vehicles.collect{ |v| v.id.split('_').slice(0, 2).join('_') }.uniq
      @output_tool = OptimizerWrapper.config[:debug][:output_schedule] ? OutputHelper::Scheduling.new(vrp.name, vehicle_names, job, @schedule_end) : nil
    end

    def compute_initial_solution(vrp, &block)
      block&.call()

      fill_days

      # Relax same_point_day constraint
      if @same_point_day && !@candidate_services_ids.empty?
        # If there are still unassigned visits
        # relax the @same_point_day constraint but
        # keep the logic of unlocked for less frequent visits.
        # We still call fill_grouped but with same_point_day = false
        @to_plan_service_ids = @candidate_services_ids
        @same_point_day = false
        @relaxed_same_point_day = true
        fill_days
      end

      save_status

      # Reorder routes with solver and try to add more visits
      if vrp.resolution_solver && !@candidate_services_ids.empty?
        reorder_routes(vrp)
        fill_days
      end

      add_missing_visits if @allow_partial_assignment && !@same_point_day

      begin
        check_solution_validity
      rescue
        log 'Solution after calling solver to reorder routes is unfeasible.', level: :warn
        restore
      end

      check_solution_validity

      @output_tool&.close_file

      routes = prepare_output_and_collect_routes(vrp)
      routes
    end

    def clean_routes(service, vehicle)
      ### when allow_partial_assignment is false, removes all affected visits of [service] because we can not affect all visits ###
      @candidate_routes[vehicle].collect{ |_day, day_route|
        remove_index = day_route[:current_route].find_index{ |stop| stop[:id] == service[:id] }
        day_route[:current_route].slice!(remove_index) if remove_index
        day_route[:current_route] = update_route(day_route, remove_index) if remove_index
      }.compact.size

      (1..@services_data[service[:id]][:nb_visits]).each{ |number_in_sequence|
        @uninserted["#{service[:id]}_#{number_in_sequence}_#{@services_data[service[:id]][:nb_visits]}"] = {
          original_service: service[:id],
          reason: 'Partial assignment only'
        }
      }

      # unaffected all points at this location
      points_at_same_location = @candidate_services_ids.select{ |id| @services_data[id][:points_ids] == @services_data[service[:id]][:points_ids] }
      points_at_same_location.each{ |id|
        (1..@services_data[id][:nb_visits]).each{ |visit|
          @uninserted["#{id}_#{visit}_#{@services_data[id][:nb_visits]}"] = {
            original_service: id,
            reason: 'Partial assignment only'
          }
        }
        @candidate_services_ids.delete(id)
        @to_plan_service_ids.delete(id)
      }
    end

    def check_solution_validity
      @candidate_routes.each{ |_vehicle, all_days_routes|
        all_days_routes.each{ |_day, route|
          next if route[:current_route].empty?

          time_back_to_depot = route[:current_route].last[:end] + matrix(route, route[:current_route].last[:point_id], route[:end_point_id])
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is starting too soon' if route[:current_route][0][:start] < route[:tw_start]
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is ending too late' if time_back_to_depot > route[:tw_end]
        }
      }

      @candidate_routes.each{ |_vehicle, all_days_routes|
        all_days_routes.each{ |day, route|
          route[:current_route].each_with_index{ |s, i|
            next if @services_data[s[:id]][:tws_sets].flatten.empty? || i.positive? && can_ignore_tw(route[:current_route][i - 1][:id], s[:id])

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

    def adjust_candidate_routes(vehicle, day_finished)
      ### assigns all visits of services in [services] that where newly scheduled on [vehicle] at [day_finished] ###
      days_available = @candidate_routes[vehicle].keys
      @candidate_routes[vehicle][day_finished][:current_route].reject{ |service| @used_to_adjust.include?(service[:id]) }.sort_by{ |service|
        @services_data[service[:id]][:priority]
      }.each{ |service|
        @used_to_adjust << service[:id]
        peri = @services_data[service[:id]][:heuristic_period]

        next if peri.nil?

        next_day = day_finished + peri
        day_to_insert = days_available.select{ |day| day >= next_day.round }.min
        if day_to_insert
          diff = day_to_insert - next_day.round
          next_day += diff
        end

        this_service_days = [day_finished]
        cleaned_service = false
        need_to_add_visits = false
        (2..@services_data[service[:id]][:nb_visits]).each{ |visit_number|
          inserted_day = nil
          while inserted_day.nil? && day_to_insert && day_to_insert <= @schedule_end && !cleaned_service
            inserted_day = try_to_insert_at(vehicle, day_to_insert, service, visit_number) if days_available.include?(day_to_insert)
            this_service_days << inserted_day if inserted_day

            next_day += peri
            day_to_insert = days_available.select{ |day| day >= next_day.round }.min

            next if day_to_insert.nil?

            diff = day_to_insert - next_day.round
            next_day += diff
          end

          next if inserted_day

          if !@allow_partial_assignment
            clean_routes(service, vehicle)
            cleaned_service = true
          else
            need_to_add_visits = true # only if allow_partial_assignment, do not add_missing_visits otherwise
            @uninserted["#{service[:id]}_#{visit_number}_#{@services_data[service[:id]][:nb_visits]}"] = {
              original_service: service[:id],
              reason: "Visit not assignable by heuristic, first visit assigned at day #{day_finished}"
            }
          end
        }

        @missing_visits[vehicle] << { id: service[:id], used_days: this_service_days } if need_to_add_visits
      }
    end

    def initialize_routes(routes)
      inserted_ids = []
      routes.sort_by{ |route| route[:day] }.each{ |defined_route|
        associated_route = @candidate_routes[defined_route.vehicle_id][defined_route.day.to_i]
        defined_route.mission_ids.each{ |id|
          inserted_ids << id

          raise UnsupportedProblemError, 'Services in initialize routes should have only one activity' if @services_data[id][:nb_activities] > 1

          if associated_route
            associated_route[:current_route] << {
              id: id,
              point_id: @services_data[id][:points_ids].first,
              arrival: 0,                                # needed to compute route data
              end: @services_data[id][:durations].first, # needed to compute route data
              number_in_sequence: inserted_ids.count(id),
              activity: 0,
            }
          else
            @uninserted["#{id}_#{inserted_ids.count(id)}_#{@services_data[id][:nb_visits]}"] = {
              original_service: id,
              reason: "Unfeasible route (vehicle #{defined_route.vehicle_id} not available at day #{defined_route.day})"
            }
          end

          @candidate_services_ids.delete(id)
          @to_plan_service_ids.delete(id)
          # all visits should be assigned manually, or not assigned at all
          @used_to_adjust << id

          # unlock corresponding services
          services_to_add = @services_unlocked_by[id].to_a - @uninserted.collect{ |_un, data| data[:original_service] }
          @to_plan_service_ids += services_to_add
          @unlocked += services_to_add
        }

        next if associated_route.nil?

        begin
          update_route(associated_route, 0)
        rescue
          raise OptimizerWrapper::UnsupportedProblemError, 'Initial solution provided is not feasible.'
        end
      }

      check_missing_visits(inserted_ids)
    end

    def check_missing_visits(inserted_ids)
      inserted_ids.group_by{ |id| id }.each{ |id, set|
        next if set.size == @services_data[id][:nb_visits]

        (set.size + 1..@services_data[id][:nb_visits]).each{ |missing_visit|
          @uninserted["#{id}_#{missing_visit}_#{@services_data[id][:nb_visits]}"] = {
            original_service: id,
            reason: "Some visits assigned manually (#{set.size} visits preassigned in routes)"
          }
        }
      }
    end

    def update_route(full_route, first_index, first_start = nil)
      # recomputes each stop associated values (start, arrival, setup ... times) only according to their insertion order
      day_route = full_route[:current_route]
      day_route if first_index > day_route.size

      previous_id = first_index.zero? ? full_route[:start_point_id] : day_route[first_index - 1][:id]
      previous_point_id = first_index.zero? ? previous_id : day_route[first_index - 1][:point_id]
      previous_end = first_index.zero? ? full_route[:tw_start] : day_route[first_index - 1][:end]
      if first_start
        previous_end = first_start
      end

      (first_index..day_route.size - 1).each{ |position|
        stop = day_route[position]
        route_time = matrix(full_route, previous_point_id, stop[:point_id])
        stop[:considered_setup_duration] = route_time.zero? ? 0 : @services_data[stop[:id]][:setup_durations][stop[:activity]]

        if can_ignore_tw(previous_id, stop[:id])
          stop[:start] = previous_end
          stop[:arrival] = previous_end
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:durations][stop[:activity]]
          stop[:max_shift] = day_route[position - 1][:max_shift]
        else
          tw = find_corresponding_timewindow(full_route[:global_day_index], previous_end + route_time + stop[:considered_setup_duration], @services_data[stop[:id]][:tws_sets][stop[:activity]], stop[:end] - stop[:arrival])
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

      raise OptimizerWrapper::SchedulingHeuristicError, 'Vehicle end violated after updating route' if day_route.size.positive? &&
                                                                                                       day_route.last[:end] + matrix(full_route, day_route.last[:point_id], full_route[:end_point_id]) > full_route[:tw_end]

      day_route
    end

    def collect_unassigned(vrp)
      unassigned = []

      @candidate_services_ids.each{ |point|
        service_in_vrp = vrp.services.find{ |service| service[:id] == point }
        (1..service_in_vrp[:visits_number]).each{ |index|
          unassigned << get_unassigned_info(vrp, "#{point}_#{index}_#{service_in_vrp[:visits_number]}", service_in_vrp, 'Heuristic could not affect this service before all vehicles are full')
        }
      }

      @uninserted.keys.each{ |service|
        s = @uninserted[service][:original_service]
        service_in_vrp = vrp.services.find{ |current_service| current_service[:id] == s }
        unassigned << get_unassigned_info(vrp, service, service_in_vrp, @uninserted[service][:reason])
      }

      unassigned
    end

    def provide_group_tws(services, day)
      services.each{ |service|
        next if !@services_unlocked_by.collect{ |id, set| [id, set] }.flatten.include?(service.id) || # not in a same_point_day_relation
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

    def reorder_routes(vrp)
      vrp.vehicles.each{ |vehicle|
        @candidate_routes[vehicle.id].each{ |day, route|
          next if route[:current_route].collect{ |s| s[:point_id] }.uniq.size <= 1

          corresponding_vehicle = @expanded_vehicles.select{ |v| v[:original_id] == vehicle.id }.find{ |v| v[:global_day_index] == day }
          corresponding_vehicle.timewindow.start = route[:tw_start]
          corresponding_vehicle.timewindow.end = route[:tw_end]
          route_vrp = construct_sub_vrp(vrp, corresponding_vehicle, route[:current_route])

          log "Re-ordering route for #{vehicle.id} at day #{day} : #{route[:current_route].size}"

          # TODO : test with and without providing initial solution ?
          route_vrp.routes = collect_generated_routes(route_vrp.vehicles.first, route[:current_route])
          route_vrp.services = provide_group_tws(route_vrp.services, day) if @same_point_day || @relaxed_same_point_day # to have same data in ORtools and scheduling. Customers should ensure all timewindows are the same for same points

          begin
            result = OptimizerWrapper.solve([service: :ortools, vrp: route_vrp])
          rescue
            log 'ORtools could not find a solution for this problem.', level: :warn
          end

          next if result.nil? || !result[:unassigned].empty?

          time_back_to_depot = route[:current_route].last[:end] + matrix(route, route[:current_route].last[:point_id], route[:end_point_id])
          scheduling_route_time = time_back_to_depot - route[:current_route].first[:start]
          solver_route_time = (result[:routes].first[:activities].last[:begin_time] - result[:routes].first[:activities].first[:begin_time]) # last activity is vehicle depot

          next if scheduling_route_time - solver_route_time < @candidate_services_ids.collect{ |s| @services_data[s][:durations] }.flatten.min ||
                  result[:routes].first[:activities].collect{ |stop| @indices[stop[:service_id]] }.compact == route[:current_route].collect{ |s| @indices[s[:id]] } # we did not change our points order

          # we are going to try to optimize this route reoptimized by OR-tools
          begin
            # this will change @candidate_routes, but it should not be a problem since OR-tools returns a valid solution
            route[:current_route] = compute_route_from(route, result[:routes].first[:activities])
          rescue OptimizerWrapper::SchedulingHeuristicError
            log 'Failing to construct route from OR-tools solution'
          end
        }
      }
    end

    def compute_route_from(new_route, solver_route)
      solver_order = solver_route.collect{ |s| s[:service_id] }.compact
      new_route[:current_route].sort_by!{ |stop| solver_order.find_index(stop[:id]) }.collect{ |s| s[:id] }
      update_route(new_route, 0, solver_route.first[:begin_time])
    end

    def possible_for_point(point, nb_visits)
      # since @same_point_day is or has been activated, we know each service has exactly one point_id

      routes_with_point = @candidate_routes.collect{ |vehicule, route| [vehicule, route.collect{ |day, data| data[:current_route].any?{ |stop| stop[:point_id] == point } ? day : nil }.compact] }
      routes_with_point.delete_if{ |_vehicule, days| days.empty? }

      raise OptimizerWrapper::SchedulingHeuristicError, "Several vehicules affected to point #{point}" if (@same_point_day || @relaxed_same_point_day) && routes_with_point.size > 1

      allowed_vehicules = routes_with_point.collect(&:first)
      allowed_days = routes_with_point.collect{ |tab| tab[1] }.flatten.uniq
      max_nb_visits_for_point = allowed_vehicules.collect{ |v|
        allowed_days.collect{ |d|
          @candidate_routes[v][d][:current_route].select{ |stop| stop[:point_id] == point }.collect{ |stop| @services_data[stop[:id]][:nb_visits] }
        }
      }.flatten.uniq.max

      if !allowed_days.empty? && nb_visits > max_nb_visits_for_point
        allowed_days = allowed_vehicules.collect{ |v| @candidate_routes[v].keys }.flatten.uniq # all days are allowed
      end

      [allowed_vehicules, allowed_days]
    end

    def compute_insertion_costs(vehicle, day, route_data)
      ### compute the cost, for each remaining service to assign, of assigning it to [route_data] ###
      insertion_costs = []
      set = @same_point_day ? @to_plan_service_ids.reject{ |id| @services_data[id][:nb_visits] == 1 } : @to_plan_service_ids
      # we will assign services with one vehicle in relaxed_same_point_day part
      set.select{ |service|
        # quantities are respected
        ((@same_point_day && @services_data[service][:group_capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] }) ||
          (!@same_point_day && @services_data[service][:capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] })) &&
          # service is available at this day
          !@services_data[service][:unavailable_days].include?(day) &&
          (@services_data[service][:sticky_vehicles_ids].empty? || @services_data[service][:sticky_vehicles_ids].include?(vehicle))
      }.each{ |service_id|
        possible_vehicles, possible_days = possible_for_point(@services_data[service_id][:points_ids].first, @services_data[service_id][:nb_visits]) if @same_point_day || @relaxed_same_point_day

        next if @relaxed_same_point_day &&
                !possible_vehicles.empty? && (!possible_vehicles.include?(vehicle) || !possible_days.include?(day))

        next if @same_point_day && @unlocked.include?(service_id) && (!possible_vehicles.include?(vehicle) || !possible_days.include?(day))

        period = @services_data[service_id][:heuristic_period]
        latest_authorized_day = @max_day[@services_data[service_id][:nb_visits]][period]

        next if !(period.nil? ||
                day <= latest_authorized_day && (day + period..@schedule_end).step(period).find{ |current_day| @vehicle_day_completed[vehicle][current_day] }.nil? &&
                same_point_compatibility(service_id, vehicle, day))

        other_indices = find_best_index(service_id, route_data)
        insertion_costs << other_indices if other_indices
      }

      insertion_costs.compact
    end

    def same_point_compatibility(service_id, vehicle, day)
      # reminder : services in (relaxed_)same_point_day relation have only one point_id
      same_point_compatible_day = true

      return same_point_compatible_day if @services_data[service_id][:heuristic_period].nil?

      last_visit_day = day + (@services_data[service_id][:nb_visits] - 1) * @services_data[service_id][:heuristic_period]
      if @relaxed_same_point_day
        # we know only one activity/point_id because @same_point_day was activated
        involved_days = (day..last_visit_day).step(@services_data[service_id][:heuristic_period]).collect{ |d| d }
        already_involved = @candidate_routes[vehicle].select{ |_d, r| r[:current_route].any?{ |s| s[:point_id] == @services_data[service_id][:points_ids].first } }.collect{ |d, _r| d }
        if !already_involved.empty? &&
           @services_data[service_id][:nb_visits] > @freq_max_at_point[@services_data[service_id][:points_ids].first] &&
           (involved_days & already_involved).size < @freq_max_at_point[@services_data[service_id][:points_ids].first]
          same_point_compatible_day = false
        elsif !already_involved.empty? && (involved_days & already_involved).size < involved_days.size
          same_point_compatible_day = false
        end
      elsif @unlocked.include?(service_id)
        # can not finish later (over whole period) than service at same_point
        stop = @candidate_routes[vehicle][day][:current_route].select{ |stop| stop[:point_id] == @services_data[service_id][:points_ids].first }.max_by{ |stop| @services_data[stop[:id]][:nb_visits] }
        stop_last_visit_day = day + (@services_data[stop[:id]][:nb_visits] - stop[:number_in_sequence]) * @services_data[stop[:id]][:heuristic_period]
        same_point_compatible_day = last_visit_day <= stop_last_visit_day if same_point_compatible_day
      end

      same_point_compatible_day
    end

    def compute_shift(route_data, service_inserted, inserted_final_time, next_service)
      route = route_data[:current_route]

      if route.empty?
        matrix(route_data, route_data[:start_point_id], service_inserted[:point_id]) + matrix(route_data, service_inserted[:point_id], route_data[:end_point_id])
      elsif next_service
        dist_to_next = matrix(route_data, service_inserted[:point_id], next_service[:point_id])
        shift = 0
        if can_ignore_tw(service_inserted[:id], next_service[:id])
          shift += service_inserted[:duration]
        else
          next_service[:tw] = @services_data[next_service[:id]][:tws_sets][next_service[:activity]]
          next_service[:duration] = @services_data[next_service[:id]][:durations][next_service[:activity]]
          next_end = compute_tw_for_next(inserted_final_time, next_service, dist_to_next, route_data[:global_day_index])
          shift += next_end - next_service[:end]
        end

        shift
      else
        inserted_final_time - route.last[:end]
      end
    end

    def compute_tw_for_next(inserted_final_time, route_next, dist_from_inserted, current_day)
      ### compute new start and end times for the service just after inserted point ###
      sooner_start = inserted_final_time
      if !route_next[:tw].empty?
        tw = find_corresponding_timewindow(current_day, route_next[:arrival], @services_data[route_next[:id]][:tws_sets][route_next[:activity]], route_next[:end] - route_next[:arrival])
        sooner_start = tw[:start] - dist_from_inserted - route_next[:considered_setup_duration] if tw && tw[:start]
      end
      new_start = [sooner_start, inserted_final_time].max
      new_arrival = new_start + dist_from_inserted + route_next[:considered_setup_duration]
      new_end = new_arrival + route_next[:duration]

      new_end
    end

    def acceptable?(shift, route_data, position)
      computed_shift = shift
      acceptable = route_data[:current_route][position] && route_data[:current_route][position][:max_shift] ? route_data[:current_route][position][:max_shift] >= shift : true

      if acceptable && route_data[:current_route][position + 1]
        (position + 1..route_data[:current_route].size - 1).each{ |pos|
          initial_shift_with_previous = route_data[:current_route][pos][:start] - (route_data[:current_route][pos - 1][:end])
          computed_shift = [shift - initial_shift_with_previous, 0].max
          if route_data[:current_route][pos][:max_shift] && route_data[:current_route][pos][:max_shift] < computed_shift
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
      original_next_activity = route_data[:current_route][position][:activity] if route_data[:current_route][position]
      nb_activities_index = route_data[:current_route][position] ? @services_data[route_data[:current_route][position][:id]][:nb_activities] - 1 : 0

      shift, activity, time_back_to_depot, tw_accepted = (0..nb_activities_index).collect{ |activity|
        if route_data[:current_route][position]
          route_data[:current_route][position][:activity] = activity
          route_data[:current_route][position][:point_id] = @services_data[route_data[:current_route][position][:id]][:points_ids][activity]
        end

        shift = compute_shift(route_data, service, timewindow[:final_time], route_data[:current_route][position])
        if route_data[:current_route][position + 1] && activity != original_next_activity
          next_id = route_data[:current_route][position][:id]
          next_next_point_id = route_data[:current_route][position + 1][:point_id]
          shift += matrix(route_data, @services_data[next_id][:points_ids][activity], next_next_point_id) -
                   matrix(route_data, @services_data[next_id][:points_ids][original_next_activity], next_next_point_id)
        end
        acceptable_shift, computed_shift = acceptable?(shift, route_data, position)
        time_back_to_depot = if position == route_data[:current_route].size
          timewindow[:final_time] + matrix(route_data, service[:point_id], route_data[:end_point_id])
        else
          route_data[:current_route].last[:end] + matrix(route_data, route_data[:current_route].last[:point_id], route_data[:end_point_id]) + computed_shift
        end

        end_respected = timewindow[:end_tw] ? timewindow[:arrival_time] <= timewindow[:end_tw] : true
        route_start = position.zero? ? timewindow[:start_time] : route_data[:current_route].first[:start]
        duration_respected = route_data[:duration] ? time_back_to_depot - route_start <= route_data[:duration] : true
        acceptable_shift_for_itself = end_respected && duration_respected
        tw_accepted = acceptable_shift && acceptable_shift_for_itself && time_back_to_depot <= route_data[:tw_end]

        [shift, activity, time_back_to_depot, tw_accepted]
      }.min_by{ |next_info| next_info[5] }

      route_data[:current_route][position][:activity] = original_next_activity if route_data[:current_route][position]
      route_data[:current_route][position][:point_id] = @services_data[route_data[:current_route][position][:id]][:points_ids][original_next_activity] if route_data[:current_route][position]

      [activity, tw_accepted, shift, time_back_to_depot]
    end

    def compute_value_at_position(route_data, service, position, in_adjust)
      ### compute cost of inserting [service] at [position] in [route_data]
      values = []
      service_data = @services_data[service]
      route = route_data[:current_route]
      previous_info = @services_data[route[position - 1][:id]] if position.positive?
      previous = {
        id: position.zero? ? route_data[:start_point_id] : route[position - 1][:id],
        point_id: position.zero? ? route_data[:start_point_id] : route[position - 1][:point_id],
        setup_duration: position.zero? ? 0 : previous_info[:setup_durations][route[position - 1][:activity]],
        duration: position.zero? ? 0 : previous_info[:durations][route[position - 1][:activity]],
        tw: position.zero? ? [] : previous_info[:tws_sets][route[position - 1][:activity]],
        end: position.zero? ? route_data[:tw_start] : route[position - 1][:end]
      }

      (0..service_data[:nb_activities] - 1).collect{ |activity|
        duration = @same_point_day && !in_adjust ? service_data[:group_duration] : service_data[:durations][activity]

        next if route_data[:maximum_ride_time] &&
                (position.positive? && matrix(route_data, previous[:point_id], service_data[:points_ids][activity], :time) > route_data[:maximum_ride_time] ||
                position < route_data[:current_route].size && matrix(route_data, service_data[:points_ids][activity], route[position][:point_id], :time) > route_data[:maximum_ride_time])

        next if route_data[:maximum_ride_distance] &&
                (position.positive? && matrix(route_data, previous[:point_id], service_data[:points_ids][activity], :distance) > route_data[:maximum_ride_distance] ||
                position < route_data[:current_route].size && matrix(route_data, service_data[:points_ids][activity], route[position][:point_id], :distance) > route_data[:maximum_ride_distance])

        potential_tws = find_timewindows(previous, { id: service, point_id: service_data[:points_ids][activity], setup_duration: service_data[:setup_durations][activity], duration: duration, tw: service_data[:tws_sets][activity] }, route_data)

        potential_tws.each{ |tw|
          next_activity, tw_accepted, shift, back_depot = insertion_cost_with_tw(tw, route_data, { id: service, point_id: service_data[:points_ids][activity], duration: duration }, position)
          service_info = { id: service, tw: service_data[:tws_sets][activity], duration: service_data[:durations][activity] }
          acceptable_shift_for_group = in_adjust ? true : acceptable_for_group?(service_info, tw)

          next if !(tw_accepted && acceptable_shift_for_group)

          values << {
            id: service,
            point: service_data[:points_ids][activity],
            start: tw[:start_time],
            arrival: tw[:arrival_time],
            end: tw[:final_time],
            position: position,
            considered_setup_duration: tw[:setup_duration],
            next_activity: next_activity,
            potential_shift: tw[:max_shift],
            additional_route_time: [0, shift - duration - tw[:setup_duration]].max, # TODO : why using max ??min_by in select_point will chose the one that reduces work duration if we keep negative value possible
            back_to_depot: back_depot,
            activity: activity,
          }
        }
      }

      values.min_by{ |value| value[:back_to_depot] }
    end

    def fill_basic
      ### fill planning without same_point_day option ###
      all_days = @candidate_routes.collect{ |_vehicle, data| data.keys }.flatten.uniq

      all_days.each{ |day|
        @candidate_vehicles.each{ |vehicle|
          next if @candidate_routes[vehicle][day].nil?

          fill_day_in_planning(vehicle, @candidate_routes[vehicle][day])
          adjust_candidate_routes(vehicle, day)
        }
      }
    end

    def fill_days
      ### fill planning ###
      if @same_point_day || @relaxed_same_point_day
        fill_grouped
      else
        @output_tool&.add_comment('You are not using same_point_day option, only first visits will be shown.')
        fill_basic
      end
    end

    def fill_day_in_planning(vehicle, route_data)
      ### fill this specific [route_data] assigned to [vehicle] ###
      day = route_data[:global_day_index]
      current_route = route_data[:current_route]
      service_to_insert = true

      while service_to_insert
        insertion_costs = compute_insertion_costs(vehicle, day, route_data)
        if !insertion_costs.empty?
          # there are services we can add
          best_index = select_point(insertion_costs)
          insert_point_in_route(route_data, best_index)

          if @output_tool
            days = @candidate_routes[vehicle].select{ |_day, r_d| r_d[:current_route].any?{ |stop| stop[:id] == best_index[:id] } }.keys
            @output_tool.output_scheduling_insert(days, best_index[:id], @services_data[best_index[:id]][:nb_visits])
          end

          @to_plan_service_ids.delete(best_index[:id])
          @services_data[best_index[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
        else
          service_to_insert = false
          @vehicle_day_completed[vehicle][day] = true

          next if current_route.empty?

          @cost += route_data[:start_point_id] ? matrix(route_data, route_data[:start_point_id], current_route.first[:point_id]) : 0
          @cost += (0..current_route.size - 2).collect{ |position| matrix(route_data, current_route[position][:point_id], current_route[position + 1][:point_id]) }.sum
          @cost += route_data[:end_point_id] ? matrix(route_data, current_route.last[:point_id], route_data[:start_point_id]) : 0
        end
      end
    end

    def add_same_freq_located_points(best_index, route_data, adjusting_candidate_routes)
      unless adjusting_candidate_routes
        start = best_index[:end]
        max_shift = best_index[:potential_shift]
        additional_durations = @services_data[best_index[:id]][:durations].first + best_index[:considered_setup_duration]
        @same_located[best_index[:id]].each_with_index{ |service_id, i|
          route_data[:current_route].insert(best_index[:position] + i + 1,
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
    end

    def try_to_add_new_point(vehicle, day, route_data)
      insertion_costs = compute_insertion_costs(vehicle, day, route_data)

      return nil if insertion_costs.empty?

      best_index = select_point(insertion_costs)

      return nil if best_index.nil?

      best_index[:end] = best_index[:end] - @services_data[best_index[:id]][:group_duration] + @services_data[best_index[:id]][:durations].first if @same_point_day
      insert_point_in_route(route_data, best_index)
      @services_data[best_index[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }

      @to_plan_service_ids.delete(best_index[:id])

      best_index[:id]
    end

    def fill_grouped
      ### fill planning with same_point_day option ###
      @candidate_vehicles.each{ |current_vehicle|
        possible_to_fill = !@to_plan_service_ids.empty?
        nb_of_days = @candidate_routes[current_vehicle].keys.size
        forbidden_days = []

        while possible_to_fill
          best_day = @candidate_routes[current_vehicle].reject{ |day, _route| forbidden_days.include?(day) }.min_by{ |_day, route_data|
            route_data[:current_route].empty? ? 0 : route_data[:current_route].sum{ |stop| stop[:end] - stop[:start] }
          }[0]

          inserted_id = try_to_add_new_point(current_vehicle, best_day, @candidate_routes[current_vehicle][best_day])

          if inserted_id
            if @output_tool
              days = @candidate_routes[current_vehicle].select{ |_day, r_d| r_d[:current_route].any?{ |stop| stop[:id] == inserted_id } }.keys
              @output_tool.output_scheduling_insert(days, inserted_id, @services_data[inserted_id][:nb_visits])
            end

            adjust_candidate_routes(current_vehicle, best_day)

            if @services_unlocked_by[inserted_id] && !@services_unlocked_by[inserted_id].empty? && !@relaxed_same_point_day
              services_to_add = @services_unlocked_by[inserted_id] - @uninserted.collect{ |un, data| data[:original_service] }
              @to_plan_service_ids += services_to_add
              @unlocked += services_to_add
              forbidden_days = [] unless services_to_add.empty? # new services are available so we may need these days
            end
          else
            forbidden_days << best_day
          end

          if @to_plan_service_ids.empty? || forbidden_days.size == nb_of_days
            possible_to_fill = false
          end
        end
      }
    end

    def find_best_index(service, route_data, in_adjust = false)
      ### find the best position in [route_data] to insert [service] ###

      possibles = []
      route = route_data[:current_route]

      positions_to_try = if route.empty?
        [0]
      elsif @services_data[service][:points_ids].size == 1 && route.find_index{ |stop| stop[:point_id] == @services_data[service][:points_ids].first }
        [route.size - route.reverse.find_index{ |stop| stop[:point_id] == @services_data[service][:points_ids].first }]
      else
        (0..route.size).collect{ |position| position }
      end

      positions_to_try.each{ |position|
        previous_point = position.zero? ? route_data[:start_point_id] : route[position - 1][:point_id]
        next if (@same_point_day || @relaxed_same_point_day) && !(position == route.size || route[position][:point_id] != previous_point)

        possibles << compute_value_at_position(route_data, service, position, in_adjust)

        next if !(route.empty? && possibles.last)

        possibles.last[:additional_route_time] = matrix(route_data, route_data[:start_point_id], possibles.last[:point]) + matrix(route_data, possibles.last[:point], route_data[:end_point_id])
      }

      possibles.flatten.compact.sort_by!{ |possible_position| possible_position[:back_to_depot] }[0]
    end

    def can_ignore_tw(previous_service, service)
      ### true if arriving on time at previous_service is enough to consider we are on time at service ###
      # when same point day is activated we can consider two points at same location are the same
      # when @duration_in_tw is disabled, only arrival time of first point at a given location matters in tw
      (@same_point_day || @relaxed_same_point_day) &&
        !@duration_in_tw &&
        @services_data.has_key?(previous_service) && # not coming from depot
        @services_data[previous_service][:points_ids].first == @services_data[service][:points_ids].first # same location as previous
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

    def get_unassigned_info(vrp, id, service_in_vrp, reason)
      {
        original_service_id: service_in_vrp[:id],
        service_id: id,
        point_id: service_in_vrp.activity&.point_id,
        detail: {
          lat: vrp.points.find{ |point| service_in_vrp.activity && point[:id] == service_in_vrp.activity.point_id }&.location&.lat,
          lon: vrp.points.find{ |point| service_in_vrp.activity && point[:id] == service_in_vrp.activity.point_id }&.location&.lon,
          setup_duration: service_in_vrp.activity&.setup_duration,
          duration: service_in_vrp.activity&.duration,
          timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].collect{ |tw| {start: tw[:start], end: tw[:end] } }.sort_by{ |t| t[:start] } : [],
          quantities: service_in_vrp.quantities.collect{ |qte| { unit: qte.unit.id, value: qte.value, label: qte.unit.label } }
        },
        reason: reason
      }
    end

    def insert_point_in_route(route_data, point_to_add, adjusting_candidate_routes = false)
      ### modify [route_data] such that [point_to_add] is in the route ###
      current_route = route_data[:current_route]
      @candidate_services_ids.delete(point_to_add[:id])

      @freq_max_at_point[point_to_add[:point]] = [@freq_max_at_point[point_to_add[:point]], @services_data[point_to_add[:id]][:nb_visits]].max

      current_route.insert(point_to_add[:position],
                           id: point_to_add[:id],
                           point_id: point_to_add[:point],
                           start: point_to_add[:start],
                           arrival: point_to_add[:arrival],
                           end: point_to_add[:end],
                           considered_setup_duration: point_to_add[:considered_setup_duration],
                           max_shift: point_to_add[:potential_shift],
                           number_in_sequence: 1,
                           activity: point_to_add[:activity])

      add_same_freq_located_points(point_to_add, route_data, adjusting_candidate_routes) if @same_point_day

      if point_to_add[:position] < current_route.size - 1
        current_route[point_to_add[:position] + 1][:activity] = point_to_add[:next_activity]
        current_route[point_to_add[:position] + 1][:point_id] = @services_data[current_route[point_to_add[:position] + 1][:id]][:points_ids][point_to_add[:next_activity]]

        update_route(route_data, point_to_add[:position] + 1)
      end
    end

    def matrix(route_data, start, arrival, dimension = nil)
      ### return [dimension] between [start] and [arrival] ###
      if start.nil? || arrival.nil?
        0
      else
        start = @indices[start] if start.is_a?(String)
        arrival = @indices[arrival] if arrival.is_a?(String)
        dimension = route_data[:router_dimension] if dimension.nil?

        @matrices.find{ |matrix| matrix[:id] == route_data[:matrix_id] }[dimension][start][arrival]
      end
    end

    def get_stop(vrp, stop)
      associated_point = vrp[:points].find{ |point| point[:id] == stop }

      {
        point_id: stop,
        detail: {
          lat: (associated_point[:location][:lat] if associated_point[:location]),
          lon: (associated_point[:location][:lon] if associated_point[:location]),
          quantities: []
        }
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
          service_id: "#{point[:id]}_#{point[:number_in_sequence]}_#{service_in_vrp[:visits_number]}",
          point_id: service_in_vrp.activity&.point&.id || service_in_vrp.activities[point[:activity]]&.point&.id,
          begin_time: point[:arrival],
          departure_time: route_activities[point_index + 1] ? route_activities[point_index + 1][:start] : point[:end],
          detail: {
            lat: (associated_point.location.lat if associated_point.location),
            lon: (associated_point.location.lon if associated_point.location),
            skills: @services_data[point[:id]][:skills].to_a,
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

      @candidate_routes.each{ |_vehicle, all_days_routes|
        all_days_routes.keys.sort.each{ |day|
          route = all_days_routes[day]
          computed_activities = []

          computed_activities << get_stop(vrp, route[:start_point_id]) if route[:start_point_id]
          computed_activities += get_activities(day, vrp, route[:current_route])
          computed_activities << get_stop(vrp, route[:end_point_id]) if route[:end_point_id]

          routes << {
            vehicle: {
              id: route[:vehicle_id]
            },
            mission_ids: computed_activities.collect{ |stop| stop[:service_id] }.compact
          }

          solution << {
            vehicle_id: route[:vehicle_id],
            activities: computed_activities
          }
        }
      }

      unassigned = collect_unassigned(vrp)
      vrp[:preprocessing_heuristic_result] = {
        cost: @cost,
        solvers: ['heuristic'],
        iterations: 0,
        routes: solution,
        unassigned: unassigned,
        elapsed: Time.now - @starting_time
      }

      routes
    end

    def select_point(insertion_costs)
      ### chose the most interesting point to insert according to [insertion_costs] ###
      max_priority = @services_data.collect{ |_id, data| data[:priority] }.max + 1
      costs = insertion_costs.collect{ |s| s[:additional_route_time] }
      if costs.min != 0
        insertion_costs.min_by{ |s| ((@services_data[s[:id]][:priority].to_f + 1) / max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:nb_visits]**2) }
      else
        freq = insertion_costs.collect{ |s| @services_data[s[:id]][:nb_visits] }
        zero_idx = (0..(costs.size - 1)).select{ |i| costs[i].zero? }
        potential = zero_idx.select{ |i| freq[i] == freq.max }
        if !potential.empty?
          # the one with biggest duration will be the hardest to plan
          insertion_costs[potential.max_by{ |p| @services_data[insertion_costs[p][:id]][:durations][insertion_costs[p][:activity]] }]
        else
          # TODO : more tests to improve.
          # we can consider having a limit such that if additional route is > limit then we keep service with additional_route = 0 (and freq max among those)
          insertion_costs.reject{ |s| s[:additional_route_time].zero? }.min_by{ |s| ((@services_data[s[:id]][:priority].to_f + 1) / max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:nb_visits]**2) }
        end
      end
    end

    def try_to_insert_at(vehicle, day, service, visit_number)
      # when adjusting routes, tries to insert [service] at [day] for [vehicle]
      if !@vehicle_day_completed[vehicle][day] &&
         @services_data[service[:id]][:capacity].all?{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] - qty >= 0 } &&
         @services_data[service[:id]][:sticky_vehicles_ids].empty? || @services_data[service[:id]][:sticky_vehicles_ids].include?(vehicle)

        best_index = find_best_index(service[:id], @candidate_routes[vehicle][day], true)

        if best_index
          insert_point_in_route(@candidate_routes[vehicle][day], best_index, true)
          @candidate_routes[vehicle][day][:current_route].find{ |stop| stop[:id] == service[:id] }[:number_in_sequence] = visit_number

          @services_data[service[:id]][:capacity].each{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] -= qty }
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
      route_vrp.schedule_range_date = nil

      route_vrp.resolution_duration = 1000
      route_vrp.resolution_solver = true

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
