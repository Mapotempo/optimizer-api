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
require './models/base'

module Models
  class Solution < Base
    class CostInfo < Base
      field :fixed, default: 0
      field :time, default: 0
      field :distance, default: 0
      field :value, default: 0
      field :lateness, default: 0
      field :overload, default: 0

      def total
        fixed + time + distance + value + lateness + overload
      end

      def +(other)
        CostInfo.create(
          fixed: fixed + other.fixed,
          time: time + other.time,
          distance: distance + other.distance,
          value: value + other.value,
          lateness: lateness + other.lateness,
          overload: overload + other.overload,
        )
      end
    end
  end
end
