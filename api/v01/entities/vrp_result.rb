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
#require './api/v01/entities/vrp_result_*'


module Api
  module V01
    class VrpResult < Grape::Entity
      def self.entity_name
        'VrpResult'
      end

      expose :solutions do
        expose :cost, documentation: { type: Float, desc: '' }
        expose :total_travel_distance, documentation: { type: Integer, desc: '' }
        expose :total_travel_time, documentation: { type: Integer, desc: '' }
        expose :total_waiting_time, documentation: { type: Integer, desc: '' }
        expose :start_time, documentation: { type: Integer, desc: '' }
        expose :end_time, documentation: { type: Integer, desc: '' }
        expose :routes, documentation: { desc: '' } do
          expose :vehicle_id, documentation: { type: String, desc: '' }
          expose :activities, documentation: { desc: '' } do
            expose :point_id, documentation: { type: String, desc: '' }
            expose :travel_distance, documentation: { type: Integer, desc: '' }
            expose :travel_start_time, documentation: { type: Integer, desc: '' }
            expose :waiting_duration, documentation: { type: Integer, desc: '' }
            expose :arrival_time, documentation: { type: Integer, desc: '' }
            expose :departure_time, documentation: { type: Integer, desc: '' }
            expose :service_id, documentation: { type: String, desc: '' }
            expose :pickup_shipment_id, documentation: { type: String, desc: '' }
            expose :delivery_shipment_id, documentation: { type: String, desc: '' }
          end
        end
      end

      expose :job do
        expose :id, documentation: { type: String, desc: 'Job uniq ID' }
        expose :status, documentation: { type: String, desc: 'One of queued, working, completed, killed or failed.' }
        expose :avancement, documentation: { type: String, desc: 'Free form advancement message.' }
        expose :graph do
          expose :iteration, documentation: { type: Integer, desc: 'Iteration number.' }
          expose :time, documentation: { type: Integer, desc: 'Time in ms since resolution begin.' }
          expose :cost, documentation: { type: Float, desc: 'Current best cost at this iteration.' }
        end
      end
    end
  end
end
