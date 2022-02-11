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
    class Configuration < Base
      field :csv, default: false
      field :geometry, default: false
      field :deprecated_headers, default: false
      field :schedule_start_date

      def +(other)
        Configuration.create(
          csv: csv || other.csv,
          geometry: (geometry + other.geometry).uniq,
          deprecated_headers: deprecated_headers || other.deprecated_headers,
          schedule_start_date: schedule_start_date
        )
      end
    end
  end
end
