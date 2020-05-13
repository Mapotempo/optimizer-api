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

  def add_missing_visits
    found = {}
    costs = compute_first_costs # usage : cost[id] = best known cost until now

    until costs.empty?
      # select best visit to insert
      max_priority = costs.keys.collect{ |id| @services_data[id][:priority] + 1 }.max
      best_cost = costs.min_by{ |id, info| ((@services_data[id][:priority].to_f + 1) / max_priority) * (info[:cost][:additional_route_time] / @services_data[id][:visits_number]**2) }

      id = best_cost[0]
      day = best_cost[1][:day]
      vehicle = best_cost[1][:vehicle]
      log "It is interesting to add #{id} at day #{day} on #{vehicle}", level: :debug

      # insert in corresponding route
      if found[id]
        found[id] << [vehicle, day]
      else
        found[id] = [[vehicle, day]]
        @services_data[best_cost[0]][:used_days].each{ |assigned_day| found[id] << [vehicle, assigned_day] }
      end
      insert_point_in_route(@candidate_routes[vehicle][day], best_cost[1][:cost])
      @output_tool&.output_scheduling_insert([day], id)
      @services_data[id][:capacity].each{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] -= qty }
      @services_data[best_cost[0]][:used_days] << day

      costs = update_costs(costs, best_cost)
    end

    reaffect_visits_number(found)
  end

  def update_costs(costs, best_cost)
    # update costs for inserted id, available_days changed
    uninserted_set = @uninserted.keys.select{ |key| key.include?(best_cost[0] + '_') }
    @uninserted.delete(uninserted_set.first)
    if uninserted_set.size > 1
      available_days = available_days(best_cost[0], best_cost[1][:vehicle], @services_data[best_cost[0]][:used_days])

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

      day, cost = find_best_cost(id, info[:vehicle], @services_data[id][:used_days])

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

  def available_days(id, vehicle, used_days)
    min_lapse = @services_data[id][:minimum_lapse]
    max_lapse = @services_data[id][:maximum_lapse]
    available_days = @candidate_routes[vehicle].keys - used_days
    available_days.delete_if{ |day|
      smaller_lapse_with_other_days = used_days.collect{ |used_day| (used_day - day).abs }.min
      min_lapse && smaller_lapse_with_other_days < min_lapse ||
        max_lapse && smaller_lapse_with_other_days > max_lapse
    }.sort_by{ |day| used_days.collect{ |used_day| (used_day - day).abs }.min } # we minimize lapse generated
  end

  def find_best_cost(id, vehicle, used_days)
    available_days = available_days(id, vehicle, used_days)
    find_best_day_cost(available_days, @candidate_routes[vehicle], id)
  end

  def compute_first_costs
    costs = {}

    @missing_visits.collect{ |vehicle, list|
      list.collect{ |service_id|
        day, cost = find_best_cost(service_id, vehicle, @services_data[service_id][:used_days])

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

  def reaffect_visits_number(found)
    found.each{ |id, info|
      info.sort_by{ |_v_id, day| day }.each_with_index{ |occurence, current_visit|
        v_id, day = occurence
        @candidate_routes[v_id][day][:current_route].find{ |stop| stop[:id] == id }[:number_in_sequence] = current_visit + 1
      }
    }
  end
end
