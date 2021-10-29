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
  class Timings < Base
    field :day_week_num
    field :day_week

    field :travel_distance, default: 0
    field :travel_time, default: 0
    field :travel_value, default: 0

    field :waiting_time, default: 0
    field :begin_time, default: 0
    field :end_time, default: 0
    field :departure_time, default: 0

    field :current_distance, default: 0
  end
end
