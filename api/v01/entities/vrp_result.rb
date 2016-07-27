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
    class VrpResultSolutionRouteActivities < Grape::Entity
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

    class VrpResultSolutionRoute < Grape::Entity
      expose :vehicle_id, documentation: { type: String, desc: '' }
      expose :activities, using: VrpResultSolutionRouteActivities, documentation: { is_array: true, desc: '' }
    end

    class VrpResultSolution < Grape::Entity
      expose :cost, documentation: { type: Float, desc: '' }
      expose :total_travel_distance, documentation: { type: Integer, desc: '' }
      expose :total_travel_time, documentation: { type: Integer, desc: '' }
      expose :total_waiting_time, documentation: { type: Integer, desc: '' }
      expose :start_time, documentation: { type: Integer, desc: '' }
      expose :end_time, documentation: { type: Integer, desc: '' }
      expose :routes, using: VrpResultSolutionRoute, documentation: { is_array: true, desc: '' }
    end

    class VrpResultJobGraphItem < Grape::Entity
      expose :iteration, documentation: { type: Integer, desc: 'Iteration number.' }
      expose :time, documentation: { type: Integer, desc: 'Time in ms since resolution begin.' }
      expose :cost, documentation: { type: Float, desc: 'Current best cost at this iteration.' }
    end

    class VrpResultJob < Grape::Entity
      expose :id, documentation: { type: String, desc: 'Job uniq ID' }
      expose :status, documentation: { type: String, desc: 'One of queued, working, completed, killed or failed.' }
      expose :avancement, documentation: { type: String, desc: 'Free form advancement message.' }
      expose :graph, using: VrpResultJobGraphItem, documentation: { is_array: true, desc: 'Items to plot cost evolution.' }
    end

    class VrpResult < Grape::Entity
      expose :solutions, using: VrpResultSolution, documentation: { is_array: true, desc: 'The current best solution.' }
      expose :job, using: VrpResultJob, documentation: { desc: 'The Job status.' }
    end
  end
end
