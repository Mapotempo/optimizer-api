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
require './api/v01/entities/vrp_request_timewindow'


module Api
  module V01
    class VrpRequestActivity < Grape::Entity
      def self.entity_name
        'VrpRequestActivity'
      end

      expose(:duration, documentation: { type: Float })
      expose(:setup_duration, documentation: { type: Float })
      expose(:point_id, documentation: { type: String })
      expose(:timewindows, using: Api::V01::VrpRequestTimewindow, documentation: { type: Api::V01::VrpRequestTimewindow })
    end
  end
end
