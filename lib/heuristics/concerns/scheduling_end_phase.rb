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
module SchedulingEndPhase
  extend ActiveSupport::Concern

  def refine_solution(&block)
    @end_phase = true
    @ids_to_renumber = []

    if @allow_partial_assignment && !@same_point_day && !@relaxed_same_point_day
      block&.call(nil, nil, nil, 'scheduling heuristic - adding missing visits', nil, nil, nil)
      add_missing_visits
    end

    unless @services_data.all?{ |_id, data| (data[:raw].exclusion_cost || 0).zero? }
      block&.call(nil, nil, nil, 'scheduling heuristic - correcting underfilled routes', nil, nil, nil)
      correct_underfilled_routes
    end
  end

  def days_respecting_lapse(id, vehicle_id)
    min_lapse = @services_data[id][:raw].minimum_lapse
    max_lapse = @services_data[id][:raw].maximum_lapse
    used_days = @services_data[id][:used_days]

    return @candidate_routes[vehicle_id].keys if used_days.empty?

    @candidate_routes[vehicle_id].keys.select{ |day|
      smaller_lapse_with_other_days = used_days.collect{ |used_day| (used_day - day).abs }.min
      (min_lapse.nil? || smaller_lapse_with_other_days >= min_lapse) &&
        (max_lapse.nil? || smaller_lapse_with_other_days <= max_lapse)
    }.sort_by{ |day| used_days.collect{ |used_day| (used_day - day).abs }.min } # minimize generated lapse
  end

  private

  def reaffect_visits_number
    @ids_to_renumber.each{ |id|
      current_visit_index = 1
      previous_day = nil
      uninserted_indices = []
      @services_data[id][:used_days].sort.each{ |day|
        if previous_day.nil? || previous_day + @services_data[id][:raw].maximum_lapse >= day
          @services_data[id][:used_vehicles].each{ |vehicle_id|
            stop = @candidate_routes[vehicle_id][day][:stops].find{ |route_stop| route_stop[:id] == id }

            next unless stop

            stop[:number_in_sequence] = current_visit_index
          }
        else
          uninserted_indices << current_visit_index
        end

        current_visit_index += 1
      }

      reasons = []
      @uninserted.each{ |uninserted_id, info|
        next unless info[:original_id] == uninserted_id

        @uninserted.delete(uninserted_id)
        reasons |= info[:reason]
      }

      uninserted_indices.each{ |indice|
        @uninserted["#{id}_#{indice}_#{@services_data[id][:raw].visits_number}"] = {
          original_id: service,
          reason: "Still unassigned after end_phase. Original reasons : #{reasons}."
        }
      }
    }
  end

  #### ADD MISSING VISITS PROCESS ####

  def add_missing_visits
    @output_tool&.add_comment('ADD_MISSING_VISITS_PHASE')

    costs = compute_first_costs # usage : cost[id] = best known cost until now

    until costs.empty?
      # select best visit to insert
      max_priority = costs.keys.collect{ |id| @services_data[id][:raw].priority + 1 }.max
      best_cost = costs.min_by{ |id, info| ((@services_data[id][:raw].priority.to_f + 1) / max_priority) * (info[:cost][:additional_route_time] / @services_data[id][:raw].visits_number**2) }

      id = best_cost[0]
      day = best_cost[1][:day]
      vehicle_id = best_cost[1][:vehicle]
      log "It is interesting to add #{id} at day #{day} on #{vehicle_id}", level: :debug

      @ids_to_renumber |= [id]
      insert_point_in_route(@candidate_routes[vehicle_id][day], best_cost[1][:cost])
      @output_tool&.add_single_visit(day, @services_data[id][:used_days], id, @services_data[id][:raw].visits_number)

      costs = update_costs(costs, best_cost)
    end

    reaffect_visits_number
  end

  def update_costs(costs, best_cost)
    # update costs for inserted id, available_days changed
    uninserted_set = @uninserted.select{ |_key, info| info[:original_id] == best_cost[0] }.keys
    @uninserted.delete(uninserted_set.first)
    if uninserted_set.size > 1
      available_days = days_respecting_lapse(best_cost[0], best_cost[1][:vehicle])

      day, cost = find_best_day_cost(available_days, @candidate_routes[best_cost[1][:vehicle]], best_cost[0])

      if cost
        costs[best_cost[0]][:day] = day
        costs[best_cost[0]][:cost] = cost
      else
        costs.delete(best_cost[0])
      end
    else
      costs.delete(best_cost[0])
    end

    # update costs for all ids that should take place at this day. Route changed so cost can change too.
    costs.each{ |id, info|
      next if info[:day] != best_cost[1][:day] && info[:vehicle] != best_cost[1][:vehicle]

      day, cost = find_best_cost(id, info[:vehicle])

      if cost
        costs[id] = {
          day: day,
          vehicle: info[:vehicle],
          cost: cost
        }
      else
        costs.delete(id)
      end
    }

    costs
  end

  def find_best_day_cost(available_days, vehicle_routes, id)
    return [nil, nil] if available_days.empty?

    day = available_days[0]
    if @same_point_day && @services_data[id][:group_capacity].all?{ |need, quantity| quantity <= vehicle_routes[day][:capacity_left][need] } ||
       !@same_point_day && @services_data[id][:capacity].all?{ |need, quantity| quantity <= vehicle_routes[day][:capacity_left][need] }
      cost = find_best_index(id, vehicle_routes[day])
    end

    index = 1
    while cost.nil? && index < available_days.size
      day = available_days[index]

      if @same_point_day && @services_data[id][:group_capacity].all?{ |need, quantity| quantity <= vehicle_routes[day][:capacity_left][need] } ||
         !@same_point_day && @services_data[id][:capacity].all?{ |need, quantity| quantity <= vehicle_routes[day][:capacity_left][need] }
        cost = find_best_index(id, vehicle_routes[day])
      end
      index += 1
    end

    [day, cost]
  end

  def find_best_cost(id, vehicle_id)
    available_days = days_respecting_lapse(id, vehicle_id)
    find_best_day_cost(available_days, @candidate_routes[vehicle_id], id)
  end

  def compute_first_costs
    costs = {}

    @missing_visits.collect{ |vehicle, list|
      list.collect{ |service_id|
        day, cost = find_best_cost(service_id, vehicle)

        next if cost.nil?

        costs[service_id] = {
          day: day,
          vehicle: vehicle,
          cost: cost
        }
      }
    }

    costs
  end

  #### CORRECT UNDERFILLED ROUTES PROCESS ####

  def correct_underfilled_routes
    @output_tool&.add_comment('EMPTY_UNDERFILLED_ROUTES_PHASE')

    removed = empty_underfilled
    return if removed.empty?

    @output_tool&.add_comment('REAFFECT_FROM_UNDERFILLED_ROUTES_PHASE')

    firstly_unassigned = removed.collect(&:first)
    still_removed = reaffect(removed)

    still_removed += empty_underfilled unless @allow_partial_assignment
    if @allow_partial_assignment && firstly_unassigned.sort == still_removed.collect(&:first).sort
      log 'Reaffection with allow_partial_assignment false was pointless', level: :warn
    elsif @allow_partial_assignment
      log 'Reaffection with allow_partial_assignment false was usefull', level: :warn
    end

    reaffect_visits_number
  end

  def empty_underfilled
    removed = []
    loop do
      smth_removed = false
      all_empty = true

      @candidate_routes.each{ |vehicle, all_routes|
        all_routes.each{ |day, route_data|
          next if route_data[:stops].empty?

          all_empty = false

          next if route_data[:stops].sum{ |stop| @services_data[stop[:id]][:raw].exclusion_cost || 0 } >= route_data[:cost_fixed]

          smth_removed = true
          locally_removed = route_data[:stops].collect{ |stop|
            @services_data[stop[:id]][:used_days].delete(day)
            @output_tool&.remove_visits([day], @services_data[stop[:id]][:used_days], stop[:id], @services_data[stop[:id]][:raw].visits_number)
            [stop[:id], stop[:number_in_sequence]]
          }
          route_data[:stops] = []
          route_data[:capacity].each{ |unit, qty|
            route_data[:capacity_left][unit] = qty
          }
          removed += locally_removed

          if @allow_partial_assignment
            locally_removed.each{ |removed_id, number_in_sequence|
              @uninserted["#{removed_id}_#{number_in_sequence}_#{@services_data[removed_id][:raw].visits_number}"] = {
                original_id: removed_id,
                reason: 'Unaffected because route was underfilled'
              }
            }
          else
            locally_removed.each{ |removed_id, _number_in_sequence|
              clean_stops(removed_id, vehicle, false)
              (1..@services_data[removed_id][:raw].visits_number).each{ |visit|
                uninserted_id = "#{removed_id}_#{visit}_#{@services_data[removed_id][:raw].visits_number}"
                @uninserted[uninserted_id][:reason] = 'Unaffected because route was underfilled'

                next if visit == 1

                removed << [removed_id, visit]
              }
            }
          end
        }
      }

      break if all_empty || !smth_removed
    end

    compute_latest_authorized
    removed
  end

  def reaffect(still_removed)
    if @allow_partial_assignment
      still_removed = reaffect_in_non_empty_route(still_removed)
      still_removed = generate_new_routes(still_removed)
    else
      still_removed = reaffect_prohibiting_partial_assignment(still_removed)
    end

    still_removed
  end

  def reaffect_in_non_empty_route(still_removed)
    need_to_stop = false
    until still_removed.empty? || need_to_stop
      remaining_ids = still_removed.collect(&:first).uniq
      referent_route = nil
      insertion_costs = @candidate_routes.collect{ |vehicle_id, all_routes|
        all_routes.collect{ |day, route_data|
          if route_data[:stops].empty?
            []
          else
            referent_route ||= route_data
            insertion_costs = compute_costs_for_route(route_data, remaining_ids)
            insertion_costs.each{ |cost|
              cost[:vehicle] = vehicle
              cost[:day] = day
            }
            insertion_costs
          end
        }
      }

      if insertion_costs.flatten.empty?
        need_to_stop = true
      else
        acceptable_costs = insertion_costs.flatten.group_by{ |cost| cost[:id] }.collect{ |id, set|
          # keep insertion cost that minimizes lapse with its other visits
          if @services_data[id][:used_days].empty?
            set.first
          else
            set.min_by{ |cost| @services_data[id][:used_days].collect{ |day| (day - cost[:day]).abs }.min }
          end
        }
        point_to_add = select_point(acceptable_costs, referent_route)
        @ids_to_renumber |= [point_to_add[:id]]
        insert_point_in_route(@candidate_routes[point_to_add[:vehicle]][point_to_add[:day]], point_to_add, false)
        @output_tool&.add_single_visit(point_to_add[:day], @services_data[point_to_add[:id]][:used_days], point_to_add[:id], @services_data[point_to_add[:id]][:raw].visits_number)
        still_removed.delete(still_removed.find{ |removed| removed.first == point_to_add[:id] })
        @uninserted.delete(@uninserted.find{ |_id, data| data[:original_id] == to_plan[:service] }[0])
      end
    end

    still_removed
  end

  def collect_empty_routes
    @candidate_routes.each_with_object([]){ |routes_data, empty_routes|
      vehicle_id, all_routes = routes_data
      all_routes.select{ |_day, route_data| route_data[:stops].empty? }.each{ |day, route_data|
        empty_routes << {
          vehicle_id: vehicle_id,
          day: day,
          stores: [route_data[:start_point_id], route_data[:end_point_id]],
          time_range: route_data[:tw_end] - route_data[:tw_start]
        }
      }
    }
  end

  def chose_best_route(empty_routes, still_removed)
    # prefer closer vehicles
    closer_vehicles = empty_routes.group_by{ |empty_route_data|
      divider = 0
      average_distance_to_removed = still_removed.sum{ |id, _nb_in_sq|
        @services_data[id][:points_ids].sum{ |point_id|
          divider += empty_route_data[:stores].size
          empty_route_data[:stores].sum{ |store|
            matrix(@candidate_routes[@candidate_routes.keys.first].first[1], store, point_id)
          }
        }
      }.to_f / divider

      average_distance_to_removed
    }.min_by{ |key, _set| key }[1]

    # prefer vehicles with big timewindows
    big_time_range_vehicles = closer_vehicles.group_by{ |empty_route_data|
      empty_route_data[:time_range]
    }.max_by{ |key, _set| key }[1]

    # prefer vehicle with more empty days already, in order to balance work load among vehicles
    # for now, avoid using a vehicle that was not used at all until now
    to_consider_routes = big_time_range_vehicles.group_by{ |tab| tab[:vehicle_id] }.max_by{ |vehicle_id, _set|
      if @candidate_routes[vehicle_id].all?{ |_day, day_data| day_data[:stops].empty? }
        0
      else
        @candidate_routes[vehicle_id].count{ |_day, day_data| day_data[:stops].empty? }
      end
    }

    to_consider_routes[1].min_by{ |empty_route_data| empty_route_data[:day] } # start as soon as possible to maximize number of visits we can assign allong period
  end

  def generate_new_routes(still_removed)
    empty_routes = collect_empty_routes

    previous_vehicle_filled_info = nil
    previous_was_filled = false
    until still_removed.empty? || empty_routes.empty?
      best_route = chose_best_route(empty_routes, still_removed)
      vehicle_info = {
        stores: best_route[:stores],
        time_range: best_route[:time_range]
      }

      ### fill ###
      if previous_vehicle_filled_info != vehicle_info || previous_was_filled
        route_data = @candidate_routes[best_route[:vehicle_id]][best_route[:day]]
        keep_inserting = true
        inserted = []
        while keep_inserting
          insertion_costs = compute_costs_for_route(route_data, still_removed.collect(&:first).uniq - inserted)

          if insertion_costs.flatten.empty?
            keep_inserting = false
            empty_routes.delete_if{ |tab| tab[:vehicle_id] == best_route[:vehicle_id] && tab[:day] == best_route[:day] }
            if route_data[:stops].empty? || route_data[:stops].sum{ |stop| @services_data[stop[:id]][:raw].exclusion_cost || 0 } < route_data[:cost_fixed]
              route_data[:stops] = []
              previous_vehicle_filled_info = {
                stores: best_route[:stores],
                time_range: best_route[:time_range]
              }
            else
              previous_was_filled = true
              route_data[:stops].each{ |stop|
                @ids_to_renumber |= [stop[:id]]
                still_removed.delete(still_removed.find{ |removed| removed.first == stop[:id] })
                @output_tool&.add_single_visit(route_data[:global_day_index], @services_data[stop[:id]][:used_days], stop[:id], @services_data[stop[:id]][:raw].visits_number)
                @uninserted.delete(@uninserted.find{ |_id, data| data[:original_id] == stop[:id] }[0])
              }
            end
          else
            point_to_add = select_point(insertion_costs, route_data)
            inserted << point_to_add[:id]
            insert_point_in_route(route_data, point_to_add, false)
          end
        end
      else
        empty_routes.delete_if{ |tab| tab[:vehicle_id] == best_route[:vehicle_id] && tab[:day] == best_route[:day] }
      end
    end

    still_removed
  end

  def reaffect_prohibiting_partial_assignment(still_removed)
    # allow any day to assign visits
    @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, route_data| route_data[:available_ids] = @services_data.keys } }

    banned = []
    adapted_still_removed = still_removed.uniq{ |id, _visit| [id, @services_data[id][:raw].visits_number] }
    most_prioritary = adapted_still_removed.group_by{ |removed| @services_data[removed.first][:raw].priority }.min_by{ |priority, _set| priority }[1]
    most_prio_and_frequent = most_prioritary.group_by{ |removed| removed[1] }.max_by{ |visits_number, _set| visits_number }[1]
    until most_prio_and_frequent.empty?
      potential_costs = most_prio_and_frequent.collect{ |_| {} }
      @candidate_routes.each{ |vehicle_id, all_routes|
        all_routes.each{ |day, route_data|
          most_prio_and_frequent.each_with_index{ |service, s_i|
            potential_costs[s_i][vehicle_id] ||= {}

            cost = compute_costs_for_route(route_data, [service[0]]).first
            potential_costs[s_i][vehicle_id][day] = cost
          }
        }
      }

      available_sequences = []
      most_prio_and_frequent.collect.with_index{ |service_data, s_i|
        id, visits_number = service_data
        potential_costs[s_i].each{ |vehicle_id, data|
          available_days = data.reject{ |_key, cost| cost.nil? }.keys
          these_sequences = deduce_sequences(id, visits_number, available_days)

          available_sequences += these_sequences.collect{ |seq|
            cost = seq.collect{ |d| potential_costs[s_i][vehicle_id][d][:additional_route_time] }.sum
            { vehicle: vehicle_id, service: id, s_i: s_i, seq: seq, cost: cost }
          }
        }
      }

      sequences = available_sequences.select{ |sequence| !sequence[:seq].empty? && sequence[:seq].none?{ |day| @candidate_routes[sequence[:vehicle]][day][:stops].empty? } }
      if sequences.empty? && !available_sequences.empty?
        allowed_non_empty_sequences = available_sequences.reject{ |sequence|
          sequence[:seq].empty? ||
            sequence[:seq].count{ |day| @candidate_routes[sequence[:vehicle]][day][:stops].empty? } > @services_data[sequence[:service]][:raw].visits_number / 3.0
        }

        sequences = if allowed_non_empty_sequences.empty?
          []
        else
          allowed_non_empty_sequences.group_by{ |sequence|
            sequence[:seq].count{ |day| @candidate_routes[sequence[:vehicle]][day][:stops].empty? }
          }.min_by{ |nb_empty, _set| nb_empty }[1]
        end
      end

      if sequences.empty?
        banned |= most_prio_and_frequent.collect{ |p_a_f| p_a_f }
        most_prio_and_frequent = []
      else
        to_plan = sequences.min_by{ |sequence| sequence[:cost] }
        @ids_to_renumber |= [to_plan[:service]]
        to_plan[:seq].each{ |day|
          insert_point_in_route(@candidate_routes[to_plan[:vehicle]][day], potential_costs[to_plan[:s_i]][to_plan[:vehicle]][day], false)
        }
        @output_tool&.insert_visits(@services_data[to_plan[:service]][:used_days], to_plan[:service], @services_data[to_plan[:service]][:visits_number])

        most_prio_and_frequent.delete_if{ |service| service.first == to_plan[:service] }
        adapted_still_removed.delete_if{ |service| service.first == to_plan[:service] }
        still_removed.delete_if{ |service| service.first == to_plan[:service] }
        @uninserted.delete_if{ |_id, data| data[:original_id] == to_plan[:service] }
      end

      break if adapted_still_removed.empty? || (adapted_still_removed - banned).empty?

      while most_prio_and_frequent.empty?
        most_prioritary = (adapted_still_removed - banned).group_by{ |removed| @services_data[removed.first][:raw].priority }.min_by{ |priority, _set| priority }[1]
        most_prio_and_frequent = most_prioritary.group_by{ |removed| removed[1] }.max_by{ |visits_number, _set| visits_number }[1]
      end
    end

    # restaure right days to insert
    compute_latest_authorized
    still_removed
  end

  def deduce_sequences(id, visits_number, days)
    sequences = []

    return days.collect{ |day| [day] } if visits_number == 1

    days.sort.each_with_index{ |first_day, day_index|
      available_days = days.slice(days.find_index(first_day)..-1)
      break if available_days.size < visits_number

      sequences += find_sequences_from(days.slice(day_index + 1..-1), visits_number - 1, @services_data[id][:raw].minimum_lapse, @services_data[id][:raw].maximum_lapse, [first_day])
    }

    sequences
  end

  def find_sequences_from(days, visits_left, min_lapse, max_lapse, current_sequence)
    return current_sequence if visits_left.zero?

    next_days = collect_next_days(days, current_sequence.last, min_lapse, max_lapse)

    return [] if next_days.empty? # unvalid sequences will be ignored

    collected = next_days.collect{ |day|
      c = find_sequences_from(days.slice(days.find_index(day) + 1..-1), visits_left - 1, min_lapse, max_lapse, current_sequence + [day])
      c
    }

    collected = collected.first while collected.first.is_a?(Array) && collected.first.first.is_a?(Array)

    collected
  end

  def collect_next_days(all_days, last_day, min_lapse, max_lapse)
    all_days.select{ |day|
      day >= last_day + min_lapse &&
        day <= last_day + max_lapse
    }
  end
end
