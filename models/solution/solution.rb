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
    field :cost, default: 0
    field :elapsed, default: 0
    field :heuristic_synthesis, default: {}
    field :iterations
    field :solvers, default: []

    has_many :routes, class_name: 'Models::SolutionRoute'
    has_many :unassigned, class_name: 'Models::RouteActivity'

    belongs_to :costs, class_name: 'Models::CostDetails'
    belongs_to :details, class_name: 'Models::RouteDetails'
  end
end
