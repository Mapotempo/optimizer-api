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


module Api
  module V01
    class VrpRequestPoint < Grape::Entity
      def self.entity_name
        'VrpRequestPoint'
      end

      expose(:id, documentation: { type: String })
      expose(:matrix_index, documentation: { type: Integer })
      expose(:location) do
        expose(:lat, documentation: { type: Float })
        expose(:lon, documentation: { type: Float })
      end
    end
  end
end
