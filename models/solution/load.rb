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
    class Load < Base
      field :current, default: 0, vrp_result: :hide

      belongs_to :quantity, class_name: 'Models::Quantity', vrp_result: :hide

      def vrp_result(options = {})
        hash = super(options)
        hash['unit'] = quantity.unit_id
        hash['label'] = quantity.unit.label
        hash['value'] = quantity.value&.round(3)
        hash['setup_value'] = quantity.setup_value if quantity.unit.counting
        hash['current_load'] = current&.round(3)
        hash
      end
    end
  end
end
