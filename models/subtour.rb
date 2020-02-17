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
require './models/base'

module Models
  class Subtour < Base
    field :time_bounds, default: nil
    field :distance_bounds, default: nil
    field :router_mode, default: :pedestrian
    field :router_dimension, default: :time
    field :speed_multiplier, default: 1
    field :skills, default: []
    field :duration, default: nil

    has_many :transmodal_stops, class_name: 'Models::Point'
    has_many :capacities, class_name: 'Models::Capacity'
  end
end
