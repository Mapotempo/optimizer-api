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
  class SolutionRoute < Base
    field :geometry

    has_many :activities, class_name: 'Models::RouteActivity'
    has_many :initial_loads, class_name: 'Models::Load'

    belongs_to :cost_details, class_name: 'Models::CostDetails'
    belongs_to :details, class_name: 'Models::RouteDetails'
    belongs_to :vehicle, class_name: 'Models::Vehicle'
  end
end
