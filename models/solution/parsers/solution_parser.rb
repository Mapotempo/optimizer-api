# Copyright © Mapotempo, 2021
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
require './models/base'

module Parsers
  class SolutionParser
    def self.parse(solution, vrp, options = {})
      tic_parse_result = Time.now
      vrp.vehicles.each{ |vehicle|
        route = solution.routes.find{ |r| r.vehicle.id == vehicle.id }
        # there should be one route per vehicle in solution :
        unless route
          route = vrp.empty_route(vehicle)
          solution.routes << route
        end
        matrix = vrp.matrices.find{ |mat| mat.id == vehicle.matrix_id }
        Parsers::RouteParser.parse(route, vrp, matrix, options)
      }
      compute_result_total_dimensions_and_round_route_stats(solution)
      solution.cost_info = solution.routes.map(&:cost_info).reduce(&:+) ||
                           Models::Solution::CostInfo.new({})
      solution.configuration.geometry = vrp.restitution_geometry
      solution.configuration.schedule_start_date = vrp.schedule_start_date

      log "solution - unassigned rate: #{solution.unassigned.size} of (ser: #{vrp.visits} " \
          "(#{(solution.unassigned.size.to_f / vrp.visits * 100).round(1)}%)"
      used_vehicle_count = solution.routes.count{ |r| r.stops.any?(&:service_id) }
      log "result - #{used_vehicle_count}/#{vrp.vehicles.size}(limit: #{vrp.resolution_vehicle_limit}) " \
          "vehicles used: #{used_vehicle_count}"
      log "<---- parse_result elapsed: #{Time.now - tic_parse_result}sec", level: :debug
      solution
    end

    def self.compute_result_total_dimensions_and_round_route_stats(solution)
      %i[total_time total_travel_time total_travel_value total_distance total_waiting_time].each{ |stat_symbol|
        next if solution.routes.none?{ |r| r.info.send stat_symbol }

        solution.info.send("#{stat_symbol}=", solution.routes.collect{ |r|
          r.info.send(stat_symbol)
        }.compact.reduce(:+))
      }
    end
  end
end
