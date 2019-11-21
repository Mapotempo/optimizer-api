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
require 'grape'
require 'grape-swagger'
require 'date'
require 'digest/md5'
require 'csv'

require './api/v01/api_base'
require './api/v01/entities/status'
require './api/v01/entities/vrp_result'

module Api
  module V01
    module CSVParser
      def self.call(object, _env)
        # TODO: use encoding from Content-Type or detect it.
        CSV.parse(object.force_encoding('utf-8'), headers: true).collect{ |row|
          r = row.to_h

          r.keys.each{ |key|
            next unless key.include?('.')
            part = key.split('.', 2)
            r.deep_merge!(part[0] => {part[1] => r[key]})
            r.delete(key)
          }

          json = r['json']
          if json # Open the secret short cut
            r.delete('json')
            r.deep_merge!(JSON.parse(json))
          end

          r
        }
      end
    end

    class Vrp < APIBase
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      content_type :csv, 'text/csv;'
      parser :csv, CSVParser
      default_format :json

      def self.vrp_request_timewindow(this)
        this.optional(:start, types: [String, Float, Integer], desc: 'Beginning of the current timewindow in seconds', coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
        this.optional(:end, types: [String, Float, Integer], desc: 'End of the current timewindow in seconds', coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
        this.optional(:day_index, type: Integer, values: 0..6, desc: '[ Planning ] Day index of the current timewindow within the periodic week, (monday = 0, ..., sunday = 6)')
      end

      def self.vrp_request_indice_range(this)
        this.optional(:start, type: Integer, desc: 'Beginning of the range.')
        this.optional(:end, type: Integer, desc: 'End of the range.')
      end

      def self.vrp_request_date_range(this)
        this.optional(:start, type: Date, desc: 'Beginning of the range in date format : .') # date format n'est donnable que si on crée vrp au meme endroit que là oùu on résoud, non ?
        this.optional(:end, type: Date, desc: 'End of the range in date format : .') # date format n'est donnable que si on crée vrp au meme endroit que là oùu on résoud, non ?
      end

      def self.vrp_request_matrices(this)
        this.requires(:id, type: String, allow_blank: false)
        this.optional(:time, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of time, travel duration between each pair of point in the problem. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix')
        this.optional(:distance, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of distance, travel distance between each pair of point in the problem. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix')
        this.optional(:value, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of values, travel value between each pair of point in the problem if not distance or time related. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix')
      end

      def self.vrp_request_point(this)
        this.requires(:id, type: String, allow_blank: false)
        this.optional(:matrix_index, type: Integer, desc: 'Index within the matrices, required if the matrices are already given')
        this.optional(:location, type: Hash, desc: 'Location of the point if matrices are not given') do
          self.requires(:lat, type: Float, allow_blank: false, desc: 'Latitude coordinate')
          self.requires(:lon, type: Float, allow_blank: false, desc: 'Longitude coordinate')
        end
        this.at_least_one_of :matrix_index, :location
      end

      def self.vrp_request_unit(this)
        this.requires(:id, type: String, allow_blank: false)
        this.optional(:label, type: String, desc: 'Name of the unit')
        this.optional(:counting, type: Boolean, desc: 'Define if the unit is a counting one, which allows to count the number of stops in a single route')
      end

      def self.vrp_request_rest(this)
        this.requires(:id, type: String, allow_blank: false)
        this.requires(:duration, types: [String, Float, Integer], desc: 'Duration of the vehicle rest', coerce_with: ->(value) { ScheduleType.new.type_cast(value) })
        this.optional(:timewindows, type: Array, desc: 'Time slot while the rest may begin') do
          Vrp.vrp_request_timewindow(self)
        end
        this.optional(:late_multiplier, type: Float, desc: 'Late multiplier applied for this rest.')
        this.optional(:exclusion_cost, type: Float, desc: 'Cost induced by non affectation of this rest.')
      end

      def self.vrp_request_zone(this)
        this.requires(:id, type: String, allow_blank: false, desc: '')
        this.requires(:polygon, type: Hash, desc: 'Geometry which describes the area')
        this.optional(:allocations, type: Array[Array[String]], desc: 'Define by which vehicle or vehicles combination the zone could be served') # ----------- ???
      end

      def self.vrp_request_activity(this)
        this.optional(:duration, types: [String, Float, Integer], desc: 'Time while the current activity stands until it\'s over (in seconds)', coerce_with: ->(value) { ScheduleType.new.type_cast(value) })
        this.optional(:additional_value, type: Integer, desc: 'Additional value associated to the visit')
        this.optional(:setup_duration, types: [String, Float, Integer], desc: 'Time at destination before the proper activity is effectively performed', coerce_with: ->(value) { ScheduleType.new.type_cast(value) })
        this.optional(:late_multiplier, type: Float, desc: 'Overrides the late_multiplier defined at the vehicle level (ORtools only)')
        this.optional(:timewindow_start_day_shift_number, type: Integer, desc: '[ DEPRECATED ]')
        this.requires(:point_id, type: String, allow_blank: false, desc: 'Reference to the associated point')
        this.optional(:timewindows, type: Array, desc: 'Time slot while the activity may start') do
          Vrp.vrp_request_timewindow(self)
        end
      end

      def self.vrp_request_quantity(this)
        this.optional(:id, type: String)
        this.requires(:unit_id, type: String, allow_blank: false, desc: 'Unit related to this quantity')
        this.optional(:fill, type: Boolean, desc: 'Allows to fill with quantity, until this unit vehicle capacity is full')
        this.optional(:empty, type: Boolean, desc: 'Allows to empty this quantity, until this unit vehicle capacity reaches zero')
        this.mutually_exclusive :fill, :empty
        this.optional(:value, type: Float, desc: 'Value of current quantity')
        this.optional(:setup_value, type: Integer, desc: 'If the associated unit is a counting one, defines the default value to count for this stop (additional quantities for this specific service are to define with the value tag)')
      end

      def self.vrp_request_capacity(this)
        this.optional(:id, type: String)
        this.requires(:unit_id, type: String, allow_blank: false, desc: 'Unit of the capacity')
        this.requires(:limit, type: Float, allow_blank: false, desc: 'Maximum capacity that can be carried')
        this.optional(:initial, type: Float, desc: 'Initial quantity value loaded in the vehicle')
        this.optional(:overload_multiplier, type: Float, desc: 'Allows to exceed the limit against this cost (ORtools only)')
      end

      def self.vrp_request_vehicle(this)
        this.requires(:id, type: String, allow_blank: false)
        this.optional(:cost_fixed, type: Float, desc: 'Cost applied if the vehicle is used')
        this.optional(:cost_distance_multiplier, type: Float, desc: 'Cost applied to the distance performed')
        this.optional(:cost_time_multiplier, type: Float, desc: 'Cost applied to the total amount of time of travel (Jsprit) or to the total time of route (ORtools)')
        this.optional(:cost_value_multiplier, type: Float, desc: 'Multiplier applied to the value matrix and additional activity value')
        this.optional(:cost_waiting_time_multiplier, type: Float, desc: 'Cost applied to the waiting time in the route (Jsprit Only)')
        this.optional(:cost_late_multiplier, type: Float, desc: 'Cost applied if a point is delivered late (ORtools only)')
        this.optional(:cost_setup_time_multiplier, type: Float, desc: 'Cost applied on the setup duration (Jsprit only)')
        this.optional(:coef_setup, type: Float, desc: 'Coefficient applied to every setup duration defined in the tour, for this vehicle')
        this.optional(:additional_setup, type: Float, desc: 'Constant additional setup duration for all setup defined in the tour, for this vehicle')
        this.optional(:coef_service, type: Float, desc: 'Coefficient applied to every service duration defined in the tour, for this vehicle')
        this.optional(:additional_service, type: Float, desc: 'Constant additional service time for all travel defined in the tour, for this vehicle')
        this.optional(:force_start, type: Boolean, desc: '[ DEPRECATED ]')
        this.optional(:shift_preference, type: String, values: ['force_start', 'force_end', 'minimize_span'], desc: 'Force the vehicle to start as soon as the vehicle timewindow is open, as late as possible or let vehicule start at any time. Not available with periodic heuristic.')
        this.optional(:trips, type: Integer, desc: 'Describe the number of return to the depot a vehicle is allowed to perform within its route')

        this.optional :matrix_id, type: String, desc: 'Related matrix, if already defined'
        this.optional :value_matrix_id, type: String, desc: 'If any value matrix defined, related matrix index.'
        this.optional :router_mode, type: String, desc: 'car, truck, bicycle...etc. See the Router Wrapper API doc'
        this.exactly_one_of :matrix_id, :router_mode
        this.optional :router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance'
        this.optional :speed_multiplier, type: Float, default: 1.0, desc: 'Multiplies the vehicle speed, default : 1.0. Specifies if this vehicle is faster or slower than average speed.'
        this.optional :area, type: Array, coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |b| b.split(',').collect{ |f| Float(f) }} : c }, desc: 'List of latitudes and longitudes separated with commas. Areas separated with pipes (only available for truck mode at this time).'
        this.optional :speed_multiplier_area, type: Array[Float], coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |f| Float(f) } : c }, desc: 'Speed multiplier per area, 0 to avoid area. Areas separated with pipes (only available for truck mode at this time).'
        this.optional :traffic, type: Boolean, default: true, desc: 'Take into account traffic or not.'
        this.optional :departure, type: DateTime, desc: 'Departure date time (only used if router supports traffic).'
        this.optional :track, type: Boolean, default: true, desc: 'Use track or not.'
        this.optional :motorway, type: Boolean, default: true, desc: 'Use motorway or not.'
        this.optional :toll, type: Boolean, default: true, desc: 'Use toll section or not.'
        this.optional :trailers, type: Integer, desc: 'Number of trailers.'
        this.optional :weight, type: Float, desc: 'Vehicle weight including trailers and shipped goods, in tons.'
        this.optional :weight_per_axle, type: Float, desc: 'Weight per axle, in tons.'
        this.optional :height, type: Float, desc: 'Height in meters.'
        this.optional :width, type: Float, desc: 'Width in meters.'
        this.optional :length, type: Float, desc: 'Length in meters.'
        this.optional :hazardous_goods, type: Symbol, values: [:explosive, :gas, :flammable, :combustible, :organic, :poison, :radio_active, :corrosive, :poisonous_inhalation, :harmful_to_water, :other], desc: 'List of hazardous materials in the vehicle.'
        this.optional :max_walk_distance, type: Float, default: 750, desc: 'Max distance by walk.'
        this.optional :approach, type: Symbol, values: [:unrestricted, :curb], default: :unrestricted, desc: 'Arrive/Leave in the traffic direction.'
        this.optional :snap, type: Float, desc: 'Snap waypoint to junction close by snap distance.'
        this.optional :strict_restriction, type: Boolean, desc: 'Strict compliance with truck limitations.'

        this.optional(:duration, types: [String, Float, Integer], desc: 'Maximum tour duration', coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
        this.optional(:overall_duration, types: [String, Float, Integer], desc: '[planning] If schedule covers several days, maximum work duration over whole period. Not available with periodic heuristic.', coerce_with: ->(value) { ScheduleType.new.type_cast(value, false) })
        this.optional(:distance, types: Integer, desc: 'Maximum tour distance. Not available with periodic heuristic.')
        this.optional(:maximum_ride_time, type: Integer, desc: 'Maximum ride duration between two route activities')
        this.optional(:maximum_ride_distance, type: Integer, desc: 'Maximum ride distance between two route activities')
        this.optional(:skills, type: Array[Array[String]], desc: 'Particular abilities which could be handle by the vehicle. Not available with periodic heuristic. This parameter is a set of alternative skills, and must be defined as an Array[Array[String]]')

        this.optional(:unavailable_work_day_indices, type: Array[Integer], desc: '[planning] Express the exceptionnals indices of unavailabilty')
        this.optional(:unavailable_work_date, type: Array, desc: '[planning] Express the exceptionnals days of unavailability')
        this.mutually_exclusive :unavailable_work_day_indices, :unavailable_work_date

        this.optional(:free_approach, type: Boolean, desc: 'Do not take into account the route leaving the depot in the objective. Not available with periodic heuristic.')
        this.optional(:free_return, type: Boolean, desc: 'Do not take into account the route arriving at the depot in the objective. Not available with periodic heuristic.')

        this.optional(:start_point_id, type: String, desc: 'Begin of the tour')
        this.optional(:end_point_id, type: String, desc: 'End of the tour')
        this.optional(:capacities, type: Array, desc: 'Define the limit of entities the vehicle could carry') do
          Vrp.vrp_request_capacity(self)
        end

        this.optional(:sequence_timewindows, type: Array, desc: '[planning] Define the vehicle work schedule over a period') do
          Vrp.vrp_request_timewindow(self)
        end
        this.optional(:timewindow, type: Hash, desc: 'Time window whithin the vehicle may be on route') do
          Vrp.vrp_request_timewindow(self)
        end
        this.mutually_exclusive :sequence_timewindows, :timewindow

        this.optional(:rest_ids, type: Array[String], desc: 'Breaks whithin the tour')
      end

      def self.vrp_request_service(this)
        this.requires(:id, type: String, allow_blank: false)
        this.optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8, default is 4. 0 is the highest priority level). Not available with same_point_day option.')
        this.optional(:exclusion_cost, type: Integer, desc: 'Exclusion cost. Not available with periodic heuristic.')

        this.optional(:visits_number, type: Integer, desc: 'Total number of visits over the complete schedule (including the unavailable visit indices)')

        this.optional(:unavailable_visit_indices, type: Array[Integer], desc: '[planning] unavailable indices of visit')

        this.optional(:unavailable_visit_day_indices, type: Array[Integer], desc: '[planning] Express the exceptionnals days indices of unavailabilty')
        this.optional(:unavailable_visit_day_date, type: Array, desc: '[planning] Express the exceptionnals days of unavailability')
        this.mutually_exclusive :unavailable_visit_day_indices, :unavailable_visit_day_date

        this.optional(:minimum_lapse, type: Float, desc: 'Minimum day lapse between two visits')
        this.optional(:maximum_lapse, type: Float, desc: 'Maximum day lapse between two visits')

        this.optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the service is assigned')
        this.optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this service')

        this.optional(:type, type: Symbol, desc: 'service, pickup or delivery')
        this.optional(:activity, type: Hash, desc: 'Details of the activity performed to accomplish the current service') do
          Vrp.vrp_request_activity(self)
        end
        this.optional(:activities, type: Array, desc: 'Define other possible activities for the service. This allows to assign different timewindows and/or points to a single service.') do
          Vrp.vrp_request_activity(self)
        end
        this.mutually_exclusive :activity, :activities
        this.optional(:quantities, type: Array, desc: 'Define the entities which are taken or dropped') do
          Vrp.vrp_request_quantity(self)
        end
      end

      def self.vrp_request_shipment(this)
        this.requires(:id, type: String, allow_blank: false, desc: '')
        this.optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8, default is 4)')
        this.optional(:exclusion_cost, type: Integer, desc: 'Exclusion cost')

        this.optional(:visits_number, type: Integer, desc: 'Total number of visits over the complete schedule (including the unavailable visit indices)')

        this.optional(:unavailable_visit_indices, type: Array[Integer], desc: '[planning] unavailable indices of visit')

        this.optional(:unavailable_visit_day_indices, type: Array[Integer], desc: '[planning] Express the exceptionnals days indices of unavailabilty')
        this.optional(:unavailable_visit_day_date, type: Array, desc: '[planning] Express the exceptionnals days of unavailability')
        this.mutually_exclusive :unavailable_visit_day_indices, :unavailable_visit_day_date

        this.optional(:minimum_lapse, type: Float, desc: 'Minimum day lapse between two visits')
        this.optional(:maximum_lapse, type: Float, desc: 'Maximum day lapse between two visits')

        this.optional(:maximum_inroute_duration, type: Integer, desc: 'Maximum in route duration of this particular shipment (Must be feasible !)')
        this.optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the shipment is assigned')
        this.optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this shipment')
        this.requires(:pickup, type: Hash, allow_blank: false, desc: 'Activity of collection') do
          Vrp.vrp_request_activity(self)
        end
        this.requires(:delivery, type: Hash, allow_blank: false, desc: 'Activity of drop off') do
          Vrp.vrp_request_activity(self)
        end
        this.optional(:quantities, type: Array, desc: 'Define the entities which are taken and dropped') do
          Vrp.vrp_request_quantity(self)
        end
      end

      def self.vrp_request_subtour(this)
        this.requires(:id, type: String, allow_blank: false, desc: '')
        this.optional(:time_bounds, type: Integer, desc: 'Time limit from the transmodal points (Isochrone)')
        this.optional(:distance_bounds, type: Integer, desc: 'Distance limit from the transmodal points (Isodistanche)')
        this.optional(:router_mode, type: String, desc: 'car, truck, bicycle...etc. See the Router Wrapper API doc')
        this.optional(:router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance')
        this.optional(:speed_multiplier, type: Float, default: 1.0, desc: 'multiply the current modality speed, default : 1.0')
        this.optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this subtour')
        this.optional(:duration, type: Integer, desc: 'Maximum subtour duration')
        this.optional(:transmodal_stops, type: Array, desc: 'Point where the vehicles can park and start the subtours') do
          Vrp.vrp_request_point(self)
        end
        this.optional(:capacities, type: Array, desc: 'Define the limit of entities the subtour modality can handle') do
          Vrp.vrp_request_capacity(self)
        end
        this.exactly_one_of :time_bounds, :distance_bounds
      end

      def self.vrp_request_relation(this)
        this.requires(:id, type: String, allow_blank: false, desc: '')
        this.requires(:type, type: String, allow_blank: false, values: %w[same_route sequence order minimum_day_lapse maximum_day_lapse shipment meetup maximum_duration_lapse force_first never_first force_end vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months],
                             desc: 'Relations allow to define constraints explicitly between activities and/or vehicles. It could be the following types: same_route, sequence, order, minimum_day_lapse, maximum_day_lapse, shipment, meetup, maximum_duration_lapse, force_first, never_first, force_end, vehicle_group_duration, vehicle_group_duration_on_weeks or vehicle_group_duration_on_months')
        this.optional(:lapse, type: Integer, desc: 'Only used for relations implying a duration constraint : minimum/maximum day lapse, vehicle group durations...')
        this.optional(:linked_ids, type: Array[String], desc: 'List of activities involved in the relation')
        this.optional(:linked_vehicle_ids, type: Array[String], desc: 'List of vehicles involved in the relation')
        this.optional(:periodicity, type: Integer, desc: 'In the case of planning optimization, number of weeks/months to consider at the same time/in each relation : vehicle group duration on weeks/months')
        this.at_least_one_of :linked_ids, :linked_vehicles_ids
      end

      def self.vrp_request_route(this)
        this.optional(:vehicle_id, type: String, desc: 'vehicle linked to the current described route')
        this.optional(:day, type: Integer, desc: 'Day indice of the route. Must be provided if first_solution_strategy is \'periodic\'.')
        this.requires(:mission_ids, type: Array[String], desc: 'Initial state or partial state of the current vehicle route')
      end

      def self.vrp_request_partition(this)
        this.requires(:method, type: String, values: %w[hierarchical_tree balanced_kmeans], desc: 'Method used to partition')
        this.optional(:metric, type: Symbol, desc: 'Defines partition reference metric. Values should be either duration, visits or any unit you defined in units.')
        this.optional(:entity, type: String, values: %w[vehicle work_day], desc: 'Describes what the partition corresponds to. Only available if method in [balanced_kmeans hierarchical_tree]')
        this.optional(:threshold, type: Integer, desc: 'Maximum size of partition. Only available if method in [iterative_kmean clique]')
      end

      def self.vrp_request_preprocessing(this)
        this.optional(:max_split_size, type: Integer, desc: 'Divide the problem into clusters beyond this threshold')
        this.optional(:partition_method, type: String, desc: '[ DEPRECATED : use partitions structure instead ]')
        this.optional(:partition_metric, type: Symbol, desc: '[ DEPRECATED : use partitions structure instead ]')
        this.optional(:kmeans_centroids, type: Array[Integer], desc: 'Forces centroid indices used to generate clusters with kmeans partition_method. Only available with deprecated partition_method')
        this.optional(:cluster_threshold, type: Float, desc: 'Regroup close points which constitute a cluster into a single geolocated point')
        this.optional(:force_cluster, type: Boolean, desc: 'Force to cluster visits even if containing timewindows and quantities')
        this.optional(:prefer_short_segment, type: Boolean, desc: 'Could allow to pass multiple time in the same street but deliver in a single row')
        this.optional(:neighbourhood_size, type: Integer, desc: 'Limit the size of the considered neighbourhood within the search')
        this.optional(:partitions, type: Array, desc: 'Describes partition process to perform before solving. Partitions will be performed in provided order') do
          Vrp.vrp_request_partition(self)
        end
        this.optional(:first_solution_strategy, types: Array[String], desc: 'Forces first solution strategy. Either one value to force specific behavior, or a list in order to test several ones and select the best. If string is \'internal\', we will choose among pre-selected behaviors. There can not be more than three behaviors (ORtools only)', coerce_with: ->(value) { FirstSolType.new.type_cast(value) })
      end

      def self.vrp_request_resolution(this)
        this.optional(:duration, type: Integer, desc: 'Maximum duration of resolution')
        this.optional(:iterations, type: Integer, desc: 'Maximum number of iterations (Jsprit only)')
        this.optional(:iterations_without_improvment, type: Integer, desc: 'Maximum number of iterations without improvment from the best solution already found')
        this.optional(:stable_iterations, type: Integer, desc: 'maximum number of iterations without variation in the solve bigger than the defined coefficient (Jsprit only)')
        this.optional(:stable_coefficient, type: Float, desc: 'variation coefficient related to stable_iterations (Jsprit only)')
        this.optional(:initial_time_out, type: Integer, desc: '[ DEPRECATED : use minimum_duration instead]')
        this.optional(:minimum_duration, type: Integer, desc: 'Minimum solve duration before the solve could stop (x10 in order to find the first solution) (ORtools only)')
        this.optional(:time_out_multiplier, type: Integer, desc: 'the solve could stop itself if the solve duration without finding a new solution is greater than the time currently elapsed multiplicate by this parameter (ORtools only)')
        this.optional(:vehicle_limit, type: Integer, desc: 'Limit the maxiumum number of vehicles within a solution. Not available with periodic heuristic.')
        this.optional(:solver_parameter, type: Integer, desc: '[ DEPRECATED : use preprocessing_first_solution_strategy instead ]')
        this.optional(:solver, type: Boolean, default: true, desc: 'Defines if solver should be called.')
        this.optional(:same_point_day, type: Boolean, desc: '[planning] Forces all services with the same point_id to take place on the same days. Only available if first_solution_strategy is periodic is activated. Not available ORtools.')
        this.optional(:allow_partial_assignment, type: Boolean, default: true, desc: '[planning] Assumes solution is valid even if only a subset of one service\'s visits are affected. Default: true. Not available ORtools.')
        this.optional(:split_number, type: Integer, desc: 'Give the current number of process for block call')
        this.optional(:evaluate_only, type: Boolean, desc: 'Takes the solution provided through relations of type order and computes solution cost and time/distance associated values (Ortools only). Not available for scheduling yet.')
        this.optional(:several_solutions, type: Integer, desc: 'Return several solution computed with different matrices')
        this.optional(:batch_heuristic, type: Boolean, default: OptimizerWrapper.config[:debug][:batch_heuristic], desc: 'Compute each heuristic solution')
        this.optional(:variation_ratio, type: Integer, desc: 'Value of the ratio that will change the matrice')
        this.optional(:floating_precision, type: Integer, default: 0, desc: 'Number of decimals used for scheduling computation.')
        this.at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient, :initial_time_out, :minimum_duration
        this.mutually_exclusive :initial_time_out, :minimum_duration
      end

      def self.vrp_request_restitution(this)
        this.optional(:geometry, type: Boolean, desc: 'Allow to return the MultiLineString of each route')
        this.optional(:geometry_polyline, type: Boolean, desc: 'Encode the MultiLineString')
        this.optional(:intermediate_solutions, type: Boolean, desc: 'Return intermediate solutions if available')
        this.optional(:csv, type: Boolean, desc: 'The output is a CSV file if you do not specify api format')
        this.optional(:allow_empty_result, type: Boolean, desc: 'Allow no solution from the solver used')
      end

      def self.vrp_request_schedule(this)
        this.optional(:range_indices, type: Hash, desc: '[planning] Day indices within the plan has to be build') do
          Vrp.vrp_request_indice_range(self)
        end
        this.optional(:range_date, type: Hash, desc: '[planning] Define the total period to consider') do
          Vrp.vrp_request_date_range(self)
        end

        this.mutually_exclusive :range_indices, :range_date
        this.optional(:unavailable_indices, type: Array[Integer], desc: '[planning] Exclude some days indices from the resolution')
        this.optional(:unavailable_date, type: Array[Date], desc: '[planning] Exclude some days from the resolution')
        this.mutually_exclusive :unavailable_indices, :unavailable_date
      end

      namespace :vrp do
        resource :submit do
          desc 'Submit VRP problem', {
            nickname: 'vrp',
            success: VrpResult,
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: 'Submit vehicle routing problem. If the problem can be quickly solved, the solution is returned in the response. In other case, the response provides a job identifier in a queue: you need to perfom another request to fetch vrp job status and solution.'
          }
          params {
            optional(:vrp, type: Hash, documentation: { param_type: 'body' }, coerce_with: ->(c) { c.has_key?('filename') ? JSON.parse(c.tempfile.read) : c }) do
              optional(:name, type: String, desc: 'Name of the problem, used as tag for all element in order to name plan when importing returned .csv file')
              optional(:matrices, type: Array, desc: 'Define all the distances between each point of problem') do
                Vrp.vrp_request_matrices(self)
              end

              optional(:points, type: Array, desc: 'Particular place in the map') do
                Vrp.vrp_request_point(self)
              end

              optional(:units, type: Array, desc: 'The name of a Capacity/Quantity') do
                Vrp.vrp_request_unit(self)
              end

              optional(:rests, type: Array, desc: 'Break within a vehicle tour') do
                Vrp.vrp_request_rest(self)
              end

              optional(:zones, type: Array, desc: '') do
                Vrp.vrp_request_zone(self)
              end

              requires(:vehicles, type: Array, desc: 'Usually represent a work day of a particular driver/vehicle') do
                Vrp.vrp_request_vehicle(self)
              end

              optional(:services, type: Array, desc: 'Independent activity, which does not require a context') do
                Vrp.vrp_request_service(self)
              end
              optional(:shipments, type: Array, desc: 'Link directly one activity of collection to another of drop off') do
                Vrp.vrp_request_shipment(self)
              end
              at_least_one_of :services, :shipments

              optional(:relations, type: Array, desc: '') do
                Vrp.vrp_request_relation(self)
              end

              optional(:subtours, type: Array, desc: '') do
                Vrp.vrp_request_subtour(self)
              end

              optional(:routes, type: Array, desc: '') do
                Vrp.vrp_request_route(self)
              end

              optional(:configuration, type: Hash, desc: 'Describe the limitations of the solve in term of computation') do
                optional(:preprocessing, type: Hash, desc: 'Parameters independent from the search') do
                  Vrp.vrp_request_preprocessing(self)
                end
                optional(:resolution, type: Hash, desc: 'Parameters used to stop the search') do
                  Vrp.vrp_request_resolution(self)
                end
                optional(:restitution, type: Hash, desc: 'Restitution paramaters') do
                  Vrp.vrp_request_restitution(self)
                end
                optional(:schedule, type: Hash, desc: 'Describe the general settings of a schedule') do
                  Vrp.vrp_request_schedule(self)
                end
              end
            end

            optional :points, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Particular place in the map' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_point(self)
            end

            optional :units, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! The name of a Capacity/Quantity' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_unit(self)
            end

            optional :timewindows, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Time slot while the activity may be performed' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_timewindow(self)
            end

            optional :capacities, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Define the limit of entities the vehicle could carry' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_capacity(self)
            end

            optional :quantities, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Define the entities which are taken or dropped' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_quantity(self)
            end

            optional :services, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Independent activity, which does not require a context' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) } do
              Vrp.vrp_request_service(self)
            end

            optional(:shipments, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Link directly one activity of collection to another of drop off' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) }) do
              Vrp.vrp_request_shipment(self)
            end

            optional(:vehicles, type: Array, documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Usually represent a work day of a particular driver/vehicle' }, coerce_with: ->(c) { CSVParser.call(File.open(c.tempfile, 'r:bom|utf-8').read, nil) }) do
              Vrp.vrp_request_vehicle(self)
            end
          }
          post do
            begin
              # Api key is not declared as part of the VRP and must be handled carefully and separatly from other parameters
              api_key = params[:api_key]
              checksum = Digest::MD5.hexdigest Marshal.dump(params)
              d_params = declared(params, include_missing: false)
              vrp_params = d_params[:points] ? d_params : d_params[:vrp]
              APIBase.dump_vrp_dir.write([api_key, vrp_params[:name], checksum].compact.join('_'), { vrp: vrp_params }.to_json) if OptimizerWrapper.config[:dump][:vrp]
              vrp = ::Models::Vrp.create({})
              params_limit = APIBase.services(api_key)[:params_limit].merge(OptimizerWrapper.access[api_key][:params_limit] || {})
              [:name, :matrices, :units, :points, :rests, :zones, :capacities, :quantities, :timewindows,
               :vehicles, :services, :shipments, :relations, :subtours, :routes, :configuration].each{ |key|
                value = vrp_params[key]
                if params_limit[key] && value && value.size > params_limit[key]
                  error!({
                    status: 'Exceeded params limit',
                    detail: "Exceeded #{key} limit authorized for your account: #{params_limit[key]}. Please contact support or sales to increase limits."
                  }, 400)
                end
                vrp.send("#{key}=", vrp_params[key]) if vrp_params[key]
              }

              if !vrp.valid? || vrp_params.nil? || vrp_params.keys.empty?
                vrp.errors.add(:empty_file, message: 'JSON file is empty') if vrp_params.nil?
                vrp.errors.add(:empty_vrp, message: 'VRP structure is empty') if vrp_params&.keys&.empty?
                error!({ status: 'Model Validation Error', detail: vrp.errors }, 400)
              else
                ret = OptimizerWrapper.wrapper_vrp(api_key, APIBase.services(api_key), vrp, checksum)
                if ret.is_a?(String)
                  #present result, with: VrpResult
                  status 201
                  present({ job: { id: ret, status: :queued }}, with: Grape::Presenters::Presenter)
                elsif ret.is_a?(Hash)
                  status 200
                  if vrp.restitution_csv
                    present(OptimizerWrapper.build_csv(ret.deep_stringify_keys), type: CSV)
                  else
                    present({ solutions: [ret], job: { status: :completed }}, with: Grape::Presenters::Presenter)
                  end
                else
                  error!({ status: 'Internal Server Error' }, 500)
                end
              end
            ensure
              ::Models.delete_all
            end
          end
        end

        resource :jobs do
          desc 'Fetch vrp job status', {
            nickname: 'job',
            success: VrpResult,
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: 'Get the job status and details, contains progress avancement. Return the best actual solutions currently found.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by creating VRP problem.'
          }
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            stored_result = APIBase.dump_vrp_dir.read([id, params[:api_key], 'solution'].join('_'))
            solution = stored_result && Marshal.load(stored_result) || OptimizerWrapper::Result.get(id)
            output_format = params[:format]&.to_sym || (solution && solution['csv'] ? :csv : env['api.format'])
            env['api.format'] = output_format # To override json default format

            error!({status: 'Not Found', detail: "Job with id='#{id}' not found"}, 404) unless job && job['options']['api_key'] == params[:api_key] || solution

            solution ||= {}

            # If job has been killed by restarting queues, need to update job status to 'killed'
            if job&.working?
              job_ids = Resque.workers.map{ |w|
                j = w.job(false)
                j['payload'] && j['payload']['args'].first
              }
              unless job_ids.include? id
                OptimizerWrapper.job_remove(params[:api_key], id)
                job.status = 'killed'
              end
            end

            if job&.killed? || Resque::Plugins::Status::Hash.should_kill?(id)
              status 404
              error!({status: 'Not Found', detail: "Job with id='#{id}' not found"}, 404)
            elsif job&.failed?
              status 202
              if output_format == :csv
                present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
              else
                present({
                  solutions: [solution['result']].flatten(1),
                  job: {
                    id: id,
                    status: :failed,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              end
            elsif job && !job.completed?
              status 206
              # TODO: why try to return a csv for queued job?
              if output_format == :csv
                present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
              else
                present({
                  solutions: [solution['result']].flatten(1),
                  job: {
                    id: id,
                    status: ['queued', 'working'].include?(job.status) ? job.status.to_sym : nil,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              end
            else
              APIBase.dump_vrp_dir.write([id, params[:api_key], 'solution'].join('_'), Marshal.dump(solution)) if job && OptimizerWrapper.config[:dump][:solution]
              status 200
              if output_format == :csv
                present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
              else
                present({
                  solutions: [solution['result']].flatten(1),
                  job: {
                    id: id,
                    status: :completed,
                    avancement: job&.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              end
              OptimizerWrapper.job_remove(params[:api_key], id) if job
            end
          end

          desc 'List vrp jobs', {
            nickname: 'listJobs',
            success: VrpJobsList,
            detail: 'List running or queued jobs.'
          }
          get do
            status 200
            present OptimizerWrapper.job_list(params[:api_key]), with: Grape::Presenters::Presenter
          end

          desc 'Delete vrp job', {
            nickname: 'deleteJob',
            success: {code: 204},
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: 'Kill the job. This operation may have delay, since if the job is working it will be killed during the next iteration.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by creating VRP problem.'
          }
          delete ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)

            if !job || job['options']['api_key'] != params[:api_key]
              status 404
              error!({status: 'Not Found', detail: "Job with id='#{id}' not found"}, 404)
            else
              OptimizerWrapper.job_kill(params[:api_key], id)
              job.status = 'killed'
              solution = OptimizerWrapper::Result.get(id)
              status 202
              if solution && !solution.empty?
                output_format = params[:format]&.to_sym || (solution['csv'] ? :csv : env['api.format'])
                if output_format == :csv
                  present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
                else
                  present({
                    solutions: [solution['result']],
                    job: {
                      id: id,
                      status: :killed,
                      avancement: job.message,
                      graph: solution['graph']
                    }
                  }, with: Grape::Presenters::Presenter)
                end
              else
                present({
                  job: {
                    id: id,
                    status: :killed,
                  }
                }, with: Grape::Presenters::Presenter)
              end
              OptimizerWrapper.job_remove(params[:api_key], id)
            end
          end
        end
      end
    end
  end
end
