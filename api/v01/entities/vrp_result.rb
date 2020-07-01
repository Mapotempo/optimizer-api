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
# require './api/v01/entities/vrp_result_*'

module Api
  module V01
    class VrpResultSolutionRouteActivityDetailTimewindows < Grape::Entity
      expose :start, documentation: { type: Integer, desc: '' }
      expose :end, documentation: { type: Integer, desc: '' }
    end

    class VrpResultDetailQuantities < Grape::Entity
      expose :unit, documentation: { type: String, desc: '' }
      expose :value, documentation: { type: Float, desc: '' }
      expose :setup_value, documentation: { type: Float, desc: '' }
      expose :current_load, documentation: { type: Float, desc: '' }
    end

    class VrpResultSolutionRouteActivityDetails < Grape::Entity
      expose :router_mode, documentation: { type: String, desc: 'Means of transport used to reach this activity, it may vary within a route if subtours are defined' }
      expose :speed_multiplier, documentation: { type: String, desc: 'Speed multiplier applied to the current means of transport, it may vary within a route if subtours are defined' }
      expose :lat, documentation: { type: Float, desc: '' }
      expose :lon, documentation: { type: Float, desc: '' }
      expose :skills, documentation: { type: Array[String], desc: '' }
      expose :setup_duration, documentation: { type: Integer, desc: '' }
      expose :duration, documentation: { type: Integer, desc: '' }
      expose :additional_value, documentation: { type: Integer, desc: '' }
      expose :quantities, using: VrpResultDetailQuantities, documentation: { is_array: true, desc: '' }
      expose :timewindows, using: VrpResultSolutionRouteActivityDetailTimewindows, documentation: { is_array: true, desc: '' }
    end

    class VRPResultSolutionRouteCosts < Grape::Entity
      expose :fixed, documentation: { type: String, desc: 'Cost associated to the use of the vehicle' }
      expose :time, documentation: { type: String, desc: 'Cost associated to the time dimension' }
      expose :distance, documentation: { type: String, desc: 'Cost associated to the distance dimension' }
      expose :value, documentation: { type: String, desc: 'Cost associated to the value dimension' }
    end

    class VrpResultSolutionRouteActivities < Grape::Entity
      expose :point_id, documentation: { type: String, desc: 'Linked spatial point' }
      expose :travel_distance, documentation: { type: Integer, desc: 'travel distance from the previous point' }
      expose :travel_duration, documentation: { type: Integer, desc: 'travel time from the previous point' }
      expose :waiting_duration, documentation: { type: Integer, desc: '' }
      expose :arrival_time, documentation: { type: Integer, desc: '' }
      expose :departure_time, documentation: { type: Integer, desc: '' }
      expose :service_id, documentation: { type: String, desc: '' }
      expose :pickup_shipment_id, documentation: { type: String, desc: '' }
      expose :delivery_shipment_id, documentation: { type: String, desc: '' }
      expose :detail, using: VrpResultSolutionRouteActivityDetails, documentation: { desc: '' }
    end

    class VrpResultSolutionRoute < Grape::Entity
      expose :vehicle_id, documentation: { type: String, desc: 'Reference of the vehicule used for the current route' }
      expose :activities, using: VrpResultSolutionRouteActivities, documentation: { is_array: true, desc: 'Every step of the route' }
      expose :total_distance, documentation: { type: Integer, desc: 'Sum of every distance within the route' }
      expose :total_time, documentation: { type: Integer, desc: 'Sum of every travel time and activity duration of the route' }
      expose :start_time, documentation: { type: Integer, desc: 'Give the actual start time of the current route if provided by the solve' }
      expose :end_time, documentation: { type: Integer, desc: 'Give the actual end time of the current route if provided by the solver' }
      expose :geometry, documentation: { type: String, desc: 'Contains the geometry of the route, if asked in first place' }
      expose :initial_loads, using: VrpResultDetailQuantities, documentation: { is_array: true, desc: 'Give the actual initial loads of the route' }
      expose :costs, using: VRPResultSolutionRouteCosts, documentation: { desc: 'The impact of the current route within the solution cost' }
    end

    class VrpResultSolutionUnassigneds < Grape::Entity
      expose :point_id, documentation: { type: String, desc: 'Linked spatial point' }
      expose :service_id, documentation: { type: String, desc: '' }
      expose :pickup_shipment_id, documentation: { type: String, desc: '' }
      expose :delivery_shipment_id, documentation: { type: String, desc: '' }
      expose :detail, using: VrpResultSolutionRouteActivityDetails, documentation: { desc: '' }
    end

    class VrpResultSolution < Grape::Entity
      expose :heuristics_synthesis, documentation: { type: Hash, desc: 'When first_solution_strategies are provided, sum up of tryied heuristics and their performance.' }
      expose :solvers, documentation: { is_array: true, type: String, desc: 'Solvers used to perform the optimization' }
      expose :cost, documentation: { type: Float, desc: 'The actual cost of the solution considering all costs' }
      expose :iterations, documentation: { type: Integer, desc: 'Total number of iteration performed to obtain the current result' }
      expose :total_distance, documentation: { type: Integer, desc: 'cumulated distance of every route' }
      expose :total_time, documentation: { type: Integer, desc: 'Cumulated time of every route' }
      expose :start_time, documentation: { type: Integer, desc: '' }
      expose :end_time, documentation: { type: Integer, desc: '' }
      expose :routes, using: VrpResultSolutionRoute, documentation: { is_array: true, desc: 'All the route calculated' }
      expose :unassigned, using: VrpResultSolutionUnassigneds, documentation: { is_array: true, desc: 'Jobs which are not part of the solution' }
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

    class VrpJobsList < Grape::Entity
      expose :jobs, using: VrpResultJob, documentation: { is_array: true, desc: 'The Jobs.' }
    end
  end
end
