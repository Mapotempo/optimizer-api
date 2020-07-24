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
  class Costs < Base
      field :total, default: 0
      field :fixed, default: 0
      field :time, default: 0
      field :distance, default: 0
      field :value, default: 0
      field :lateness, default: 0
      field :overload, default: 0

      def +(other)
        merged_cost = Costs.new({})
        self.attributes.keys.each{ |key|
          merged_cost[key] = (self[key] || 0) + (other[key] || 0)
        }
        merged_cost
      end
  end
end
