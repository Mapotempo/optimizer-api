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
require './models/solution/solution_details'

module Models
  class Solution < Base
    field :name
    field :status
    field :cost, default: 0
    field :elapsed, default: 0
    field :heuristic_synthesis, default: []
    field :iterations
    field :solvers, default: []

    has_many :routes, class_name: 'Models::SolutionRoute'
    has_many :unassigned, class_name: 'Models::RouteActivity'

    belongs_to :cost_details, class_name: 'Models::CostDetails'
    belongs_to :details, class_name: 'Models::SolutionDetails'
    belongs_to :configuration, class_name: 'Models::SolutionConfiguration'

    def initialize(options = {})
      super(options)
      self.details = Models::SolutionDetails.new({}) unless options.key? :details
      self.cost_details = Models::CostDetails.new({}) unless options.key? :cost_details
      self.configuration = Models::SolutionConfiguration.new({}) unless options.key? :configuration
    end

    def as_json(options = {})
      hash = super(options)
      hash.delete('details')
      hash.merge(details.as_json(options))
    end

    def parse_solution(vrp, options = {})
      tic_parse_result = Time.now
      vrp.vehicles.each{ |vehicle|
        route = routes.find{ |r| r.vehicle.id == vehicle.id }
        # there should be one route per vehicle in solution :
        unless route
          route = vrp.empty_route(vehicle)
          routes << route
        end
        matrix = vrp.matrices.find{ |mat| mat.id == vehicle.matrix_id }
        route.fill_missing_route_data(vrp, matrix, options)
      }
      compute_result_total_dimensions_and_round_route_stats
      self.cost_details = routes.map(&:cost_details).reduce(&:+)

      log "solution - unassigned rate: #{unassigned.size} of (ser: #{vrp.visits} (#{(unassigned.size.to_f / vrp.visits * 100).round(1)}%)"
      used_vehicle_count = routes.count{ |r| r.activities.any?{ |a| a.service_id } }
      log "result - #{used_vehicle_count}/#{vrp.vehicles.size}(limit: #{vrp.resolution_vehicle_limit}) vehicles used: #{used_vehicle_count}"
      log "<---- parse_result elapsed: #{Time.now - tic_parse_result}sec", level: :debug
      self
    end

    def compute_result_total_dimensions_and_round_route_stats
      %i[total_time total_travel_time total_travel_value total_distance total_waiting_time].each{ |stat_symbol|
        next unless routes.all?{ |r| r.detail.send stat_symbol }

        details.send("#{stat_symbol}=", routes.collect{ |r|
          r.detail.send(stat_symbol)
        }.reduce(:+))
      }
    end

    def count_assigned_services
      routes.sum(&:count_services)
    end

    def count_unassigned_services
      unassigned.count(&:service_id)
    end

    def count_used_routes
      routes.count{ |route| route.count_services.positive? }
    end

    def +(other)
      solution = Solution.new({})
      solution.cost = self.cost + other.cost
      solution.elapsed = self.elapsed + other.elapsed
      solution.heuristic_synthesis = self.heuristic_synthesis + other.heuristic_synthesis
      solution.solvers = self.solvers + other.solvers
      solution.routes = self.routes + other.routes
      solution.unassigned = self.unassigned + other.unassigned
      solution.cost_details = self.cost_details + other.cost_details
      solution.details = self.details + other.details
      solution
    end
  end
end
