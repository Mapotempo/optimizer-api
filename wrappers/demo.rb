# Copyright © Mapotempo, 2016
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
require './wrappers/wrapper'

module Wrappers
  class Demo < Wrapper
    def initialize(hash = {})
      super(hash)
    end

    def solve(vrp, _job = nil, _thread_proc = nil, &_block)
      routes = vrp.vehicles.map{ |vehicle|
        stops = [vehicle.start_point && Models::Solution::StopDepot.new(vehicle.start_point)] +
                vrp.services.map{ |service|
                  Models::Solution::Stop.new(service, index: service.activities.any? && 0)
                } + [vehicle.end_point && Models::Solution::StopDepot.new(vehicle.end_point)]
        Models::Solution::Route.new(
          vehicle: vehicle,
          stops: stops.compact
        )
      }
      solution = Models::Solution.new(
        solvers: [:demo],
        routes: routes
      )

      solution.parse(vrp, compute_dimensions: true)
    end
  end
end
