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

module PeriodicEndPhase
  extend ActiveSupport::Concern

  def refine_solution(&block)
    if @allow_partial_assignment && !@same_point_day && !@relaxed_same_point_day
      block&.call(nil, nil, nil, 'periodic heuristic - adding missing visits', nil, nil, nil)
      add_missing_visits
    end

    unless @services_data.all?{ |_id, data| data[:raw].exclusion_cost.to_f.zero? }
      block&.call(nil, nil, nil, 'periodic heuristic - correcting poorly populated routes', nil, nil, nil)
      correct_poorly_populated_routes
    end
  end

  def days_respecting_lapse(id, vehicle_routes)
    min_lapse = @services_data[id][:raw].minimum_lapse
    max_lapse = @services_data[id][:raw].maximum_lapse
    used_days = @services_assignment[id][:days]

    return vehicle_routes.keys if used_days.empty?

    vehicle_routes.keys.select{ |day|
      smaller_lapse_with_other_days = used_days.collect{ |used_day| (used_day - day).abs }.min
      (min_lapse.nil? || smaller_lapse_with_other_days >= min_lapse) &&
        (max_lapse.nil? || smaller_lapse_with_other_days <= max_lapse)
    }.sort_by{ |day| used_days.collect{ |used_day| (used_day - day).abs }.min } # minimize generated lapse
  end

  private

  #### ADD MISSING VISITS PROCESS ####

  def add_missing_visits
    @output_tool&.add_comment('ADD_MISSING_VISITS_PHASE')

    costs = compute_first_costs # usage : cost[id] = best known cost until now

    until costs.empty?
      # select best visit to insert
      max_priority = costs.keys.collect{ |id| @services_data[id][:raw].priority + 1 }.max
      best_cost = costs.min_by{ |id, info| ((@services_data[id][:raw].priority.to_f + 1) / max_priority) * (info[:additional_route_time] / @services_data[id][:raw].visits_number**2) }

      id = best_cost[0]
      day = best_cost[1][:day]
      vehicle_id = best_cost[1][:vehicle]
      log "It is interesting to add #{id} at day #{day} on #{vehicle_id}", level: :debug

      insert_point_in_route(@candidate_routes[vehicle_id][day], best_cost[1])
      @output_tool&.add_single_visit(day, @services_assignment[id][:days], id, @services_data[id][:raw].visits_number)

      costs = update_costs(costs, best_cost)
    end
  end

  # Updates costs after insertion of inserted_id
  # Costs of inserted id should be updated : some days are no longer available because of lapses
  # Costs corresponding to this route should updated : they may not be assignable anymore
  def update_costs(costs, inserted_cost_data)
    # Update inserted_id costs
    inserted_id = inserted_cost_data[0]
    inserted_cost = inserted_cost_data[1]
    if @services_assignment[inserted_id][:missing_visits].positive?
      costs[inserted_id] = find_best_day_cost(@candidate_routes[inserted_cost[:vehicle]], inserted_id)
      costs.delete(inserted_id) unless costs[inserted_id]
    else
      costs.delete(inserted_id)
    end

    # Update costs on this route
    costs.each{ |id, info|
      next unless info &&
                  info[:day] == inserted_cost[:day] &&
                  info[:vehicle] == inserted_cost[:vehicle]

      costs[id] = find_best_day_cost(@candidate_routes[info[:vehicle]], id)
      costs.delete(id) unless costs[id]
    }

    costs
  end

  def find_best_vehicle_day_cost(id)
    @services_assignment[id][:vehicles].map{ |vehicle_id|
      find_best_day_cost(@candidate_routes[vehicle_id], id)
    }.compact.min_by{ |cost| cost[:additional_route_time] } # TODO : find fair comparison between empty and non empty routes
  end

  def find_best_day_cost(vehicle_routes, id)
    # FIXME : this function does not return best cost, but earliest day which have a cost
    available_days = days_respecting_lapse(id, vehicle_routes)

    return nil unless available_days.any?

    index = 0
    cost = nil
    while cost.nil? && index < available_days.size
      cost = find_best_index(id, vehicle_routes[available_days[index]], false)
      index += 1
    end

    cost
  end

  def compute_first_costs
    costs = {}

    @services_assignment.each{ |id, data|
      next unless data[:days].any? && data[:missing_visits].positive?

      # some visits could be assigned but not all of them
      # we can try to be less restrictive on the lapse we use
      # TODO : should we consider all IDs again, even if no visit was assigned?

      cost = find_best_vehicle_day_cost(id)
      costs[id] = cost if cost
    }

    costs
  end

  #### CORRECT POORLY POPULATED ROUTES PROCESS ####

  def correct_poorly_populated_routes
    @output_tool&.add_comment('REMOVE_POORLY_POPULATED_ROUTES PHASE')
    @still_removed = {}

    remove_poorly_populated_routes
    return if @still_removed.empty?

    @output_tool&.add_comment('REAFFECT_FROM_POORLY_POPULATED_ROUTES_PHASE')

    firstly_unassigned = @still_removed.dup
    reaffect_removed_visits

    remove_poorly_populated_routes unless @allow_partial_assignment
    if @allow_partial_assignment && firstly_unassigned == @still_removed
      log 'Reaffection with allow_partial_assignment false was pointless', level: :warn
    elsif @allow_partial_assignment
      log 'Reaffection with allow_partial_assignment false was usefull', level: :warn
    end
  end

  def empty_route(route_data)
    route_data[:stops] = []
    route_data[:capacity].each{ |unit, qty|
      route_data[:capacity_left][unit] = qty
    }
  end

  def reduce_removed(id)
    @still_removed[id] -= 1
    return unless @still_removed[id].zero?

    @still_removed.delete(id)
  end

  def remove_poorly_populated_routes
    loop do
      smth_removed = false
      all_empty = true

      @candidate_routes.each{ |_vehicle, all_routes|
        all_routes.each{ |day, route_data|
          next if route_data[:stops].empty?

          all_empty = false

          next if route_data[:stops].sum{ |stop|
                    @services_data[stop[:id]][:raw].exclusion_cost.to_f
                  } >= route_data[:cost_fixed]

          smth_removed = true
          localy_removed = Hash.new(0)
          route_data[:stops].each{ |stop|
            @services_assignment[stop[:id]][:days].delete(day)
            @services_assignment[stop[:id]][:vehicles] = [] unless @services_assignment[stop[:id]][:days].any?
            @services_assignment[stop[:id]][:missing_visits] += 1
            @services_assignment[stop[:id]][:unassigned_reasons] |= ['Corresponding route was poorly populated']
            @output_tool&.remove_visits([day], @services_assignment[stop[:id]][:days], stop[:id], @services_data[stop[:id]][:raw].visits_number)
            localy_removed[stop[:id]] += 1
          }
          empty_route(route_data)

          localy_removed.each{ |id, number_of_removed|
            @still_removed[id] ||= 0
            if @allow_partial_assignment
              @still_removed[id] += number_of_removed
            else
              clean_stops(id, false)
              @services_assignment[id][:missing_visits] = @services_data[id][:raw].visits_number
              @still_removed[id] = @services_data[id][:raw].visits_number
            end
          }
        }
      }

      break if all_empty || !smth_removed
    end

    compute_latest_authorized
  end

  def reaffect_removed_visits
    if @allow_partial_assignment
      reaffect_in_non_empty_route
      generate_new_routes
    else
      reaffect_prohibiting_partial_assignment
    end
  end

  def reaffect_in_non_empty_route
    need_to_stop = false
    until @still_removed.empty? || need_to_stop
      referent_route = nil
      insertion_costs = @candidate_routes.collect{ |vehicle_id, all_routes|
        all_routes.collect{ |day, route_data|
          if route_data[:stops].empty?
            []
          else
            referent_route ||= route_data
            insertion_costs = compute_costs_for_route(route_data, @still_removed.keys)
            insertion_costs.each{ |cost|
              cost[:vehicle] = vehicle_id
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
          if @services_assignment[id][:days].empty?
            set.first
          else
            set.min_by{ |cost| @services_assignment[id][:days].collect{ |day| (day - cost[:day]).abs }.min }
          end
        }
        point_to_add = select_point(acceptable_costs, referent_route)
        insert_point_in_route(@candidate_routes[point_to_add[:vehicle]][point_to_add[:day]], point_to_add, false)
        @output_tool&.add_single_visit(point_to_add[:day], @services_assignment[point_to_add[:id]][:days], point_to_add[:id], @services_data[point_to_add[:id]][:raw].visits_number)
        reduce_removed(point_to_add[:id])
      end
    end
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

  def chose_best_route(empty_routes, still_removed_ids)
    # prefer closer vehicles
    closer_vehicles = empty_routes.group_by{ |empty_route_data|
      divider = 0
      still_removed_ids.sum{ |id|
        @services_data[id][:points_ids].sum{ |point_id|
          divider += empty_route_data[:stores].size
          empty_route_data[:stores].sum{ |store|
            matrix(@candidate_routes[@candidate_routes.keys.first].first[1], store, point_id)
          }
        }
      }.to_f / divider
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

  def generate_new_routes
    empty_routes = collect_empty_routes

    previous_vehicle_filled_info = nil
    previous_was_filled = false
    until @still_removed.empty? || empty_routes.empty?
      best_route = chose_best_route(empty_routes, @still_removed.keys)
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
          insertion_costs = compute_costs_for_route(route_data, @still_removed.keys - inserted)

          if insertion_costs.flatten.empty?
            keep_inserting = false
            empty_routes.delete_if{ |tab| tab[:vehicle_id] == best_route[:vehicle_id] && tab[:day] == best_route[:day] }
            if route_data[:stops].empty? ||
               route_data[:stops].sum{ |stop| @services_data[stop[:id]][:raw].exclusion_cost.to_f } < route_data[:cost_fixed]
              route_data[:stops].each{ |stop| @services_assignment[stop[:id]][:missing_visits] += 1 }
              route_data[:stops] = []
              previous_vehicle_filled_info = {
                stores: best_route[:stores],
                time_range: best_route[:time_range]
              }
            else
              previous_was_filled = true
              route_data[:stops].each{ |stop|
                reduce_removed(stop[:id])
                @output_tool&.add_single_visit(route_data[:day], @services_assignment[stop[:id]][:days], stop[:id], @services_data[stop[:id]][:raw].visits_number)
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
  end

  def reaffect_prohibiting_partial_assignment
    # allow any day to assign visits
    @candidate_routes.each{ |_vehicle_id, all_routes| all_routes.each{ |_day, route_data| route_data[:available_ids] = @services_data.keys } }

    banned = []
    adapted_still_removed = @still_removed.uniq{ |id, _visit| [id, @services_data[id][:raw].visits_number] }
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
        to_plan[:seq].each{ |day|
          insert_point_in_route(@candidate_routes[to_plan[:vehicle]][day], potential_costs[to_plan[:s_i]][to_plan[:vehicle]][day], false)
        }
        @output_tool&.insert_visits(@services_assignment[to_plan[:service]][:days], to_plan[:service], @services_data[to_plan[:service]][:visits_number])

        most_prio_and_frequent.delete_if{ |service| service.first == to_plan[:service] }
        adapted_still_removed.delete_if{ |service| service.first == to_plan[:service] }
        @still_removed.delete(to_plan[:service])
        @services_assignment[to_plan[:service]][:missing_visits] = 0
        @services_assignment[to_plan[:service]][:unassigned_reasons] = []
      end

      break if adapted_still_removed.empty? || (adapted_still_removed - banned).empty?

      while most_prio_and_frequent.empty?
        most_prioritary = (adapted_still_removed - banned).group_by{ |removed| @services_data[removed.first][:raw].priority }.min_by{ |priority, _set| priority }[1]
        most_prio_and_frequent = most_prioritary.group_by{ |removed| removed[1] }.max_by{ |visits_number, _set| visits_number }[1]
      end
    end

    # restaure right days to insert
    compute_latest_authorized
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
