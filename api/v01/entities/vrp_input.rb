# Copyright © Mapotempo, 2020
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
require './api/v01/vrp'

module VrpInput
  extend Grape::API::Helpers

  params :input do
    optional(:vrp, type: Hash, documentation: { param_type: 'body' }, coerce_with: ->(c) { c.has_key?('filename') ? JSON.parse(c[:tempfile].read) : c }) do
      use :request_object
    end
    use :request_files
    exactly_one_of :vrp, :vehicles # either it is a json (and :vrp is required) or it is a csv (and :vehicles is required)
  end

  # Input as expected in JSON
  params :request_object do
    optional(:name, type: String, desc: 'Name of the problem, used as tag for all element in order to name plan when importing returned .csv file')
    optional(:matrices, type: Array, documentation: { desc: 'Define all the distances between each point of problem' }) do use :vrp_request_matrices end

    optional(:points, type: Array, documentation: { desc: 'Particular place in the map' }) do use :vrp_request_point end

    optional(:units, type: Array, documentation: { desc: 'The name of a Capacity/Quantity' }) do use :vrp_request_unit end

    optional(:rests, type: Array, documentation: { desc: 'Break within a vehicle tour' }) do use :vrp_request_rest end

    optional(:zones, type: Array, desc: '') do use :vrp_request_zone end

    requires(:vehicles, type: Array, documentation: { desc: 'Set of available vehicles' }) do
      use :vrp_request_vehicle
    end

    optional(:services, type: Array, allow_blank: false, documentation: { desc: 'Independent activity, which does not require a context' }) do
      use :vrp_request_service
    end
    optional(:shipments, type: Array, allow_blank: false, documentation: { desc: 'Link directly one activity of collection to another of drop off. Not available with periodic heuristic.' }) do
      use :vrp_request_shipment
    end
    at_least_one_of :services, :shipments

    optional(:relations, type: Array, desc: 'Not available with periodic heuristic') do use :vrp_request_relation end

    optional(:subtours, type: Array, desc: 'Not available with periodic heuristic') do use :vrp_request_subtour end

    optional(:routes, type: Array, desc: '') do use :vrp_request_route end

    optional(:configuration, type: Hash, documentation: { desc: 'Describe the limitations of the solve in term of computation' }) do
      use :vrp_request_configuration
    end
  end

  # Input as expected in CSV
  params :request_files do # rubocop:disable Metrics/BlockLength
                           # We expect here to keep the definition of the high level model in a single place
    optional :points, type: Array,
                      documentation: { hidden: true, desc: 'Warning : CSV Format expected here ! Particular place in the map.' },
                      coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_point
    end

    optional :units, type: Array,
                     documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! The name of a Capacity/Quantity.' },
                     coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_unit
    end

    optional :timewindows, type: Array,
                           documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Time slot while the activity may be performed.' },
                           coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_timewindow
    end

    optional :capacities, type: Array,
                          documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Define the limit of entities the vehicle could carry.' },
                          coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_capacity
    end

    optional :quantities, type: Array,
                          documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Define the entities which are taken or dropped.' },
                          coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_quantity
    end

    optional :services, type: Array,
                        documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Independent activity, which does not require a context.' },
                        coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_service
    end

    optional :shipments, type: Array,
                         documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Link directly one activity of collection to another of drop off.' },
                         coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_shipment
    end

    optional :vehicles, type: Array,
                        documentation: { hidden: true, format: 'CSV', desc: 'Warning : CSV Format expected here ! Set of available vehicles.' },
                        coerce_with: ->(path) { path.is_a?(Array) ? path : Api::V01::CSVParser.call(File.open(path[:tempfile], 'r:bom|utf-8').read, nil) } do
      use :vrp_request_vehicle
    end

    optional(:configuration, type: Hash,
                             documentation: { hidden: true, desc: 'Describe the limitations of the solve in term of computation' },
                             coerce_with: ->(path) { path[:tempfile] ? JSON.parse(path[:tempfile].read, symbolize_names: true) : path }) do
      use :vrp_request_configuration
    end
  end
end

module VrpConfiguration
  extend Grape::API::Helpers

  params :vrp_request_configuration do
    optional(:preprocessing, type: Hash, desc: 'Parameters independent from the search') do
      use :vrp_request_preprocessing
    end
    optional(:resolution, type: Hash, desc: 'Parameters used to stop the search') do
      use :vrp_request_resolution
    end
    optional(:restitution, type: Hash, desc: 'Restitution paramaters') do
      use :vrp_request_restitution
    end
    optional(:schedule, type: Hash, desc: 'Describe the general settings of a schedule') do
      use :vrp_request_schedule
    end
    mutually_exclusive :solver_parameter, :first_solution_strategy
  end

  params :vrp_request_partition do
    requires(:method, type: String, values: %w[hierarchical_tree balanced_kmeans], desc: 'Method used to partition')
    optional(:metric, type: Symbol, desc: 'Defines partition reference metric. Values should be either duration, visits or any unit you defined in units.')
    optional(:entity, type: Symbol, values: [:vehicle, :work_day], desc: 'Describes what the partition corresponds to. Available only if method in [balanced_kmeans hierarchical_tree].', coerce_with: ->(value) { value.to_sym })
    optional(:threshold, type: Integer, desc: 'Maximum size of partition. Available only if method in [iterative_kmean clique].')
  end

  params :vrp_request_preprocessing do
    optional(:max_split_size, type: Integer, desc: 'Divide the problem into clusters beyond this threshold')
    optional(:partition_method, type: String, documentation: { hidden: true }, desc: '[ DEPRECATED : use partitions structure instead ]')
    optional(:partition_metric, type: Symbol, documentation: { hidden: true }, desc: '[ DEPRECATED : use partitions structure instead ]')
    optional(:kmeans_centroids, type: Array[Integer], desc: 'Forces centroid indices used to generate clusters with kmeans partition_method. Available only with deprecated partition_method.')
    optional(:cluster_threshold, type: Float, desc: 'Regroup close points which constitute a cluster into a single geolocated point')
    optional(:force_cluster, type: Boolean, desc: 'Force to cluster visits even if containing timewindows and quantities')
    optional(:prefer_short_segment, type: Boolean, desc: 'Could allow to pass multiple time in the same street but deliver in a single row')
    optional(:neighbourhood_size, type: Integer, desc: 'Limit the size of the considered neighbourhood within the search')
    optional(:partitions, type: Array, desc: 'Describes partition process to perform before solving. Partitions will be performed in provided order') do
      use :vrp_request_partition
    end
    optional(:first_solution_strategy, type: Array[String], desc: 'Forces first solution strategy. Either one value to force specific behavior, or a list in order to test several ones and select the best. If string is \'internal\', we will choose among pre-selected behaviors. There can not be more than three behaviors (ORtools only).', coerce_with: ->(value) { FirstSolType.new.type_cast(value) })
  end

  params :vrp_request_resolution do
    optional(:duration, type: Integer, allow_blank: false, desc: 'Maximum duration of resolution')
    optional(:iterations, type: Integer, allow_blank: false, desc: 'DEPRECATED : Jsprit solver and related parameters are not supported anymore')
    optional(:iterations_without_improvment, type: Integer, allow_blank: false, desc: 'Maximum number of iterations without improvment from the best solution already found')
    optional(:stable_iterations, type: Integer, allow_blank: false, desc: 'DEPRECATED : Jsprit solver and related parameters are not supported anymore')
    optional(:stable_coefficient, type: Float, allow_blank: false, desc: 'DEPRECATED : Jsprit solver and related parameters are not supported anymore')
    optional(:initial_time_out, type: Integer, allow_blank: false, documentation: { hidden: true }, desc: '[ DEPRECATED : use minimum_duration instead]')
    optional(:minimum_duration, type: Integer, allow_blank: false, desc: 'Minimum solve duration before the solve could stop (x10 in order to find the first solution) (ORtools only)')
    optional(:time_out_multiplier, type: Integer, desc: 'The solve could stop itself if the solve duration without finding a new solution is greater than the time currently elapsed multiplicate by this parameter (ORtools only)')
    optional(:vehicle_limit, type: Integer, desc: 'Limit the maxiumum number of vehicles within a solution. Not available with periodic heuristic.')
    optional(:solver_parameter, type: Integer, documentation: { hidden: true }, desc: '[ DEPRECATED : use preprocessing_first_solution_strategy instead ]')
    optional(:solver, type: Boolean, desc: 'Defines if solver should be called')
    optional(:minimize_days_worked, type: Boolean, default: false, desc: '(Scheduling heuristic only) Starts filling earlier days of the period first and minimizes the total number of days worked. Available only if first_solution_strategy is \'periodic\'. Not available with ORtools.')
    optional(:same_point_day, type: Boolean, desc: '(Scheduling only) Forces all services with the same point_id to take place on the same days. Available only if first_solution_strategy is \'periodic\'. Not available ORtools.')
    optional(:allow_partial_assignment, type: Boolean, default: true, desc: '(Scheduling heuristic only) Considers a solution as valid even if only a subset of the visits of a service is performed. If disabled, a service can only appear fully assigned or fully unassigned in the solution. Not available with ORtools.')
    optional(:split_number, type: Integer, desc: 'Give the current number of process for block call')
    optional(:evaluate_only, type: Boolean, desc: 'Takes the solution provided through relations of type order and computes solution cost and time/distance associated values (Ortools only). Not available for scheduling yet.')
    optional(:several_solutions, type: Integer, allow_blank: false, default: 1, desc: 'Return several solution computed with different matrices')
    optional(:batch_heuristic, type: Boolean, default: OptimizerWrapper.config[:debug][:batch_heuristic], desc: 'Compute each heuristic solution')
    optional(:variation_ratio, type: Integer, desc: 'Value of the ratio that will change the matrice')
    optional(:repetition, type: Integer, documentation: { hidden: true }, desc: 'Number of times the optimization process is going to be repeated. Only the best solution is returned.')
    optional(:dicho_algorithm_service_limit, type: Integer, documentation: { hidden: true }, desc: 'Minimum number of services required to allow a call to heuristic dichotomious_approach')
    at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient, :initial_time_out, :minimum_duration
    mutually_exclusive :initial_time_out, :minimum_duration
    mutually_exclusive :solver, :solver_parameter
  end

  params :vrp_request_restitution do
    optional(:geometry, type: Boolean, desc: 'Allow to return the MultiLineString of each route')
    optional(:geometry_polyline, type: Boolean, desc: 'Encode the MultiLineString')
    optional(:intermediate_solutions, type: Boolean, desc: 'Return intermediate solutions if available')
    optional(:csv, type: Boolean, desc: 'The output is a CSV file if you do not specify api format')
    optional(:allow_empty_result, type: Boolean, desc: 'Allow no solution from the solver used')
  end

  params :vrp_request_schedule do
    optional(:range_indices, type: Hash, desc: '(Scheduling only) Day indices within the plan has to be build') do
      use :vrp_request_indice_range
    end
    optional(:range_date, type: Hash, desc: '(Scheduling only) Define the total period to consider') do
      use :vrp_request_date_range
    end

    mutually_exclusive :range_indices, :range_date
    optional(:unavailable_indices, type: Array[Integer], desc: '(Scheduling only) Exclude some days indices from the resolution')
    optional(:unavailable_date, type: Array[Date], desc: '(Scheduling only) Exclude some days from the resolution')
    mutually_exclusive :unavailable_indices, :unavailable_date

    optional(:unavailable_index_ranges, type: Array, desc:
      '(Scheduling only) Day index ranges where no routes should be generated') do
      use :vrp_request_indice_range
    end
    optional(:unavailable_date_ranges, type: Array, desc:
      '(Scheduling only) Date ranges where no routes should be generated') do
      use :vrp_request_date_range
    end
    mutually_exclusive :unavailable_index_ranges, :unavailable_date_ranges
  end

  params :vrp_request_indice_range do
    optional(:start, type: Integer, desc: 'Beginning of the range')
    optional(:end, type: Integer, desc: 'End of the range')
  end

  params :vrp_request_date_range do
    optional(:start, type: Date, desc: 'Beginning of the range in date format')
    optional(:end, type: Date, desc: 'End of the range in date format')
  end
end

module VrpMisc
  extend Grape::API::Helpers

  params :vrp_request_matrices do
    requires(:id, type: String, allow_blank: false)
    optional(:time, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of time, travel duration between each pair of point in the problem. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix.')
    optional(:distance, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of distance, travel distance between each pair of point in the problem. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix.')
    optional(:value, type: Array[Array[Float]], allow_blank: false, desc: 'Matrix of values, travel value between each pair of point in the problem if not distance or time related. It must be send as an Array[Array[Float]] as it could potentially be non squared matrix.')
  end

  params :vrp_request_relation do
    requires(:type, type: String, allow_blank: false, values: %w[same_route sequence order minimum_day_lapse maximum_day_lapse
                                                                 shipment meetup
                                                                 minimum_duration_lapse maximum_duration_lapse
                                                                 force_first never_first force_end
                                                                 vehicle_group_duration vehicle_group_duration_on_weeks
                                                                 vehicle_group_duration_on_months vehicle_group_number],
                    desc: 'Relations allow to define constraints explicitly between activities and/or vehicles.
                           It could be the following types: same_route, sequence, order, minimum_day_lapse, maximum_day_lapse,
                           shipment, meetup, minimum_duration_lapse, maximum_duration_lapse')
    optional(:lapse, type: Integer, desc: 'Only used for relations implying a duration constraint : minimum/maximum day lapse, vehicle group durations...')
    optional(:linked_ids, type: Array[String], allow_blank: false, desc: 'List of activities involved in the relation', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    optional(:linked_vehicle_ids, type: Array[String], allow_blank: false, desc: 'List of vehicles involved in the relation', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    optional(:periodicity, type: Integer, documentation: { hidden: true }, desc: 'In the case of planning optimization, number of weeks/months to consider at the same time/in each relation : vehicle group duration on weeks/months')
    at_least_one_of :linked_ids, :linked_vehicle_ids
  end

  params :vrp_request_route do
    optional(:vehicle_id, type: String, desc: 'Vehicle linked to the current described route')
    optional(:indice, type: Integer, documentation: { hidden: true }, desc: '[ DEPRECATED : use day_index instead ]')
    optional(:index, type: Integer, desc: 'Index of the route. Must be provided if first_solution_strategy is \'periodic\'.')
    optional(:date, type: Date, desc: 'Date of the route. Must be provided if first_solution_strategy is \'periodic\'.')
    requires(:mission_ids, type: Array[String], desc: 'Initial state or partial state of the current vehicle route', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    mutually_exclusive :indice, :index, :day
  end

  params :vrp_request_subtour do
    requires(:id, type: String, allow_blank: false, desc: '')
    optional(:time_bounds, type: Integer, desc: 'Time limit from the transmodal points (Isochrone)')
    optional(:distance_bounds, type: Integer, desc: 'Distance limit from the transmodal points (Isodistanche)')
    optional(:router_mode, type: String, desc: '`car`, `truck`, `bicycle`, etc... See the Router Wrapper API doc')
    optional(:router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance')
    optional(:speed_multiplier, type: Float, default: 1.0, desc: 'multiply the current modality speed, default : 1.0')
    optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this subtour', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    optional(:duration, type: Integer, desc: 'Maximum subtour duration')
    optional(:transmodal_stops, type: Array, desc: 'Point where the vehicles can park and start the subtours') do
      use :vrp_request_point
    end
    optional(:capacities, type: Array, desc: 'Define the limit of entities the subtour modality can handle') do
      use :vrp_request_capacity
    end
    exactly_one_of :time_bounds, :distance_bounds
  end

  params :vrp_request_zone do
    requires(:id, type: String, allow_blank: false, desc: '')
    requires(:polygon, type: Hash, desc: 'Geometry which describes the area')
    optional(:allocations, type: Array[Array[String]], desc: 'Define by which vehicle or vehicles combination the zone could be served')
  end
end

module VrpMissions
  extend Grape::API::Helpers

  params :vrp_request_rest do
    requires(:id, type: String, allow_blank: false)
    requires(:duration, type: Integer, default: 0, desc: 'Duration of the vehicle rest', coerce_with: ->(value) { ScheduleType.type_cast(value) })
    optional(:timewindows, type: Array, desc: 'Time slot while the rest may begin') do
      use :vrp_request_timewindow
    end
    optional(:late_multiplier, type: Float, desc: 'Late multiplier applied for this rest')
    optional(:exclusion_cost, type: Float, desc: 'Cost induced by non affectation of this rest')
  end

  params :vrp_request_service do
    requires(:id, type: String, allow_blank: false)
    optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8, default is 4. 0 is the highest priority level). Not available with same_point_day option.')
    optional(:exclusion_cost, type: Integer, desc: 'Exclusion cost')

    optional(:visits_number, type: Integer, coerce_with: ->(val) { val.to_i.positive? && val.to_i }, default: 1, allow_blank: false, desc: '(Scheduling only) Total number of visits over the complete schedule (including the unavailable visit indices)')

    optional(:unavailable_visit_indices, type: Array[Integer], desc: '(Scheduling only) unavailable indices of visit')

    optional(:unavailable_visit_day_indices, type: Array[Integer], desc: '(Scheduling only) Express the exceptionnals days indices of unavailabilty')
    optional(:unavailable_visit_day_date, type: Array, desc: '(Scheduling only) Express the exceptionnals days of unavailability')
    mutually_exclusive :unavailable_visit_day_indices, :unavailable_visit_day_date

    optional(:minimum_lapse, type: Float, desc: '(Scheduling only) Minimum day lapse between two visits')
    optional(:maximum_lapse, type: Float, desc: '(Scheduling only) Maximum day lapse between two visits')
    optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the service is assigned', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this service. Not available with periodic heuristic.', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })

    optional(:type, type: Symbol, desc: '`service`, `pickup` or `delivery`. Only service type is available with periodic heuristic.')
    optional(:activity, type: Hash, desc: 'Details of the activity performed to accomplish the current service') do
      use :vrp_request_activity
    end
    optional(:activities, type: Array, desc: 'Define other possible activities for the service. This allows to assign different timewindows and/or points to a single service.') do
      use :vrp_request_activity
    end
    mutually_exclusive :activity, :activities
    optional(:quantity_ids, type: String, documentation: { hidden: true }, desc: 'Quantities to consider, CSV front only')
    optional(:quantities, type: Array, desc: 'Define the entities which are taken or dropped') do
      use :vrp_request_quantity
    end
    mutually_exclusive :quantity_ids, :quantities

    optional(:unavailable_index_ranges, type: Array, desc:
      '(Scheduling only) Day index ranges where visits can not take place') do
      use :vrp_request_indice_range
    end
    optional(:unavailable_date_ranges, type: Array, desc:
      '(Scheduling only) Date ranges where visits can not take place') do
      use :vrp_request_date_range
    end
    mutually_exclusive :unavailable_index_ranges, :unavailable_date_ranges
  end

  params :vrp_request_shipment do
    requires(:id, type: String, allow_blank: false, desc: '')
    optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8, default is 4)')
    optional(:exclusion_cost, type: Integer, desc: 'Exclusion cost')

    optional(:visits_number, type: Integer, coerce_with: ->(val) { val.to_i.positive? && val.to_i }, default: 1, allow_blank: false, desc: 'Total number of visits over the complete schedule (including the unavailable visit indices)')

    optional(:unavailable_visit_indices, type: Array[Integer], desc: '(Scheduling only) unavailable indices of visit')

    optional(:unavailable_visit_day_indices, type: Array[Integer], desc: '(Scheduling only) Express the exceptionnals days indices of unavailabilty')
    optional(:unavailable_visit_day_date, type: Array, desc: '(Scheduling only) Express the exceptionnals days of unavailability')
    mutually_exclusive :unavailable_visit_day_indices, :unavailable_visit_day_date

    optional(:minimum_lapse, type: Float, desc: 'Minimum day lapse between two visits')
    optional(:maximum_lapse, type: Float, desc: 'Maximum day lapse between two visits')

    optional(:maximum_inroute_duration, type: Integer, desc: 'Maximum in route duration of this particular shipment (Must be feasible !)')
    optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the shipment is assigned', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this shipment', coerce_with: ->(val) { val.is_a?(String) ? val.split(/,/) : val })
    requires(:pickup, type: Hash, allow_blank: false, desc: 'Activity of collection') do
      use :vrp_request_activity
    end
    requires(:delivery, type: Hash, allow_blank: false, desc: 'Activity of drop off') do
      use :vrp_request_activity
    end
    optional(:direct, type: Boolean, default: false, desc: 'When activated, vehicle should go directly to delivery point after pick up')
    optional(:quantity_ids, type: String, documentation: { hidden: true }, desc: 'Quantities to consider, CSV front only')
    optional(:quantities, type: Array, desc: 'Define the entities which are taken and dropped') do
      use :vrp_request_quantity
    end
    mutually_exclusive :quantity_ids, :quantities

    optional(:unavailable_index_ranges, type: Array, desc:
      '(Scheduling only) Day index ranges where visits can not take place') do
      use :vrp_request_indice_range
    end
    optional(:unavailable_date_ranges, type: Array, desc:
      '(Scheduling only) Date ranges where visits can not take place') do
      use :vrp_request_date_range
    end
    mutually_exclusive :unavailable_index_ranges, :unavailable_date_ranges
  end
end

module VrpShared
  extend Grape::API::Helpers

  params :vrp_request_activity do
    optional(:position, type: Symbol, default: :neutral, values: [:neutral, :always_first, :always_middle, :always_last, :never_first, :never_middle, :never_last], desc: 'Provides an indication on when to do this service among whole route', coerce_with: ->(value) { value.to_sym })
    optional(:duration, type: Integer, default: 0, desc: 'Time while the current activity stands until it\'s over (in seconds)', coerce_with: ->(value) { ScheduleType.type_cast(value) })
    optional(:additional_value, type: Integer, desc: 'Additional value associated to the visit')
    optional(:setup_duration, type: Integer, default: 0, desc: 'Time at destination before the proper activity is effectively performed', coerce_with: ->(value) { ScheduleType.type_cast(value) })
    optional(:late_multiplier, type: Float, desc: '(ORtools only) Overrides the late_multiplier defined at the vehicle level')
    optional(:timewindow_start_day_shift_number, documentation: { hidden: true }, type: Integer, desc: '[ DEPRECATED ]')
    requires(:point_id, type: String, allow_blank: false, desc: 'Reference to the associated point')
    optional(:timewindow_ids, type: String, documentation: { hidden: true }, desc: 'Timewindows to consider, CSV front only')
    optional(:timewindows, type: Array, desc: 'Time slot while the activity may start') do
      use :vrp_request_timewindow
    end
    mutually_exclusive :timewindow_ids, :timewindows
  end

  params :vrp_request_capacity do
    optional(:id, type: String)
    requires(:unit_id, type: String, allow_blank: false, desc: 'Unit of the capacity')
    requires(:limit, type: Float, allow_blank: false, desc: 'Maximum capacity that can be carried')
    optional(:initial, type: Float, desc: 'Initial quantity value loaded in the vehicle')
    optional(:overload_multiplier, type: Float, desc: 'Allows to exceed the limit against this cost (ORtools only)')
  end

  params :vrp_request_point do
    requires(:id, type: String, allow_blank: false)
    optional(:matrix_index, type: Integer, allow_blank: false, desc: 'Index within the matrices, required if the matrices are already given')
    optional(:location, type: Hash, allow_blank: false, documentation: { desc: 'Location of the point if matrices are not given' }) do
      self.requires(:lat, type: Float, allow_blank: false, desc: 'Latitude coordinate')
      self.requires(:lon, type: Float, allow_blank: false, desc: 'Longitude coordinate')
    end
    at_least_one_of :matrix_index, :location
  end

  params :vrp_request_quantity do
    optional(:id, type: String)
    requires(:unit_id, type: String, allow_blank: false, desc: 'Unit related to this quantity')
    optional(:fill, type: Boolean, desc: 'Allows to fill with quantity, until this unit vehicle capacity is full')
    optional(:empty, type: Boolean, desc: 'Allows to empty this quantity, until this unit vehicle capacity reaches zero')
    mutually_exclusive :fill, :empty
    optional(:value, type: Float, desc: 'Value of current quantity')
    optional(:setup_value, type: Integer, desc: 'If the associated unit is a counting one, defines the default value to count for this stop (additional quantities for this specific service are to define with the value tag)')
  end

  params :vrp_request_timewindow do
    optional(:id, type: String)
    optional(:start,
             type: Integer, coerce_with: ->(value) { ScheduleType.type_cast(value || 0) },
             desc: 'Beginning of the current timewindow in seconds')
    optional(:end,
             type: Integer, coerce_with: ->(value) { ScheduleType.type_cast(value) },
             desc: 'End of the current timewindow in seconds')
    optional(:day_index,
             type: Integer, values: 0..6,
             desc: '(Scheduling only) Day index of the current timewindow within the periodic week,
                    (monday = 0, ..., sunday = 6)')
    at_least_one_of :start, :end, :day_index
  end

  params :vrp_request_unit do
    requires(:id, type: String, allow_blank: false)
    optional(:label, type: String, desc: 'Name of the unit')
    optional(:counting, type: Boolean, desc: 'Define if the unit is a counting one, which allows to count the number of stops in a single route')
  end
end

module VrpVehicles
  extend Grape::API::Helpers

  params :vrp_request_vehicle do
    use :router_options, :vehicle_costs, :vehicle_model_related
    requires(:id, type: String, allow_blank: false)

    optional(:coef_setup, type: Float, desc: 'Coefficient applied to every setup duration defined in the tour, for this vehicle. Not taken into account within periodic heuristic.')
    optional(:additional_setup, type: Float, desc: 'Constant additional setup duration for all setup defined in the tour, for this vehicle. Not taken into account within periodic heuristic.')
    optional(:coef_service, type: Float, desc: 'Coefficient applied to every service duration defined in the tour, for this vehicle. Not taken into account within periodic heuristic.')
    optional(:additional_service, type: Float, desc: 'Constant additional service time for all travel defined in the tour, for this vehicle. Not taken into account within periodic heuristic.')
    optional(:force_start, type: Boolean, documentation: { hidden: true }, desc: '[ DEPRECATED ]')
    optional(:shift_preference, type: String, values: ['force_start', 'force_end', 'minimize_span'], desc: 'Force the vehicle to start as soon as the vehicle timewindow is open,
      as late as possible or let vehicle start at any time. Not available with periodic heuristic, it will always leave as soon as possible.')
    optional(:trips, type: Integer, default: 1, desc: 'The number of times a vehicle is allowed to return to the depot within its route. Not available with periodic heuristic.')

    optional :matrix_id, type: String, desc: 'Related matrix, if already defined'
    optional :value_matrix_id, type: String, desc: 'If any value matrix defined, related matrix index'

    optional(:duration, type: Integer, values: ->(v) { v.positive? }, desc: 'Maximum tour duration', coerce_with: ->(value) { ScheduleType.type_cast(value) })
    optional(:overall_duration, type: Integer, values: ->(v) { v.positive? }, documentation: { hidden: true }, desc: '(Scheduling only) If schedule covers several days, maximum work duration over whole period. Not available with periodic heuristic.', coerce_with: ->(value) { ScheduleType.type_cast(value) })
    optional(:distance, type: Integer, desc: 'Maximum tour distance. Not available with periodic heuristic.')
    optional(:maximum_ride_time, type: Integer, desc: 'Maximum ride duration between two route activities')
    optional(:maximum_ride_distance, type: Integer, desc: 'Maximum ride distance between two route activities')
    optional :skills, type: Array[Array[String]], desc: 'Particular abilities which could be handle by the vehicle. This parameter is a set of alternative skills, and must be defined as an Array[Array[String]]. Not available with periodic heuristic.',
                      coerce_with: ->(val) { val.is_a?(String) ? [val.split(/,/).map(&:strip)] : val } # TODO : Create custom coerce to consider multiple alternatives

    optional(:unavailable_work_day_indices, type: Array[Integer], desc: '(Scheduling only) Express the exceptionnals indices of unavailabilty')
    optional(:unavailable_work_date, type: Array, desc: '(Scheduling only) Express the exceptionnals days of unavailability')
    mutually_exclusive :unavailable_work_day_indices, :unavailable_work_date

    optional(:unavailable_index_ranges, type: Array, desc:
      '(Scheduling only) Day index ranges where vehicle is not available') do
      use :vrp_request_indice_range
    end
    optional(:unavailable_date_ranges, type: Array, desc:
      '(Scheduling only) Date ranges where vehicle is not available') do
      use :vrp_request_date_range
    end
    mutually_exclusive :unavailable_index_ranges, :unavailable_date_ranges

    optional(:free_approach, type: Boolean, desc: 'Do not take into account the route leaving the depot in the objective. Not available with periodic heuristic.')
    optional(:free_return, type: Boolean, desc: 'Do not take into account the route arriving at the depot in the objective. Not available with periodic heuristic.')
  end

  params :vehicle_costs do
    optional(:cost_fixed, type: Float, desc: 'Cost applied if the vehicle is used')
    optional(:cost_distance_multiplier, type: Float, desc: 'Cost applied to the distance performed')

    optional(:cost_time_multiplier, type: Float, desc: 'Cost applied to the total time of route (ORtools). Not taken into account within periodic heuristic.')
    optional(:cost_value_multiplier, type: Float, desc: 'Multiplier applied to the value matrix and additional activity value. Not taken into account within periodic heuristic.')
    optional(:cost_waiting_time_multiplier, type: Float, desc: 'Cost applied to the waiting time in the route. Not taken into account within periodic heuristic.')
    optional(:cost_late_multiplier, type: Float, desc: 'Cost applied if a point is delivered late (ORtools only). Not taken into account within periodic heuristic.')
    optional(:cost_setup_time_multiplier, type: Float, desc: 'DEPRECATED : Jsprit solver and related parameters are not supported anymore')
  end

  params :vehicle_model_related do
    optional(:start_point_id, type: String, desc: 'Begin of the tour')
    optional(:end_point_id, type: String, desc: 'End of the tour')
    optional(:capacity_ids, type: String, documentation: { hidden: true }, desc: 'Capacities to consider, CSV front only')
    optional(:capacities, type: Array, desc: 'Define the limit of entities the vehicle could carry') do
      use :vrp_request_capacity
    end
    mutually_exclusive :capacity_ids, :capacities

    optional(:sequence_timewindow_ids, type: Array[String], documentation: { hidden: true }, desc: 'Sequence timewindows to consider, CSV front only',
                                       coerce_with: ->(val) { val.split(/,/).map(&:strip) })
    optional(:sequence_timewindows, type: Array, desc: '(Scheduling only) Define the vehicle work schedule over a period') do
      use :vrp_request_timewindow
    end
    optional(:timewindow_id, type: String, desc: 'Sequence timewindows to consider')
    optional(:timewindow, type: Hash, desc: 'Time window whithin the vehicle may be on route') do
      use :vrp_request_timewindow
    end
    mutually_exclusive :sequence_timewindows, :sequence_timewindow_ids, :timewindow

    optional(:rest_ids, type: Array[String], desc: 'Rests within the route. Not available with periodic heuristic.')
  end

  params :router_options do
    optional :router_mode, type: String, desc: '`car`, `truck`, `bicycle`, etc... See the Router Wrapper API doc.'
    exactly_one_of :matrix_id, :router_mode
    optional :router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance'
    optional :speed_multiplier, type: Float, default: 1.0, desc: 'Multiplies the vehicle speed, default : 1.0. Specifies if this vehicle is faster or slower than average speed.'
    optional :area, type: Array, coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |b| b.split(',').collect{ |f| Float(f) } } : c }, desc: 'List of latitudes and longitudes separated with commas. Areas separated with pipes (available only for truck mode at this time).'
    optional :speed_multiplier_area, type: Array[Float], coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |f| Float(f) } : c }, desc: 'Speed multiplier per area, 0 to avoid area. Areas separated with pipes (available only for truck mode at this time).'
    optional :traffic, type: Boolean, desc: 'Take into account traffic or not'
    optional :departure, type: DateTime, desc: 'Departure date time (only used if router supports traffic)'
    optional :track, type: Boolean, default: true, desc: 'Use track or not'
    optional :motorway, type: Boolean, default: true, desc: 'Use motorway or not'
    optional :toll, type: Boolean, default: true, desc: 'Use toll section or not'
    optional :trailers, type: Integer, desc: 'Number of trailers'
    optional :weight, type: Float, desc: 'Vehicle weight including trailers and shipped goods, in tons'
    optional :weight_per_axle, type: Float, desc: 'Weight per axle, in tons'
    optional :height, type: Float, desc: 'Height in meters'
    optional :width, type: Float, desc: 'Width in meters'
    optional :length, type: Float, desc: 'Length in meters'
    optional :hazardous_goods, type: Symbol, values: [:explosive, :gas, :flammable, :combustible, :organic, :poison, :radio_active, :corrosive, :poisonous_inhalation, :harmful_to_water, :other], desc: 'List of hazardous materials in the vehicle'
    optional :max_walk_distance, type: Float, default: 750, desc: 'Max distance by walk'
    optional :approach, type: Symbol, values: [:unrestricted, :curb], default: :unrestricted, desc: 'Arrive/Leave in the traffic direction'
    optional :snap, type: Float, desc: 'Snap waypoint to junction close by snap distance'
    optional :strict_restriction, type: Boolean, desc: 'Strict compliance with truck limitations'
  end
end
