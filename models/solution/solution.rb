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

module Models
  class Solution < Base
    field :name
    field :status
    field :cost, default: 0
    field :elapsed, default: 0
    field :heuristic_synthesis, default: []
    field :iterations
    field :solvers, default: []

    has_many :routes, class_name: 'Models::Solution::Route'
    has_many :unassigned, class_name: 'Models::Solution::Stop'

    belongs_to :cost_info, class_name: 'Models::Solution::CostInfo'
    belongs_to :info, class_name: 'Models::Solution::Info', vrp_result: :hide
    belongs_to :configuration, class_name: 'Models::Solution::Configuration'

    def initialize(options = {})
      options = { info: {}, cost_info: {}, configuration: {} }.merge(options)
      super(options)
    end

    def vrp_result(options = {})
      hash = super(options)
      hash['cost'] = cost_info.total
      hash['cost_details'] = hash.delete('cost_info')
      hash.merge!(info.vrp_result(options))
      edit_route_days(hash)
      hash
    end

    def edit_route_days(hash)
      return unless self.configuration.schedule_start_date

      start_date = self.configuration.schedule_start_date
      hash['routes'].each{ |r|
        r['day'] = start_date + r['day'] - (start_date.cwday - 1)
      }
    end

    def parse(vrp, options = {})
      Parsers::SolutionParser.parse(self, vrp, options)
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
      solution.cost_info = self.cost_info + other.cost_info
      solution.info = self.info + other.info
      solution.configuration = self.configuration + other.configuration
      solution
    end

    def update_costs
      previous_total = cost_info.total
      # When there is only one route, the route cost_info object is shared with the solution cost_info
      return if routes.size <= 1

      cost_info = routes.map(&:cost_info).sum
      self.cost -= (previous_total - cost_info.total).round
    end

    def insert_stop(vrp, route, stop, index, idle_time = 0)
      route.insert_stop(vrp, stop, index, idle_time)
      Parsers::SolutionParser.parse(self, vrp)
    end
  end
end
