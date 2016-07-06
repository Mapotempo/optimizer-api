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
    class VrpRequestVehicle < Grape::Entity
      def self.entity_name
        'VrpRequestVehicle'
      end

      expose(:cost) do
        expose(:fixed, documentation: { type: Float })
        expose(:distance_multiplier, documentation: { type: Float })
        expose(:time_multiplier, documentation: { type: Float })
        expose(:waiting_time_multiplier, documentation: { type: Float })
        expose(:late_multiplier, documentation: { type: Float })
        expose(:setup_time_multiplier, documentation: { type: Float })
        expose(:setup, documentation: { type: Float })
      end

      expose(:router_mode, documentation: { type: String })
      expose(:router_dimension, documentation: { type: String, values: [:time, :distance] })
      expose(:speed_multiplier, documentation: { type: Float })
      expose(:duration, documentation: { type: Float })
      expose(:skills, documentation: { type: Array[String] })

      expose(:start_point_id, documentation: { type: String })
      expose(:end_point_id, documentation: { type: String })
      expose(:quantities, documentation: { type: Array[Array[String]] })
      expose(:timewindows, using: Api::V01::VrpRequestTimewindow, documentation: { type: Api::V01::VrpRequestTimewindow })
      expose(:rest_ids, documentation: { type: Array[String] })
    end
  end
end
