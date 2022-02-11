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
    class Info < Base
      field :total_time, default: 0
      field :total_travel_time, default: 0
      field :total_waiting_time, default: 0

      field :total_distance, default: 0

      field :total_travel_value

      def +(other)
        merged_details = Info.new({})
        self.attributes.each_key{ |key|
          merged_details[key] = (self[key] || 0) + (other[key] || 0)
        }
        merged_details
      end
    end
  end
end
