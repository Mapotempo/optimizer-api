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
    class VrpResultSolutionRouteActivityDetailTimewindows < Grape::Entity
      expose :start, documentation: { type: Integer, desc: '' }
      expose :end, documentation: { type: Integer, desc: '' }
    end

    class VrpResultDetailQuantities < Grape::Entity
      expose :unit, documentation: { type: String, desc: '' }
      expose :label, documentation: { type: String, desc: '' }
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

    class VRPResultDetailedCosts < Grape::Entity
      expose :total, documentation: { type: Float, desc: 'Cumulated cost' }
      expose :fixed, documentation: { type: Float, desc: 'Cost associated to the use of the vehicle' }
      expose :time, documentation: { type: Float, desc: 'Cost associated to the time dimension' }
      expose :distance, documentation: { type: Float, desc: 'Cost associated to the distance dimension' }
      expose :value, documentation: { type: Float, desc: 'Cost associated to the value dimension' }
      expose :lateness, documentation: { type: Float, desc: 'Cost associated to late arrival' }
      expose :overload, documentation: { type: Float, desc: 'Cost associated to quantities overload' }
    end

    class VrpResultSolutionRouteActivities < Grape::Entity
      expose :day_week_num, expose_nil: false, documentation: { type: String, desc: '' }
      expose :day_week, expose_nil: false, documentation: { type: String, desc: '' }
      expose :point_id, documentation: { type: String, desc: 'Linked spatial point' }
      expose :travel_distance, documentation: { type: Integer, desc: 'Travel distance from previous point (in m)' }
      expose :travel_time, documentation: { type: Integer, desc: 'Travel time from previous point (in s)' }
      expose :travel_value, documentation: { type: Integer, desc: 'Travel value from previous point' }
      expose :waiting_time, documentation: { type: Integer, desc: 'Idle time (in s)' }
      expose :begin_time, documentation: { type: Integer, desc: 'Time visit starts' }
      expose :end_time, documentation: { type: Integer, desc: 'Time visit ends' }
      expose :departure_time, documentation: { type: Integer, desc: '' }
      expose :service_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the service' }
      expose :pickup_shipment_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the shipment' }
      expose :delivery_shipment_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the shipment' }
      expose :rest_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the rest' }
      expose :detail, using: VrpResultSolutionRouteActivityDetails, documentation: { desc: '' }
      expose :type, documentation: { type: String, desc: 'depot, rest, service, pickup or delivery' }
      expose :current_distance, documentation: { type: Integer, desc: 'Travel distance from route start to current point (in m)' }
      expose :alternative, documentation: { type: Integer, desc: 'When one service has alternative activities, index of the chosen one' }
      expose :visit_index, documentation: { type: Integer, desc: 'Index of the visit' }
    end

    class VrpResultSolutionRoute < Grape::Entity
      expose :day, documentation: { type: [Integer, Date],
                                    desc: 'Day index or date (if provided within schedule) where route takes place' }
      expose :vehicle_id, documentation: { type: String,
                                           desc: 'Internal reference of vehicule corresponding to this route' }
      expose :activities, using: VrpResultSolutionRouteActivities, documentation: { is_array: true, desc: 'Every step of the route' }
      expose :total_travel_time, documentation: { type: Integer, desc: 'Sum of every travel time within the route (in s)' }
      expose :total_distance, documentation: { type: Integer, desc: 'Sum of every distance within the route (in m)' }
      expose :total_time, documentation: { type: Integer, desc: 'Sum of every travel time and activity duration of the route (in s)' }
      expose :total_waiting_time, documentation: { type: Integer, desc: 'Sum of every idle time within the route (in s)' }
      expose :start_time, documentation: { type: Integer, desc: 'Give the actual start time of the current route if provided by the solve' }
      expose :end_time, documentation: { type: Integer, desc: 'Give the actual end time of the current route if provided by the solver' }
      expose :geometry, documentation: { type: String, desc: 'Contains the geometry of the route, if asked in first place' }
      expose :initial_loads, using: VrpResultDetailQuantities, documentation: { is_array: true, desc: 'Give the actual initial loads of the route' }
      expose :cost_details, using: VRPResultDetailedCosts, documentation: { desc: 'The impact of the current route within the solution cost' }
    end

    class VrpResultSolutionUnassigned < Grape::Entity
      expose :point_id, documentation: { type: String, desc: 'Linked spatial point' }
      expose :service_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the service' }
      expose :pickup_shipment_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the shipment' }
      expose :delivery_shipment_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the shipment' }
      expose :rest_id, expose_nil: false, documentation: { type: String, desc: 'Internal reference of the rest' }
      expose :detail, using: VrpResultSolutionRouteActivityDetails, documentation: { desc: '' }
      expose :type, documentation: { type: String, desc: 'depot, rest, service, pickup or delivery' }
      expose :reason, documentation: { type: String, desc: 'Unassigned reason. Only available when activity was rejected within preprocessing fase or periodic first_solution_strategy.' }
    end

    class VrpResultSolution < Grape::Entity
      expose :heuristic_synthesis, documentation: { type: Hash, desc: 'When first_solution_strategies are provided, sum up of tryied heuristics and their performance.' }
      expose :solvers, documentation: { is_array: true, type: String, desc: 'Solvers used to perform the optimization' }
      expose :cost, documentation: { type: Float, desc: 'The actual cost of the solution considering all costs' }
      expose :cost_details, using: VRPResultDetailedCosts, documentation: { desc: 'The detail of the different costs which impact the solution' }
      expose :iterations, documentation: { type: Integer, desc: 'Total number of iteration performed to obtain the current result' }
      expose :total_distance, documentation: { type: Integer, desc: 'cumulated distance of every route (in m)' }
      expose :total_time, documentation: { type: Integer, desc: 'Cumulated time of every route (in s)' }
      expose :total_travel_time, documentation: { type: Integer, desc: 'Cumulated travel time of every route (in s)' }
      expose :total_waiting_time, documentation: { type: Integer, desc: 'Cumulated idle time of every route (in s)' }
      expose :routes, using: VrpResultSolutionRoute, documentation: { is_array: true, desc: 'All the route calculated' }
      expose :unassigned, using: VrpResultSolutionUnassigned, documentation: { is_array: true, desc: 'Jobs which are not part of the solution' }
      expose :elapsed, documentation: { type: Integer, desc: 'Elapsed time within solver in ms' }
    end

    class VrpResultJobGraphItem < Grape::Entity
      expose :iteration, documentation: { type: Integer, desc: 'Iteration number' }
      expose :time, documentation: { type: Integer, desc: 'Time in ms since resolution begin' }
      expose :cost, documentation: { type: Float, desc: 'Current best cost at this iteration' }
    end

    class VrpResultJob < Grape::Entity
      expose :id, documentation: { type: String, desc: 'Job uniq ID' }
      expose :status, documentation: { type: String, desc: 'One of queued, working, completed, killed or failed' }
      expose :avancement, documentation: { type: String, desc: 'Free form advancement message' }
      expose :graph, using: VrpResultJobGraphItem, documentation: { is_array: true, desc: 'Items to plot cost evolution' }
    end

    class VrpResultVisualClusters < Grape::Entity
      expose :vehicle, expose_nil: false, documentation: { desc: 'Vehicle partition visual' }
      expose :work_day, expose_nil: false, documentation: { desc: 'Work_day partition visual' }
    end

    class VrpResultVisual < Grape::Entity
      expose :partitions, expose_nil: false, using: VrpResultVisualClusters, documentation: { desc: 'According to specified geometry and partitions parameter, geojsons representing each partition' }
      expose :points, expose_nil: false, documentation: { desc: 'Points visualization' }
      expose :polylines, expose_nil: false, documentation: { desc: 'Polylines visualization' }
    end

    class VrpResult < Grape::Entity
      expose :solutions, using: VrpResultSolution, documentation: { is_array: true, desc: 'The current best solution' }
      expose :geojsons, using: VrpResultVisual, documentation: { is_array: true, desc: 'If required through geometry VRP parameter, set of geojsons generated' }
      expose :job, using: VrpResultJob, documentation: { desc: 'The Job status' }
    end

    class VrpSyncJob < Grape::Entity
      expose :solutions, using: VrpResultSolution, documentation: { is_array: true, desc: 'The current best solution' }
    end

    class VrpAsyncJob < Grape::Entity
      expose :job, using: VrpResultJob, documentation: { desc: 'The Job status' }
    end

    class VrpJobsList < Grape::Entity
      expose :jobs, using: VrpResultJob, documentation: { is_array: true, desc: 'The Jobs' }
    end
  end
end
