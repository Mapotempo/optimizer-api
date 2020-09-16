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
require './lib/tsp_helper.rb'
require './models/base'
require './models/concerns/distance_matrix'
require './models/concerns/expand_data'
require './models/concerns/periodic_service'

module Models
  class Vrp < Base
    include DistanceMatrix
    include ExpandData
    include PeriodicService

    field :name, default: nil
    field :preprocessing_max_split_size, default: nil
    field :preprocessing_partition_method, default: nil
    field :preprocessing_partition_metric, default: nil
    field :preprocessing_kmeans_centroids, default: nil
    field :preprocessing_cluster_threshold, default: nil
    field :preprocessing_force_cluster, default: false
    field :preprocessing_prefer_short_segment, default: false
    field :preprocessing_neighbourhood_size, default: nil
    field :preprocessing_heuristic_result, default: {}
    field :preprocessing_heuristic_synthesis, default: nil
    field :preprocessing_first_solution_strategy, default: nil
    has_many :preprocessing_partitions, class_name: 'Models::Partition'

    # The following 7 variables are used for dicho development
    # TODO: Wait for the dev to finish to expose the dicho parameters
    field :resolution_dicho_level_coeff, default: 1.1 # This variable is calculated inside dicho by default (TODO: check if it is really necessary)
    field :resolution_dicho_algorithm_service_limit, default: 500
    field :resolution_dicho_algorithm_vehicle_limit, default: 10
    field :resolution_dicho_division_service_limit, default: 100 # This variable needs to corrected using the average number of services per vehicle.
    field :resolution_dicho_division_vehicle_limit, default: 3
    field :resolution_dicho_exclusion_scaling_angle, default: 38
    field :resolution_dicho_exclusion_rate, default: 0.6

    field :resolution_duration, default: nil
    field :resolution_total_duration, default: nil
    field :resolution_iterations, default: nil
    field :resolution_iterations_without_improvment, default: nil
    field :resolution_stable_iterations, default: nil
    field :resolution_stable_coefficient, default: nil
    field :resolution_initial_time_out, default: nil
    field :resolution_minimum_duration, default: nil
    field :resolution_init_duration, default: nil
    field :resolution_time_out_multiplier, default: nil
    field :resolution_vehicle_limit, default: nil
    field :resolution_solver, default: true
    field :resolution_same_point_day, default: false
    field :resolution_minimize_days_worked, default: false
    field :resolution_allow_partial_assignment, default: true
    field :resolution_evaluate_only, default: false
    field :resolution_split_number, default: 1
    field :resolution_total_split_number, default: 2
    field :resolution_several_solutions, default: 1
    field :resolution_variation_ratio, default: nil
    field :resolution_batch_heuristic, default: false
    field :resolution_repetition, default: nil

    field :restitution_geometry, default: false
    field :restitution_geometry_polyline, default: false
    field :restitution_intermediate_solutions, default: true
    field :restitution_csv, default: false
    field :restitution_allow_empty_result, default: false

    field :schedule_range_indices, default: nil # extends schedule_range_date
    field :schedule_unavailable_indices, default: [] # extends unavailable_date
    field :schedule_months_indices, default: []

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    #
    # validates_numericality_of :preprocessing_max_split_size, allow_nil: true
    # validates_numericality_of :preprocessing_cluster_threshold, allow_nil: true
    # validates_numericality_of :resolution_duration, allow_nil: true
    # validates_numericality_of :resolution_iterations, allow_nil: true
    # validates_numericality_of :resolution_iterations_without_improvment, allow_nil: true
    # validates_numericality_of :resolution_stable_iterations, allow_nil: true
    # validates_numericality_of :resolution_stable_coefficient, allow_nil: true
    # validates_numericality_of :resolution_initial_time_out, allow_nil: true
    # validates_numericality_of :resolution_minimum_duration, allow_nil: true
    # validates_numericality_of :resolution_time_out_multiplier, allow_nil: true
    # validates_numericality_of :resolution_vehicle_limit, allow_nil: true
    # validates_numericality_of :resolution_several_solutions, allow_nil: true
    # validates_numericality_of :resolution_variation_ratio, allow_nil: true
    #
    # validates_inclusion_of :preprocessing_partition_method, allow_nil: true, in: %w[hierarchical_tree balanced_kmeans]

    has_many :matrices, class_name: 'Models::Matrix'
    has_many :points, class_name: 'Models::Point'
    has_many :units, class_name: 'Models::Unit'
    has_many :rests, class_name: 'Models::Rest'
    has_many :timewindows, class_name: 'Models::Timewindow'
    has_many :capacities, class_name: 'Models::Capacity'
    has_many :quantities, class_name: 'Models::Quantity'
    has_many :vehicles, class_name: 'Models::Vehicle'
    has_many :services, class_name: 'Models::Service'
    has_many :shipments, class_name: 'Models::Shipment'
    has_many :relations, class_name: 'Models::Relation'
    has_many :routes, class_name: 'Models::Route'
    has_many :subtours, class_name: 'Models::Subtour'
    has_many :zones, class_name: 'Models::Zone'

    def self.create(hash, delete = true)
      Models.delete_all if delete

      vrp = super({})
      self.check_consistency(hash)
      self.ensure_retrocompatibility(hash)
      self.filter(hash) # TODO : add filters.rb here
      [:name, :matrices, :units, :points, :rests, :zones, :capacities, :quantities, :timewindows,
       :vehicles, :services, :shipments, :relations, :subtours, :routes, :configuration].each{ |key|
        vrp.send("#{key}=", hash[key]) if hash[key]
      }

      self.expand_data(vrp)

      vrp
    end

    def self.check_consistency(hash)
      # matrix_id consistency
      hash[:vehicles]&.each{ |v|
        if v[:matrix_id] && (hash[:matrices].nil? || hash[:matrices].none?{ |m| m[:id] == v[:matrix_id] })
          raise OptimizerWrapper::DiscordantProblemError, 'There is no matrix with id vehicle[:matrix_id]'
        end
      }

      # matrix_index consistency
      if hash[:matrices].nil? || hash[:matrices].empty?
        raise OptimizerWrapper::DiscordantProblemError, 'There is a point with point[:matrix_index] defined but there is no matrix' if hash[:points]&.any?{ |p| p[:matrix_index] }
      else
        max_matrix_index = hash[:points].max{ |p| p[:matrix_index] || -1 }[:matrix_index] || -1
        matrix_not_big_enough = hash[:matrices].any?{ |matrix_group|
          Models::Matrix.field_names.any?{ |dimension|
            matrix_group[dimension] && (matrix_group[dimension].size <= max_matrix_index || matrix_group[dimension].any?{ |col| col.size <= max_matrix_index })
          }
        }
        raise OptimizerWrapper::DiscordantProblemError, 'All matrices should have at least maximum(point[:matrix_index]) number of rows and columns' if matrix_not_big_enough
      end

      # shipment position consistency
      forbidden_position_pairs = [[:always_middle, :always_first], [:always_last, :always_middle], [:always_last, :always_first]]
      hash[:shipments]&.each{ |shipment|
        raise OptimizerWrapper::DiscordantProblemError, 'Unconsistent positions in shipments.' if forbidden_position_pairs.include?([shipment[:pickup][:position], shipment[:delivery][:position]])
      }

      # routes consistency
      periodic = hash[:configuration] && hash[:configuration][:preprocessing] && hash[:configuration][:preprocessing][:first_solution_strategy].to_a.include?('periodic')
      hash[:routes]&.each{ |route|
        route[:mission_ids].each{ |id|
          corresponding_service = hash[:services]&.find{ |s| s[:id] == id } || hash[:shipments]&.find{ |s| s[:id] == id }

          raise OptimizerWrapper::DiscordantProblemError, 'Each mission_ids should refer to an existant service or shipment' if corresponding_service.nil?
          raise OptimizerWrapper::UnsupportedProblemError, 'Services in initialize routes should have only one activity' if corresponding_service[:activities] && periodic
        }
      }

      configuration = hash[:configuration]
      return unless configuration

      # configuration consistency
      if configuration[:preprocessing]
        if configuration[:preprocessing][:partitions]&.any?{ |partition| partition[:entity].to_sym == :work_day }
          if hash[:services].any?{ |s| (s[:visits_number] || 1) > 1 && (s[:minimum_lapse] || 1) < 7 && s[:maximum_lapse] && s[:maximum_lapse] < 7 }
            raise OptimizerWrapper::DiscordantProblemError, 'Work day partition implies that lapses of all services can be a multiple of 7. There are services whose minimum and maximum lapse do not permit such lapse'
          end
        end
      end

      if configuration[:resolution]
        if configuration[:resolution][:solver] && configuration[:resolution][:solver_parameter].to_i == -1 ||
           !configuration[:resolution][:solver].nil? && configuration[:resolution][:solver] == false && configuration[:resolution][:solver_parameter] && configuration[:resolution][:solver_parameter] != -1
          raise OptimizerWrapper::DiscordantProblemError, 'Deprecated and new solver parameter used at the same time with uncompatible values'
        end
      end

      # periodic consistency
      return unless periodic

      if hash[:relations]
        incompatible_relation_types = hash[:relations].collect{ |r| r[:type] }.uniq - ['force_first', 'never_first', 'force_end']
        raise OptimizerWrapper::DiscordantProblemError, "#{incompatible_relation_types} relations not available with specified first_solution_strategy" unless incompatible_relation_types.empty?
      end

      raise OptimizerWrapper::DiscordantProblemError, 'Vehicle group duration on weeks or months is not available with schedule_range_date.' if hash[:relations].to_a.any?{ |relation| relation[:type] == 'vehicle_group_duration_on_months' } &&
                                                                                                                                                (!configuration[:schedule] || configuration[:schedule][:range_indice])

      raise OptimizerWrapper::DiscordantProblemError, 'Shipments are not available with periodic heuristic.' unless hash[:shipments].to_a.empty?

      raise OptimizerWrapper::DiscordantProblemError, 'Rests are not available with periodic heuristic.' unless hash[:vehicles].all?{ |vehicle| vehicle[:rests].to_a.empty? }
    end

    def self.expand_data(vrp)
      vrp.add_sticky_vehicle_if_routes_and_partitions
      vrp.adapt_relations_between_shipments
      vrp.expand_unavailable_indices
      vrp.provide_original_ids
    end

    def self.convert_position_relations(hash)
      relations_to_remove = []
      hash[:relations].to_a.each_with_index{ |r, r_i|
        case r[:type]
        when 'force_first'
          r[:linked_ids].each{ |id|
            to_modify = [hash[:services], hash[:shipments]].flatten.find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Force first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :always_first
          }
          relations_to_remove << r_i
        when 'never_first'
          r[:linked_ids].each{ |id|
            to_modify = [hash[:services], hash[:shipments]].flatten.find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Never first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :never_first
          }
          relations_to_remove << r_i
        when 'force_end'
          r[:linked_ids].each{ |id|
            to_modify = [hash[:services], hash[:shipments]].flatten.find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Force end relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :always_last
          }
          relations_to_remove << r_i
        end
      }

      relations_to_remove.reverse_each{ |index| hash[:relations].delete_at(index) }
    end

    def self.deduce_solver_parameter(hash)
      if hash[:configuration] && hash[:configuration][:resolution] && hash[:configuration][:resolution][:solver_parameter]
        if hash[:configuration][:resolution][:solver_parameter] == -1
          hash[:configuration][:resolution][:solver] = false
        else
          correspondant = { 0 => 'path_cheapest_arc', 1 => 'global_cheapest_arc', 2 => 'local_cheapest_insertion', 3 => 'savings', 4 => 'parallel_cheapest_insertion', 5 => 'first_unbound', 6 => 'christofides' }
          hash[:configuration][:resolution][:solver] = true
          hash[:configuration][:preprocessing][:first_solution_strategy] = [correspondant[hash[:configuration][:resolution][:solver_parameter]]]
        end
      end
    end

    def self.convert_route_indice_into_index(hash)
      hash[:routes].to_a.each{ |route|
        next unless route[:indice]

        log 'Route indice was used instead of route index', level: :warn
        route[:day_index] = route[:indice]
        route.delete(:indice)
      }
    end

    def self.ensure_retrocompatibility(hash)
      self.convert_position_relations(hash)
      self.deduce_solver_parameter(hash)
      self.convert_route_indice_into_index(hash)
    end

    def self.filter(hash)
      return hash if hash.empty?

      self.remove_unecessary_units(hash)
      self.generate_schedule_indices_from_date(hash)
    end

    def self.remove_unecessary_units(hash)
      return hash if !hash[:units] || !hash[:vehicles] || (!hash[:services] && !hash[:shipments])

      vehicle_capacities = hash[:vehicles]&.map{ |v| v[:capacities] || [] }&.flatten&.uniq
      service_quantities = hash[:services]&.map{ |s| s[:quantities] || [] }&.flatten&.uniq
      shipment_quantities = hash[:shipments]&.map{ |s| s[:quantities] || [] }&.flatten&.uniq

      capacities_units = hash[:capacities]&.map{ |c| c[:unit_id] } || vehicle_capacities&.map{ |c| c[:unit_id] }
      quantities_units = (hash[:quantities]&.map{ |q| q[:unit_id] } || []) +
                         (service_quantities&.map{ |q| q[:unit_id] } || []) +
                         (shipment_quantities&.map{ |q| q[:unit_id] } || [])

      needed_units = capacities_units & quantities_units.uniq
      hash[:units].delete_if{ |u| needed_units.exclude? u[:id] }

      rejected_capacities = hash[:capacities]&.select{ |capacity| needed_units.exclude? capacity[:unit_id] }&.map{ |capacity| capacity[:id] } || []
      rejected_quantities = hash[:quantities]&.select{ |quantity| needed_units.exclude? quantity[:unit_id] }&.map{ |quantity| quantity[:id] } || []

      hash[:vehicles]&.map{ |v| rejected_capacities.each { |r_c| v[:capacity_ids]&.gsub!(/\b#{r_c}\b/, '') } }
      hash[:services]&.map{ |s| rejected_quantities.each { |r_q| s[:quantity_ids]&.gsub!(/\b#{r_q}\b/, '') } }
      hash[:shipments]&.map{ |s| rejected_quantities.each { |r_q| s[:quantity_ids]&.gsub!(/\b#{r_q}\b/, '') } }

      hash[:capacities]&.delete_if{ |capacity| rejected_capacities.include? capacity[:id] }
      hash[:quantities]&.delete_if{ |quantity| rejected_quantities.include? quantity[:id] }

      hash[:vehicles]&.map{ |v| (v[:capacities] || []).delete_if{ |capacity| needed_units.exclude? capacity[:unit_id] } }
      hash[:services]&.map{ |v| (v[:quantities] || []).delete_if{ |quantity| needed_units.exclude? quantity[:unit_id] } }
      hash[:shipments]&.map{ |s| (s[:quantities] || []).delete_if{ |quantity| needed_units.exclude? quantity[:unit_id] } }
    end

    def self.generate_schedule_indices_from_date(hash)
      return hash if !hash[:configuration] || !hash[:configuration][:schedule] ||
                     hash[:configuration][:schedule][:range_indices]

      start_indice = hash[:configuration][:schedule][:range_date][:start].to_date.cwday - 1
      end_indice = (hash[:configuration][:schedule][:range_date][:end].to_date - hash[:configuration][:schedule][:range_date][:start].to_date).to_i + start_indice

      # remove service unavailable_visit_day_date
      [hash[:services].to_a + hash[:shipments].to_a].flatten.each{ |s|
        next if s[:unavailable_visit_day_date].to_a.empty?

        s[:unavailable_visit_day_indices] = [] unless s[:unavailable_visit_day_indices]
        s[:unavailable_visit_day_indices] += s[:unavailable_visit_day_date].to_a.collect{ |unavailable_date|
          (unavailable_date.to_date - hash[:configuration][:schedule][:range_date][:start]).to_i + start_indice
        }.compact
        s.delete(:unavailable_visit_day_date)
      }

      # remove vehicle unavailable_work_date
      hash[:vehicles].each{ |vehicle|
        next if vehicle[:unavailable_work_date].to_a.empty?

        vehicle[:unavailable_work_day_indices] = [] unless vehicle[:unavailable_work_day_indices]
        vehicle[:unavailable_work_day_indices] += vehicle[:unavailable_work_date].collect{ |unavailable_date|
          (unavailable_date.to_date - hash[:configuration][:schedule][:range_date][:start]).to_i + start_indice
        }.compact
        vehicle.delete(:unavailable_work_date)
      }

      # remove schedule unavailable_date
      if hash[:configuration][:schedule]
        hash[:configuration][:schedule][:unavailable_indices] = [] unless hash[:configuration][:schedule][:unavailable_indices]
        hash[:configuration][:schedule][:unavailable_indices] += hash[:configuration][:schedule][:unavailable_date].to_a.collect{ |date|
          (date.to_date - hash[:configuration][:schedule][:range_date][:start]).to_i + start_indice
        }.compact
        hash[:configuration][:schedule].delete(:unavailable_date)
      end

      # provide months
      months_indices = []
      current_month = hash[:configuration][:schedule][:range_date][:start].to_date.month
      current_indices = []
      current_index = start_indice
      (hash[:configuration][:schedule][:range_date][:start].to_date..hash[:configuration][:schedule][:range_date][:end].to_date).each{ |date|
        if date.month == current_month
          current_indices << current_index
        else
          months_indices << current_indices
          current_indices = [current_index]
          current_month = date.month
        end

        current_index += 1
      }
      months_indices << current_indices
      hash[:configuration][:schedule][:month_indices] = months_indices

      # convert route dates into indices
      hash[:routes]&.each{ |route|
        next if route[:day_index]

        route[:day_index] = (route[:date].to_date - hash[:configuration][:schedule][:range_date][:start].to_date).to_i + start_indice
        route.delete(:date)
      }

      # remove schedule_range_date
      hash[:configuration][:schedule][:range_indices] = {
        start: start_indice,
        end: end_indice
      }
      hash[:configuration][:schedule].delete(:range_date)

      hash
    end

    def configuration=(configuration)
      self.preprocessing = configuration[:preprocessing] if configuration[:preprocessing]
      self.resolution = configuration[:resolution] if configuration[:resolution]
      self.schedule = configuration[:schedule] if configuration[:schedule]
      self.restitution = configuration[:restitution] if configuration[:restitution]
    end

    def restitution=(restitution)
      self.restitution_geometry = restitution[:geometry]
      self.restitution_geometry_polyline = restitution[:geometry_polyline]
      self.restitution_intermediate_solutions = restitution[:intermediate_solutions]
      self.restitution_csv = restitution[:csv]
      self.restitution_allow_empty_result = restitution[:allow_empty_result]
    end

    def resolution=(resolution)
      self.resolution_duration = resolution[:duration]
      self.resolution_total_duration = resolution[:duration]
      self.resolution_iterations = resolution[:iterations]
      self.resolution_iterations_without_improvment = resolution[:iterations_without_improvment]
      self.resolution_stable_iterations = resolution[:stable_iterations]
      self.resolution_stable_coefficient = resolution[:stable_coefficient]
      self.resolution_minimum_duration = resolution[:initial_time_out] || resolution[:minimum_duration]
      self.resolution_init_duration = resolution[:init_duration]
      self.resolution_time_out_multiplier = resolution[:time_out_multiplier]
      self.resolution_vehicle_limit = resolution[:vehicle_limit]
      self.resolution_solver = resolution[:solver]
      self.resolution_same_point_day = resolution[:same_point_day]
      self.resolution_minimize_days_worked = resolution[:minimize_days_worked]
      self.resolution_allow_partial_assignment = resolution[:allow_partial_assignment]
      self.resolution_evaluate_only = resolution[:evaluate_only]
      self.resolution_split_number = resolution[:split_number]
      self.resolution_total_split_number = resolution[:total_split_number]
      self.resolution_several_solutions = resolution[:several_solutions]
      self.resolution_variation_ratio = resolution[:variation_ratio]
      self.resolution_batch_heuristic = resolution[:batch_heuristic]
      self.resolution_repetition = resolution[:repetition]
      self.resolution_dicho_algorithm_service_limit = resolution[:dicho_algorithm_service_limit]
    end

    def preprocessing=(preprocessing)
      self.preprocessing_force_cluster = preprocessing[:force_cluster]
      self.preprocessing_max_split_size = preprocessing[:max_split_size]
      self.preprocessing_partition_method = preprocessing[:partition_method]
      self.preprocessing_partition_metric = preprocessing[:partition_metric]
      self.preprocessing_kmeans_centroids = preprocessing[:kmeans_centroids]
      self.preprocessing_cluster_threshold = preprocessing[:cluster_threshold]
      self.preprocessing_prefer_short_segment = preprocessing[:prefer_short_segment]
      self.preprocessing_neighbourhood_size = preprocessing[:neighbourhood_size]
      self.preprocessing_first_solution_strategy = preprocessing[:first_solution_strategy].nil? ? nil : [preprocessing[:first_solution_strategy]].flatten # To make sure that internal vrp conforms with the Grape vrp.
      self.preprocessing_partitions = preprocessing[:partitions]
      self.preprocessing_heuristic_result = {}
    end

    def schedule=(schedule)
      self.schedule_range_indices = schedule[:range_indices]
      self.schedule_unavailable_indices = schedule[:unavailable_indices]
      self.schedule_months_indices = schedule[:month_indices]
    end

    def services_duration
      Helper.services_duration(self.services)
    end

    def visits
      Helper.visits(self.services)
    end

    def activity_count
      visits + self.shipments.size * 2
    end

    def total_work_times
      schedule_start = self.schedule_range_indices[:start]
      schedule_end = self.schedule_range_indices[:end]
      work_times = self.vehicles.collect{ |vehicle|
        vehicle.total_work_time_in_range(schedule_start, schedule_end)
      }
      work_times
    end

    def total_work_time
      total_work_times.sum
    end

    def calculate_service_exclusion_costs(type = :time, force_recalc = false)
      # TODO: This function will calculate an exclusion cost for each service seperately
      # using the time, distance , capacity or a mix of all.
      #
      # It is commited as is due to emercency and it basically prevents optim to use an empty vehicle
      # if there are less than ~15 services (in theory) but due to other costs etc it might be less.
      #
      # type        : [:time, :distance, :capacity]
      # force_recalc: [true, false] For cases where existing exclusion costs needs to be ignored.

      max_fixed_cost = vehicles.max_by(&:cost_fixed).cost_fixed

      if max_fixed_cost <= 0 || (!force_recalc && services.any?{ |service| service.exclusion_cost&.positive? })
        return
      end

      case type
      when :time
        tsp = TSPHelper.create_tsp(self, vehicles.first)
        result = TSPHelper.solve(tsp)
        total_travel_time = result[:cost]

        total_vehicle_work_time = vehicles.map{ |vehicle| vehicle[:duration] || vehicle[:timewindow][:end] - vehicle[:timewindow][:start] }.reduce(:+)
        average_vehicles_work_time = total_vehicle_work_time / vehicles.size.to_f
        total_service_time = services.map{ |service| service[:activity][:duration].to_i }.reduce(:+)

        # TODO: It assumes there is only one uniq location for all vehicle starts and ends
        depot = vehicles.collect(&:start_point).compact[0]
        approx_depot_time_correction = if depot.nil?
                                         0
                                       else
                                         average_loc = points.inject([0, 0]) { |sum, point| [sum[0] + point.location.lat, sum[1] + point.location.lon] }
                                         average_loc = [average_loc[0] / points.size, average_loc[1] / points.size]

                                         approximate_number_of_vehicles_used = ((total_service_time.to_f + total_travel_time) / average_vehicles_work_time).ceil

                                         approximate_number_of_vehicles_used * 2 * Helper.flying_distance(average_loc, [depot.location.lat, depot.location.lon])

                                         # TODO: Here we use flying_distance for approx_depot_time_correction; however, this value is in terms of meters
                                         # instead of seconds. Still since all dicho paramters    -- i.e.,  resolution_dicho_exclusion_scaling_angle, resolution_dicho_exclusion_rate, etc. --
                                         # are calculated with this functionality, correcting this bug makes the calculated parameters perform less effective.
                                         # We need to calculate new parameters after correcting the bug.
                                         #

                                         # point_closest_to_center = points.min_by{ |point| Helper::flying_distance(average_loc, [point.location.lat, point.location.lon]) }
                                         # ave_dist_to_depot = matrices[0][:time][point_closest_to_center.matrix_index][depot.matrix_index]
                                         # ave_dist_from_depot = matrices[0][:time][depot.matrix_index][point_closest_to_center.matrix_index]
                                         # approximate_number_of_vehicles_used * (ave_dist_to_depot + ave_dist_from_depot)
                                       end

        total_time_load = total_service_time + total_travel_time + approx_depot_time_correction

        average_service_load = total_time_load / services.size.to_f
        average_number_of_services_per_vehicle = average_vehicles_work_time / average_service_load
        exclusion_rate = resolution_dicho_exclusion_rate * average_number_of_services_per_vehicle
        angle = resolution_dicho_exclusion_scaling_angle # It needs to be in between 0 and 45 - 0 means only uniform cost is used - 45 means only variable cost is used
        tan_variable = Math.tan(angle * Math::PI / 180)
        tan_uniform = Math.tan((45 - angle) * Math::PI / 180)
        coeff_variable_cost = tan_variable / (1 - tan_variable * tan_uniform)
        coeff_uniform_cost = tan_uniform / (1 - tan_variable * tan_uniform)

        services.each{ |service|
          service.exclusion_cost = (coeff_variable_cost * (max_fixed_cost / exclusion_rate * service[:activity][:duration] / average_service_load) + coeff_uniform_cost * (max_fixed_cost / exclusion_rate)).ceil
        }
      when :distance
        raise 'Distance based exclusion cost calculation is not ready'
      when :capacity
        raise 'Capacity based exclusion cost calculation is not ready'
      end

      nil
    end
  end
end
