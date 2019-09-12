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

module Heuristics
  class Scheduling
    def initialize(vrp, expanded_vehicles, schedule)
      # heuristic data
      @candidate_vehicles = []
      @vehicle_day_completed = {}
      @to_plan_service_ids = []
      @services_data = {}
      @previous_candidate_service_ids = nil
      @candidate_services_ids = []

      @order = solve_tsp(vrp) # Solve TSP - Build a large Tour to define an arbitrary insertion order
      @indices = {}
      @matrices = vrp[:matrices]

      # in the case of same_point_day, service with higher heuristic period unlocks others
      @services_unlocked_by = {}
      @unlocked = []
      @same_located = {}
      @freq_max_at_point = Hash.new(0)

      @used_to_adjust = []
      @previous_uninserted = nil
      @uninserted = {}

      @previous_candidate_routes = nil
      @candidate_routes = {}
      @planning = {}

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
      @sub_pb_solved = 0
      vrp.vehicles.each{ |vehicle|
        @candidate_vehicles << vehicle.id
        @candidate_routes[vehicle.id] = {}
        @vehicle_day_completed[vehicle.id] = {}
        @planning[vehicle.id] = {}
      }

      collect_services_data(vrp)
      generate_route_structure(vrp)
      @starting_time = Time.now
      @cost = 0
    end

    def compute_initial_solution(vrp, &block)
      block&.call()

      fill_days
      save_status

      # Reorder routes with solver and try to add more visits
      if vrp.resolution_solver && !@candidate_services_ids.empty?
        reorder_routes(vrp)
        fill_days
      end

      begin
        fill_planning
        check_solution_validity
      rescue
        # TODO : send an alert in this case
        restore
      end

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

      fill_planning
      check_solution_validity

      routes = prepare_output_and_collect_routes(vrp)
      routes
    end

    def solve_tsp(vrp)
      if vrp.points.size == 1
        [vrp.points[0][:location] ? vrp.points[0][:location][:id] : vrp.points[0][:matrix_index]]
      else
        tsp = TSPHelper.create_tsp(vrp, vrp[:vehicles][0])
        result = TSPHelper.solve(tsp)
        result[:routes][0][:activities].collect{ |stop|
          associated_point = vrp.points.find{ |pt| pt[:id] == stop[:point_id] }
          associated_point[:location] ? associated_point[:location][:id] : associated_point[:matrix_index]
        }
      end
    end

    def collect_services_data(vrp)
      epoch = Date.new(1970, 1, 1)
      has_sequence_timewindows = vrp[:vehicles][0][:timewindow].nil?
      available_units = vrp.vehicles.collect{ |vehicle| vehicle[:capacities] ? vehicle[:capacities].collect{ |capacity| capacity[:unit_id] } : nil }.flatten.compact.uniq

      vrp.services.each{ |service|
        service[:unavailable_visit_day_indices] += service[:unavailable_visit_day_date].to_a.collect{ |unavailable_date|
          (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
        }.compact
        has_every_day_index = has_sequence_timewindows && !vrp.vehicles[0].sequence_timewindows.empty? && ((vrp.vehicles[0].sequence_timewindows.collect(&:day_index).uniq & (0..6).to_a).size == 7)
        period = if service[:visits_number] == 1
                    nil
                  elsif service[:minimum_lapse].to_f > 3 && @schedule_end > 3 && has_sequence_timewindows && !has_every_day_index
                    (service[:minimum_lapse].to_f / 7).ceil * 7
                  else
                    service[:minimum_lapse].nil? ? 1 : service[:minimum_lapse].ceil
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
          priority: service.priority
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

    def clean_routes(service, vehicle)
      ### when allow_partial_assignment is false, removes all affected visits of [service] because we can not affect all visits ###
      @planning[vehicle].collect{ |_day, day_route|
        remove_index = day_route[:services].find_index{ |stop| stop[:id] == service[:id] }
        day_route[:services].slice!(remove_index) if remove_index
        day_route[:services] = update_route(day_route, remove_index) if remove_index
      }.compact.size

      @candidate_routes[vehicle].collect{ |_day, day_route|
        remove_index = day_route[:current_route].find_index{ |stop| stop[:id] == service[:id] }
        day_route[:current_route].slice!(remove_index) if remove_index
        day_route[:services] = update_route(day_route, remove_index) if remove_index
      }.compact.size

      (1..@services_data[service[:id]][:nb_visits]).each{ |number_in_sequence|
        @uninserted["#{service[:id]}_#{number_in_sequence}_#{@services_data[service[:id]][:nb_visits]}"] = {
          original_service: service[:id],
          reason: 'Partial assignment only'
        }
      }

      # unaffected all points at this location
      points_at_same_location = @candidate_services_ids.select{ |id| @services_data[id][:point_id] == @services_data[service[:id]][:point_id] }
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
      @planning.each{ |_vehicle, all_days_routes|
        all_days_routes.each{ |_day, route|
          next if route[:services].empty?

          last_service = route[:services].last[:id]
          time_back_to_depot = route[:services].last[:end] + matrix(route[:vehicle], last_service, route[:vehicle][:end_point_id])
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is starting too soon' if route[:services][0][:start] < route[:vehicle][:tw_start]
          raise OptimizerWrapper::SchedulingHeuristicError, 'One vehicle is ending too late' if time_back_to_depot > route[:vehicle][:tw_end]
        }
      }

      @planning.each{ |_vehicle, all_days_routes|
        all_days_routes.each{ |day, route|
          route[:services].each_with_index{ |s, i|
            next if @services_data[s[:id]][:tw].nil? || @services_data[s[:id]][:tw].empty? ||
                    i.positive? && can_ignore_tw(route[:services][i - 1][:id], s [:id])

            compatible_tw = find_corresponding_timewindow(s[:id], day, s[:arrival])
            next if compatible_tw &&
                    s[:arrival].between?(compatible_tw[:start], compatible_tw[:end]) &&
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
      days_filled = [day_finished]
      @candidate_routes[vehicle][day_finished][:current_route].reject{ |service| @used_to_adjust.include?(service[:id]) }.sort_by{ |service|
        @services_data[service[:id]][:priority]
      }.each{ |service|
        @used_to_adjust << service[:id]
        peri = [@services_data[service[:id]][:heuristic_period], 1].compact.max
        day_to_insert = (peri % 7).positive? ? days_available.select{ |day| day >= day_finished + peri }.min : day_finished + peri

        cleaned_service = false
        (2..@services_data[service[:id]][:nb_visits]).each{ |visit_number|
          inserted_day = nil
          while inserted_day.nil? && day_to_insert && day_to_insert <= @schedule_end && !cleaned_service
            inserted_day = try_to_insert_at(vehicle, day_to_insert, service, visit_number, days_filled) if days_available.include?(day_to_insert)

            day_to_insert = if (peri % 7).positive?
              days_available.select{ |day| day >= day_to_insert + peri }.min
            else
              day_to_insert + peri
            end
          end

          next if inserted_day

          if !@allow_partial_assignment
            clean_routes(service, vehicle)
            cleaned_service = true
          elsif day_to_insert.nil? || day_to_insert > @schedule_end
            @uninserted["#{service[:id]}_#{visit_number}_#{@services_data[service[:id]][:nb_visits]}"] = {
              original_service: service[:id],
              reason: "First visit assigned at day #{day_finished} : too late to affect other visits"
            }
          else
            @uninserted["#{service[:id]}_#{visit_number}_#{@services_data[service[:id]][:nb_visits]}"] = {
              original_service: service[:id],
              reason: "Visit not assignable by heuristic, first visit assigned at day #{day_finished}"
            }
          end
        }
      }

      days_filled.uniq.each{ |d|
        compute_positions(vehicle, d)
      }
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

    def update_route(full_route, first_index, first_start = nil)
      # TODO : use in insert_point_in_route
      day_route = full_route[:services] || full_route[:current_route]
      day_route if first_index > day_route.size

      previous_id = first_index.zero? ? (full_route[:start_point_id] || full_route[:vehicle][:start_point_id]) : day_route[first_index - 1][:id]
      previous_end = first_index.zero? ? (full_route[:tw_start] || full_route[:vehicle][:tw_start]) : day_route[first_index - 1][:end]
      if first_start
        previous_end = first_start
      end

      (first_index..day_route.size - 1).each{ |position|
        stop = day_route[position]
        route_time = matrix(full_route[:vehicle] || full_route, previous_id, stop[:id])
        stop[:considered_setup_duration] = route_time.zero? ? 0 : @services_data[stop[:id]][:setup_duration]
        if can_ignore_tw(previous_id, stop[:id])
          stop[:start] = previous_end
          stop[:arrival] = previous_end
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:duration]
          stop[:max_shift] = day_route[position - 1][:max_shift]
        else
          tw = find_corresponding_timewindow(stop[:id], full_route[:global_day_index] || full_route[:vehicle][:global_day_index], previous_end + route_time + stop[:considered_setup_duration])
          raise OptimizerWrapper::SchedulingHeuristicError, 'No timewindow found to update route' if !@services_data[stop[:id]][:tw].empty? && tw.nil?

          stop[:start] = tw ? [tw[:start] - route_time - stop[:considered_setup_duration], previous_end].max : previous_end
          stop[:arrival] = stop[:start] + route_time + stop[:considered_setup_duration]
          stop[:end] = stop[:arrival] + @services_data[stop[:id]][:duration]
          stop[:max_shift] = tw ? tw[:end] - stop[:arrival] : nil
        end

        previous_id = stop[:id]
        previous_end = stop[:end]
      }

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

    def provide_group_tws(services, day)
      services.each{ |service|
        next if service[:activity][:timewindows].empty?

        service[:activity][:timewindows].each{ |original_tw|
          corresponding = find_corresponding_timewindow(service[:id], day, original_tw[:start])
          corresponding = find_corresponding_timewindow(service[:id], day, original_tw[:end]) if corresponding.nil?

          if corresponding.nil?
            service[:activity][:timewindows].delete(original_tw)
          else
            original_tw[:start] = corresponding[:start]
            original_tw[:end] = corresponding[:end]
            original_tw[:day_index] = corresponding[:day_index]
          end
        }
      }
    end

    def reorder_routes(vrp)
      vrp.vehicles.each{ |vehicle|
        @candidate_routes[vehicle.id].each{ |day, route|
          next if route[:current_route].collect{ |s| s[:point_id] }.uniq.size <= 1

          puts "Entering reorder_routes function for problem #{@sub_pb_solved}"

          services_ids = route[:current_route].collect{ |service| service[:id] }
          corresponding_vehicle = @expanded_vehicles.select{ |v| v[:original_id] == vehicle.id }.find{ |v| v[:global_day_index] == day }
          route_vrp = construct_sub_vrp(vrp, corresponding_vehicle, services_ids)

          # TODO : test with and without providing initial solution ?
          route_vrp.routes = collect_generated_routes(route_vrp.vehicles.first, route[:current_route])
          route_vrp.services = provide_group_tws(route_vrp.services, day) # to have same data in ORtools and scheduling. Customers should ensure all timewindows are the same for same points

          begin
            result = OptimizerWrapper.solve([service: :ortools, vrp: route_vrp])
          rescue
            puts 'ORtools could not find a solution for this problem.'
          end

          @sub_pb_solved += 1

          next if result.nil? || !result[:unassigned].empty?

          time_back_to_depot = route[:current_route].last[:end] + matrix(route, route[:current_route].last[:id], route[:end_point_id])
          scheduling_route_time = time_back_to_depot - route[:current_route].first[:start]
          solver_route_time = (result[:routes].first[:activities].last[:begin_time] - result[:routes].first[:activities].first[:begin_time]) # last activity is vehicle depot

          next if scheduling_route_time - solver_route_time < @candidate_services_ids.collect{ |s| @services_data[s][:duration] }.min ||
                  result[:routes].first[:activities].collect{ |stop| @indices[stop[:service_id]] }.compact == route[:current_route].collect{ |s| @indices[s[:id]] } # we did not change our points order

          # we are going to try to optimize this route reoptimized by OR-tools
          begin
            # this will change @candidate_routes, but it should not be a problem since OR-tools returns a valid solution
            route[:current_route] = compute_route_from(route, result[:routes].first[:activities])
          rescue OptimizerWrapper::SchedulingHeuristicError
            puts 'Failing to construct route from OR-tools solution'
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

    def compute_insertion_costs(vehicle, day, positions_in_order, route_data)
      ### compute the cost, for each remaining service to assign, of assigning it to [route_data] ###
      route = route_data[:current_route]
      insertion_costs = []
      set = @same_point_day ? @to_plan_service_ids.reject{ |id| @services_data[id][:nb_visits] == 1 } : @to_plan_service_ids
      # we will assign services with one vehicle in relaxed_same_point_day part
      set.select{ |service|
        # quantities are respected
        ((@same_point_day && @services_data[service][:group_capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] }) ||
          (!@same_point_day && @services_data[service][:capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] })) &&
          # service is available at this day
          !@services_data[service][:unavailable_days].include?(day)
      }.each{ |service_id|

        possible_vehicles, possible_days = possible_for_point(@services_data[service_id][:point_id], @services_data[service_id][:nb_visits])

        next if @relaxed_same_point_day &&
                !possible_vehicles.empty? && (!possible_vehicles.include?(vehicle) || !possible_days.include?(day))

        next if @same_point_day && @unlocked.include?(service_id) && (!possible_vehicles.include?(vehicle) || !possible_days.include?(day))

        same_point_compatible_day = @services_data[service_id][:heuristic_period] ? same_point_compatibility(service_id, vehicle, day) : true

        period = @services_data[service_id][:heuristic_period]
        n_visits = @services_data[service_id][:nb_visits]
        duration = @same_point_day ? @services_data[service_id][:group_duration] : @services_data[service_id][:duration]
        latest_authorized_day = @schedule_end - (period || 0) * (n_visits - 1)

        next if !(period.nil? || day <= latest_authorized_day && (day + period..@schedule_end).step(period).find{ |current_day| @vehicle_day_completed[vehicle][current_day] }.nil? && same_point_compatible_day)

        s_position_in_order = @order.index(@services_data[service_id][:point_id])
        first_bigger_position_in_sol = positions_in_order.select{ |pos| pos > s_position_in_order }.min
        insertion_index = positions_in_order.index(first_bigger_position_in_sol).nil? ? route.size : positions_in_order.index(first_bigger_position_in_sol)

        if route.find{ |s| s[:point_id] == @services_data[service_id][:point_id] }
          insertion_index = route.size - route.reverse.find_index{ |s| s[:point_id] == @services_data[service_id][:point_id] }
        end

        new_cost = compute_value_at_position(route_data, service_id, insertion_index, duration, false)
        if new_cost
          new_cost[:position_in_order] = s_position_in_order
          insertion_costs << new_cost
        end

        next if !(new_cost.nil? && !route.empty? && !route.find{ |s| s[:point_id] == @services_data[service_id][:point_id] })

        # we can try to find another index
        other_indices = find_best_index(service_id, route_data)
        insertion_costs << other_indices if other_indices
      }

      insertion_costs.compact
    end

    def same_point_compatibility(service_id, vehicle, day)
      same_point_compatible_day = true

      last_visit_day = day + (@services_data[service_id][:nb_visits] - 1) * @services_data[service_id][:heuristic_period]
      if @relaxed_same_point_day
        involved_days = (day..last_visit_day).step(@services_data[service_id][:heuristic_period]).collect{ |d| d }
        already_involved = @candidate_routes[vehicle].select{ |_d, r| r[:current_route].any?{ |s| s[:point_id] == @services_data[service_id][:point_id] } }.collect{ |d, _r| d }
        if !already_involved.empty? &&
           @services_data[service_id][:nb_visits] > @freq_max_at_point[@services_data[service_id][:point_id]] &&
           (involved_days & already_involved).size < @freq_max_at_point[@services_data[service_id][:point_id]]
          same_point_compatible_day = false
        elsif !already_involved.empty? && (involved_days & already_involved).size < involved_days.size
          same_point_compatible_day = false
        end
      elsif @unlocked.include?(service_id)
        # can not finish later (over whole period) than service at same_point
        stop = @candidate_routes[vehicle][day][:current_route].select{ |stop| stop[:point_id] == @services_data[service_id][:point_id] }.max_by{ |stop| @services_data[stop[:id]][:nb_visits] }
        stop_last_visit_day = day + (@services_data[stop[:id]][:nb_visits] - stop[:number_in_sequence]) * @services_data[stop[:id]][:heuristic_period]
        same_point_compatible_day = last_visit_day <= stop_last_visit_day if same_point_compatible_day
      end

      same_point_compatible_day
    end

    def compute_positions(vehicle, day)
      ### collects posittion in TSP solution of all points in this [vehicle] route at [day], or -1 if service was not inserted in TSP order ###
      route = @candidate_routes[vehicle][day]
      positions = []
      last_inserted = 0

      route[:current_route].each{ |point_seen|
        real_position = @order.index(point_seen[:point_id])
        positions << (last_inserted > -1 && real_position >= last_inserted ? @order.index(point_seen[:point_id]) : -1)
        last_inserted = positions.last
      }

      @candidate_routes[vehicle][day][:positions_in_order] = positions
    end

    def compute_shift(route_data, service_inserted, inserted_final_time, next_service, next_service_id)
      route = route_data[:current_route]

      if route.empty?
        return [nil, nil, nil, matrix(route_data, route_data[:start_point_id], service_inserted) + matrix(route_data, service_inserted, route_data[:end_point_id])]
      elsif next_service_id
        dist_to_next = matrix(route_data, service_inserted, next_service_id)
        if can_ignore_tw(service_inserted, route[next_service][:id])
          return [inserted_final_time, inserted_final_time, inserted_final_time + @services_data[service_inserted][:duration], @services_data[service_inserted][:duration]]
        else
          next_start, next_arrival, next_end = compute_tw_for_next(inserted_final_time, route[next_service], dist_to_next, route_data[:global_day_index])
          shift = next_end - route[next_service][:end]

          return [next_start, next_arrival, next_end, shift]
        end
      else
        return [nil, nil, nil, inserted_final_time - route.last[:end]]
      end
    end

    def compute_tw_for_next(inserted_final_time, route_next, dist_from_inserted, current_day)
      ### compute new start and end times for the service just after inserted point ###
      next_service_info = @services_data[route_next[:id]]
      sooner_start = inserted_final_time
      if next_service_info[:tw] && !next_service_info[:tw].empty?
        tw = find_corresponding_timewindow(route_next[:id], current_day, route_next[:arrival])
        sooner_start = tw[:start] - dist_from_inserted - route_next[:considered_setup_duration] if tw && tw[:start]
      end
      new_start = [sooner_start, inserted_final_time].max
      new_arrival = new_start + dist_from_inserted + route_next[:considered_setup_duration]
      new_end = new_arrival + next_service_info[:duration]

      [new_start, new_arrival, new_end]
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
      acceptable_for_group = true

      # all services start on time
      additional_durations = @services_data[service][:duration] + timewindow[:setup_duration]
      @same_located[service].each{ |id|
        acceptable_for_group = timewindow[:max_shift] - additional_durations >= 0
        additional_durations += @services_data[id][:duration]
      }

      acceptable_for_group
    end

    def insertion_cost_with_tw(timewindow, route_data, service, position)
      next_id = route_data[:current_route][position] ? route_data[:current_route][position][:id] : nil
      next_start, next_arrival, next_end, shift = compute_shift(route_data, service, timewindow[:final_time], position, next_id)

      acceptable_shift, computed_shift = acceptable?(shift, route_data, position)
      time_back_to_depot = if position == route_data[:current_route].size
        timewindow[:final_time] + matrix(route_data, service, route_data[:end_point_id])
      else
        route_data[:current_route].last[:end] + matrix(route_data, route_data[:current_route].last[:id], route_data[:end_point_id]) + computed_shift
      end

      end_respected = (timewindow[:end_tw] ? timewindow[:arrival_time] <= timewindow[:end_tw] : true)
      route_start = (position.zero? ? timewindow[:start_time] : route_data[:current_route].first[:start])
      duration_respected = (route_data[:duration] ? time_back_to_depot - route_start <= route_data[:duration] : true)
      acceptable_shift_for_itself = end_respected && duration_respected
      tw_accepted = acceptable_shift && acceptable_shift_for_itself && time_back_to_depot <= route_data[:tw_end]

      [tw_accepted, next_start, next_arrival, next_end, shift]
    end

    def compute_value_at_position(route_data, service, position, duration, filling_candidate_route = false)
      ### compute cost of inserting [service] at [position] in [route_data]
      value_inserted = false

      route = route_data[:current_route]
      previous_service = (position.zero? ? route_data[:start_point_id] : route[position - 1][:id])
      previous_service_end = (position.zero? ? nil : route[position - 1][:end])
      next_id = route[position] ? route[position][:id] : nil
      if route_data[:maximum_ride_time] && (position.positive? && matrix(route_data, previous_service, service, :time) > route_data[:maximum_ride_time] || position < route_data[:current_route].size && matrix(route_data, service, next_id, :time) > route_data[:maximum_ride_time])
        return
      end
      if route_data[:maximum_ride_distance] && (position.positive? && matrix(route_data, previous_service, service, :distance) > route_data[:maximum_ride_distance] || position < route_data[:current_route].size && matrix(route_data, service, next_id, :distance) > route_data[:maximum_ride_distance])
        return
      end

      previous = { id: previous_service, end: previous_service_end } if position.positive?
      potential_tws = find_timewindows(previous, service, route_data, duration, filling_candidate_route)
      potential_tws.each{ |tw|
        tw_accepted, next_start, next_arrival, next_end, shift = insertion_cost_with_tw(tw, route_data, service, position)
        acceptable_shift_for_group = @same_point_day && !filling_candidate_route && !@services_data[service][:tw].empty? ? acceptable_for_group?(service, tw) : true
        next if !(tw_accepted && acceptable_shift_for_group)

        value_inserted = true
        return {
          id: service,
          point: @services_data[service][:point_id],
          shift: shift,
          start: tw[:start_time],
          arrival: tw[:arrival_time],
          end: tw[:final_time],
          position: position,
          considered_setup_duration: tw[:setup_duration],
          next_start_time: next_start,
          next_arrival_time: next_arrival,
          next_final_time: next_end,
          potential_shift: tw[:max_shift],
          additional_route_time: [0, shift - duration - tw[:setup_duration]].max, # TODO : why using max ??min_by in select_point will chose the one that reduces work duration if we keep negative value possible
          dist_from_current_route: (0..route.size - 1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min,
          last_service_end: (position == route.size ? tw[:final_time] : route.last[:end] + shift)
        }
      }

      nil
    end

    def fill_basic
      ### fill planning without same_point_day option ###
      until @candidate_vehicles.empty? || @candidate_services_ids.empty?
        current_vehicle = @candidate_vehicles[0]
        days_available = @candidate_routes[current_vehicle].keys.sort_by!{ |day|
          [@candidate_routes[current_vehicle][day][:current_route].size, @candidate_routes[current_vehicle][day][:tw_end] - @candidate_routes[current_vehicle][day][:tw_start]]
        }
        current_day = days_available[0]

        until @candidate_services_ids.empty? || current_day.nil?
          fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day])
          adjust_candidate_routes(current_vehicle, current_day)
          days_available.delete(current_day)
          @candidate_routes[current_vehicle].delete(current_day)
          while @candidate_routes[current_vehicle].any?{ |_day, day_data| !day_data[:current_route].empty? }
            current_day = @candidate_routes[current_vehicle].max_by{ |_day, day_data| day_data[:current_route].size }.first
            fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day])
            adjust_candidate_routes(current_vehicle, current_day)
            days_available.delete(current_day)
            @candidate_routes[current_vehicle].delete(current_day)
          end

          current_day = days_available[0]
        end

        # we have filled all days for current vehicle
        @candidate_vehicles.delete(current_vehicle)
      end
    end

    def fill_days
      ### fill planning ###
      if @same_point_day || @relaxed_same_point_day
        fill_grouped
      else
        fill_basic
      end
    end

    def fill_day_in_planning(vehicle, route_data)
      ### fill this specific [route_data] assigned to [vehicle] ###
      day = route_data[:global_day_index]
      current_route = route_data[:current_route]
      positions_in_order = route_data[:positions_in_order]
      service_to_insert = true

      while service_to_insert
        insertion_costs = compute_insertion_costs(vehicle, day, positions_in_order, route_data)
        if !insertion_costs.empty?
          # there are services we can add
          point_to_add = select_point(insertion_costs)
          best_index = find_best_index(point_to_add[:id], route_data)

          insert_point_in_route(route_data, best_index, day)
          @to_plan_service_ids.delete(point_to_add[:id])
          @services_data[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
          if point_to_add[:position] == best_index[:position]
            positions_in_order.insert(point_to_add[:position], point_to_add[:position_in_order])
          else
            positions_in_order.insert(best_index[:position], best_index[:position_in_order])
          end

        else
          service_to_insert = false
          @vehicle_day_completed[vehicle][day] = true
          @planning[vehicle][day] = {
            vehicle: {
              vehicle_id: route_data[:vehicle_id],
              start_point_id: route_data[:start_point_id],
              end_point_id: route_data[:end_point_id],
              tw_start: route_data[:tw_start],
              tw_end: route_data[:tw_end],
              matrix_id: route_data[:matrix_id],
              router_dimension: route_data[:router_dimension]
            },
            services: current_route
          }

          next if current_route.empty?

          @cost += route_data[:start_point_id] ? matrix(route_data, route_data[:start_point_id], current_route.first[:id]) : 0
          @cost += (0..current_route.size - 2).collect{ |position| matrix(route_data, current_route[position][:id], current_route[position + 1][:id]) }.sum
          @cost += route_data[:end_point_id] ? matrix(route_data, current_route.last[:id], route_data[:start_point_id]) : 0
        end
      end
    end

    def add_same_freq_located_points(best_index, route_data)
      start = best_index[:end]
      max_shift = best_index[:potential_shift]
      additional_durations = @services_data[best_index[:id]][:duration] + best_index[:considered_setup_duration]
      @same_located[best_index[:id]].each_with_index{ |service_id, i|
        route_data[:current_route].insert(best_index[:position] + i + 1,
                                          id: service_id,
                                          point_id: best_index[:point],
                                          start: start,
                                          arrival: start,
                                          end: start + @services_data[service_id][:duration],
                                          considered_setup_duration: 0,
                                          max_shift: max_shift ? max_shift - additional_durations : nil,
                                          number_in_sequence: 1
                                        )
        additional_durations += @services_data[service_id][:duration]
        @to_plan_service_ids.delete(service_id)
        @candidate_services_ids.delete(service_id)
        start += @services_data[service_id][:duration]
        @services_data[service_id][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
        route_data[:positions_in_order].insert(best_index[:position] + i + 1, route_data[:positions_in_order][best_index[:position]])
      }
    end

    def try_to_add_new_point(vehicle, day, route_data)
      insertion_costs = compute_insertion_costs(vehicle, day, route_data[:positions_in_order], route_data)

      return nil if insertion_costs.empty?

      point_to_add = select_point(insertion_costs)
      best_index = find_best_index(point_to_add[:id], route_data)

      return nil if best_index.nil?

      best_index[:end] = best_index[:end] - @services_data[best_index[:id]][:group_duration] + @services_data[best_index[:id]][:duration] if @same_point_day
      insert_point_in_route(route_data, best_index, day)

      # update route data
      @services_data[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
      if point_to_add[:position] == best_index[:position]
        route_data[:positions_in_order].insert(point_to_add[:position], point_to_add[:position_in_order])
      else
        route_data[:positions_in_order].insert(best_index[:position], -1)
      end
      # TODO : do not put -1 if position changed just because point at same location

      @to_plan_service_ids.delete(best_index[:id])

      add_same_freq_located_points(best_index, route_data) if @same_point_day

      return best_index[:id]
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
            adjust_candidate_routes(current_vehicle, best_day)

            if @services_unlocked_by[inserted_id] && !@services_unlocked_by[inserted_id].empty?
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
      route = route_data[:current_route]
      possibles = []
      duration = @services_data[service][:duration]
      if !in_adjust
        duration = @same_point_day ? @services_data[service][:group_duration] : @services_data[service][:duration] # this should always work
      end

      if route.empty?
        if @services_data[service][:tw].empty? || @services_data[service][:tw].find{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:global_day_index] % 7 }
          tw = find_timewindows(nil, service, route_data, duration)[0]
          if tw[:final_time] + matrix(route_data, service, route_data[:end_point_id]) <= route_data[:tw_end]
            possibles << {
              id: service,
              point: @services_data[service][:point_id],
              shift: matrix(route_data, route_data[:start_point_id], service) + matrix(route_data, service, route_data[:end_point_id]) + @services_data[service][:duration],
              start: tw[:start_time],
              arrival: tw[:arrival_time],
              end: tw[:final_time],
              position: 0,
              position_in_order: -1,
              considered_setup_duration: tw[:setup_duration],
              next_start_time: nil,
              next_arrival_time: nil,
              next_final_time: nil,
              potential_shift: tw[:max_shift],
              additional_route_time: matrix(route_data, route_data[:start_point_id], service) + matrix(route_data, service, route_data[:end_point_id]),
              dist_from_current_route: (0..route.size - 1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min
            }
          end
        end
      elsif route.find_index{ |stop| stop[:point_id] == @services_data[service][:point_id] }
        same_point_index = route.size - route.reverse.find_index{ |stop| stop[:point_id] == @services_data[service][:point_id] }
        new_cost = if in_adjust
          compute_value_at_position(route_data, service, same_point_index, @services_data[service][:duration], true)
        else
          new_cost = compute_value_at_position(route_data, service, same_point_index, duration, false)
        end

        if new_cost
          new_cost[:position_in_order] = -1
          possibles << new_cost
        end
      else
        previous_point = route_data[:start_point_id]
        (0..route.size).each{ |position|
          if position == route.size || route[position][:point_id] != previous_point
            new_cost = if in_adjust
              compute_value_at_position(route_data, service, position, @services_data[service][:duration], true)
            else
              compute_value_at_position(route_data, service, position, duration, false)
            end

            if new_cost
              new_cost[:position_in_order] = -1
              possibles << new_cost
            end
          end
          if position < route.size
            previous_point = route[position][:point_id]
          end
        }
      end

      possibles.compact.sort_by!{ |possible_position| possible_position[:last_service_end] }[0]
    end

    def fill_planning
      ### collect solution to fille @planning ###
      @candidate_routes.each{ |vehicle, data|
        data.each{ |day, route_data|
          @planning[vehicle][day] = {
            vehicle: {
              vehicle_id: route_data[:vehicle_id],
              start_point_id: route_data[:start_point_id],
              end_point_id: route_data[:end_point_id],
              tw_start: route_data[:tw_start],
              tw_end: route_data[:tw_end],
              matrix_id: route_data[:matrix_id],
              router_dimension: route_data[:router_dimension]
            },
            services: route_data[:current_route].collect{ |stop| stop }
          }
        }
      }
    end

    def can_ignore_tw(previous_service, service)
      ### true if arriving on time at previous_service is enough to consider we are on time at service ###
      # when same point day is activated we can consider two points at same location are the same
      # when @duration_in_tw is disabled, only arrival time of first point at a given location matters in tw
      (@same_point_day || @relaxed_same_point_day) &&
        !@duration_in_tw &&
        @services_data.key?(previous_service) && # not coming from depot
        @services_data[previous_service][:point_id] == @services_data[service][:point_id] # same location as previous
    end

    def find_timewindows(previous, inserted_service, route_data, duration, filling_candidate_route = false)
      ### find [inserted_service] timewindow which allows to insert it in [route_data] ###
      inserted_service_info = @services_data[inserted_service]
      list = []
      route_time = (previous ? matrix(route_data, previous[:id], inserted_service) : matrix(route_data, route_data[:start_point_id], inserted_service))
      setup_duration = route_time.zero? ? 0 : inserted_service_info[:setup_duration]
      if filling_candidate_route
        duration = inserted_service_info[:duration]
      end

      if inserted_service_info[:tw].nil? || inserted_service_info[:tw].empty?
        start = previous ? previous[:end] : route_data[:tw_start]
        list << {
          start_time: start,
          arrival_time: start + route_time + setup_duration,
          final_time: start + route_time + setup_duration + duration,
          end_tw: nil,
          max_shift: nil,
          setup_duration: setup_duration
        }
      else
        inserted_service_info[:tw].select{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:global_day_index] % 7 }.each{ |tw|
          start = if tw[:start]
            previous ? [previous[:end], tw[:start] - route_time - setup_duration].max : [route_data[:tw_start], tw[:start] - route_time - setup_duration].max
          else
            previous ? previous[:end] : route_data[:tw_start]
          end
          arrival = start + route_time + setup_duration
          final = arrival + duration

          next if tw[:end] && arrival > tw[:end] && (!@duration_in_tw || final <= tw[:end]) &&
                  (previous.nil? || !can_ignore_tw(previous[:id], inserted_service))

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
          positions_in_order: [],
          maximum_ride_time: vehicle[:maximum_ride_time],
          maximum_ride_distance: vehicle[:maximum_ride_distance],
          router_dimension: vehicle[:router_dimension].to_sym
        }
        @vehicle_day_completed[original_vehicle_id][vehicle.global_day_index] = false
      }
    end

    def get_unassigned_info(vrp, id, service_in_vrp, reason)
      {
        original_service_id: service_in_vrp[:id],
        service_id: id,
        point_id: service_in_vrp[:activity][:point_id],
        detail: {
          lat: (vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lat] if vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location]),
          lon: (vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lon] if vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location]),
          setup_duration: service_in_vrp[:activity][:setup_duration],
          duration: service_in_vrp[:activity][:duration],
          timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].collect{ |tw| {start: tw[:start], end: tw[:end] } }.sort_by{ |t| t[:start] } : [],
          quantities: service_in_vrp.quantities.collect{ |qte| { unit: qte.unit.id, value: qte.value, label: qte.unit.label } }
        },
        reason: reason
      }
    end

    def insert_point_in_route(route_data, point_to_add, day)
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
                           number_in_sequence: 1
                          )

      if point_to_add[:position] < current_route.size - 1
        current_route[point_to_add[:position] + 1][:start] = point_to_add[:next_start_time]
        current_route[point_to_add[:position] + 1][:arrival] = point_to_add[:next_arrival_time]
        current_route[point_to_add[:position] + 1][:end] = point_to_add[:next_final_time]
        current_route[point_to_add[:position] + 1][:max_shift] = current_route[point_to_add[:position] + 1][:max_shift] ? current_route[point_to_add[:position] + 1][:max_shift] - point_to_add[:shift] : nil
        # TODO : use update route function for that
        if !point_to_add[:shift].zero?
          shift = point_to_add[:shift]
          (point_to_add[:position] + 2..current_route.size - 1).each{ |point|
            if shift.positive?
              initial_shift_with_previous = current_route[point][:start] - (current_route[point - 1][:end] - shift)
              shift = [shift - initial_shift_with_previous, 0].max
              current_route[point][:start] += shift
              current_route[point][:arrival] += shift
              current_route[point][:end] += shift
              current_route[point][:max_shift] = current_route[point][:max_shift] ? current_route[point][:max_shift] - shift : nil
            else
              new_potential_start = current_route[point][:start] + shift
              service_tw = if can_ignore_tw(current_route[point - 1][:id], current_route[point][:id])
                nil
              else
                find_corresponding_timewindow(current_route[point][:id], day, current_route[point][:arrival])
              end
              soonest_authorized = (@services_data[current_route[point][:id]][:tw].empty? || !service_tw ? new_potential_start : service_tw[:start] - matrix(route_data, current_route[point - 1][:id], current_route[point][:id]) - current_route[point][:considered_setup_duration])
              if soonest_authorized > new_potential_start
                shift += (soonest_authorized - new_potential_start)
              end
              current_route[point][:start] += shift
              current_route[point][:arrival] += shift
              current_route[point][:end] += shift
              current_route[point][:max_shift] = current_route[point][:max_shift] ? current_route[point][:max_shift] - shift : nil
            end
          }
        end
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
        service_in_vrp = vrp.services.find{ |s| s[:id] == point[:id] }
        associated_point = vrp[:points].find{ |pt| pt[:location] && pt[:location][:id] == point[:point_id] || pt[:matrix_index] == point[:point_id] }

        {
          day_week_num: "#{day % 7}_#{Helper.string_padding(day / 7 + 1, size_weeks)}",
          day_week: "#{day_name}_#{Helper.string_padding(day / 7 + 1, size_weeks)}",
          service_id: "#{point[:id]}_#{point[:number_in_sequence]}_#{service_in_vrp[:visits_number]}",
          point_id: service_in_vrp[:activity][:point_id],
          begin_time: point[:arrival],
          departure_time: route_activities[point_index + 1] ? route_activities[point_index + 1][:start] : point[:end],
          detail: {
            lat: (associated_point[:location][:lat] if associated_point[:location]),
            lon: (associated_point[:location][:lon] if associated_point[:location]),
            skills: @services_data[point[:id]][:skills].to_a,
            setup_duration: point[:considered_setup_duration],
            duration: service_in_vrp[:activity][:duration],
            timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].select{ |t| t[:day_index] == day % 7 }.collect{ |tw| {start: tw[:start], end: tw[:end] } } : [],
            quantities: service_in_vrp.quantities&.collect{ |qte| { unit: qte.unit.id, value: qte.value, label: qte.unit.label } }
          }
        }
      }.flatten
    end

    def prepare_output_and_collect_routes(vrp)
      routes = []
      solution = []

      @planning.each{ |_vehicle, all_days_routes|
        all_days_routes.keys.sort.each{ |day|
          route = all_days_routes[day]
          computed_activities = []

          computed_activities << get_stop(vrp, route[:vehicle][:start_point_id]) if route[:vehicle][:start_point_id]
          computed_activities += get_activities(day, vrp, route[:services])
          computed_activities << get_stop(vrp, route[:vehicle][:end_point_id]) if route[:vehicle][:end_point_id]

          routes << {
            vehicle: {
              id: route[:vehicle][:vehicle_id]
            },
            mission_ids: computed_activities.collect{ |stop| stop[:service_id] }.compact
          }

          solution << {
            vehicle_id: route[:vehicle][:vehicle_id],
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
      max_priority = @services_data.collect{ |_id, data| data[:priority] }.max
      costs = insertion_costs.collect{ |s| s[:additional_route_time] }
      if costs.min != 0
        insertion_costs.min_by{ |s| (@services_data[s[:id]][:priority].to_f / max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:nb_visits]**2) }
      else
        freq = insertion_costs.collect{ |s| @services_data[s[:id]][:nb_visits] }
        zero_idx = (0..(costs.size - 1)).select{ |i| costs[i].zero? }
        potential = zero_idx.select{ |i| freq[i] == freq.max }
        if !potential.empty?
          # the one with biggest duration will be the hardest to plan
          insertion_costs[potential.max_by{ |p| @services_data[insertion_costs[p][:id]][:duration] }]
        else
          # TODO : more tests to improve.
          # we can consider having a limit such that if additional route is > limit then we keep service with additional_route = 0 (and freq max among those)
          insertion_costs.reject{ |s| s[:additional_route_time].zero? }.min_by{ |s| (@services_data[s[:id]][:priority].to_f / max_priority) * (s[:additional_route_time] / @services_data[s[:id]][:nb_visits]**2) }
        end
      end
    end

    def try_to_insert_at(vehicle, day, service, visit_number, days_filled)
      # when adjusting routes, tries to insert [service] at [day] for [vehicle]
      if !@vehicle_day_completed[vehicle][day]
        best_index = find_best_index(service[:id], @candidate_routes[vehicle][day], true) if @services_data[service[:id]][:capacity].all?{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] - qty >= 0 }
        if best_index
          insert_point_in_route(@candidate_routes[vehicle][day], best_index, day)
          @candidate_routes[vehicle][day][:current_route].find{ |stop| stop[:id] == service[:id] }[:number_in_sequence] = visit_number

          @services_data[service[:id]][:capacity].each{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] -= qty }
          days_filled << day
          day
        end
      end
    end

    def find_corresponding_timewindow(service_id, day, arrival_time)
      @services_data[service_id][:tw].select{ |tw|
        (tw[:day_index].nil? || tw[:day_index] == day % 7) && # compatible days
          (arrival_time.between?(tw[:start], tw[:end]) || arrival_time <= tw[:start]) && # arrival_time is accepted
          (!@duration_in_tw || ([tw[:start], arrival_time].max + @services_data[service_id][:duration] <= tw[:end])) # duration accepted in tw
      }.min_by{ |tw| tw[:start] }
    end

    def construct_sub_vrp(vrp, vehicle, services_ids)
      # TODO : make private

      # TODO : check initial vrp is not modified.
      # Now it is ok because marshall dump, but do not use mashall dump
      route_vrp = Marshal.load(Marshal.dump(vrp))

      route_vrp.services.delete_if{ |service| !services_ids.include?(service[:id]) }
      route_vrp.services.each{ |service| service[:activity][:duration] = service[:activity][:duration].ceil }
      route_vrp.services.each{ |service| service[:activity][:setup_duration] = service[:activity][:setup_duration].ceil }
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
