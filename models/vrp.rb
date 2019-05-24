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
require './models/base'

module Models
  class Vrp < Base
    field :name, default: nil
    field :preprocessing_max_split_size, default: nil
    field :preprocessing_split_number, default: 1.0
    field :preprocessing_partition_method, default: nil
    field :preprocessing_partition_metric, default: nil
    field :preprocessing_kmeans_centroids, default: nil
    field :preprocessing_cluster_threshold, default: nil
    field :preprocessing_force_cluster, default: false
    field :preprocessing_prefer_short_segment, default: false
    field :preprocessing_neighbourhood_size, default: nil
    field :preprocessing_heuristic_result, defaul: {}
    field :preprocessing_first_solution_strategy, default: nil
    has_many :preprocessing_partitions, class_name: 'Models::Partition'

    field :resolution_duration, default: nil
    field :resolution_iterations, default: nil
    field :resolution_iterations_without_improvment, default: nil
    field :resolution_stable_iterations, default: nil
    field :resolution_stable_coefficient, default: nil
    field :resolution_initial_time_out, default: nil
    field :resolution_minimum_duration, default: nil
    field :resolution_init_duration, default: nil
    field :resolution_time_out_multiplier, default: nil
    field :resolution_vehicle_limit, default: nil
    field :resolution_solver_parameter, default: nil
    field :resolution_solver, default: true
    field :resolution_same_point_day, default: false
    field :resolution_allow_partial_assignment, default: true
    field :resolution_evaluate_only, default: false
    field :resolution_several_solutions, default: nil
    field :resolution_variation_ratio, default: nil
    field :resolution_batch_heuristic, default: false

    field :restitution_geometry, default: false
    field :restitution_geometry_polyline, default: false
    field :restitution_intermediate_solutions, default: true
    field :restitution_csv, default: false
    field :restitution_allow_empty_result, default: false

    field :schedule_range_indices, default: nil
    field :schedule_range_date, default: nil
    field :schedule_unavailable_indices, default: nil
    field :schedule_unavailable_date, default: nil

    field :debug_output_kmeans_centroids, default: false
    field :debug_output_clusters_in_csv, default: false

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
    # validates_numericality_of :resolution_solver_parameter, allow_nil: true
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
      super(hash)
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

      if max_fixed_cost <= 0 || (!force_recalc && services.any?{ |service| service.exclusion_cost && service.exclusion_cost > 0 })
        return
      end

      case type
      when :time
        services.each{ |service|
          service.exclusion_cost = max_fixed_cost / 15
        }
      when :distance
        raise 'Distance based exclusion cost calculation is not ready'
      when :capacity
        raise 'Capacity based exclusion cost calculation is not ready'
      end

      return
    end

    def configuration=(configuration)
      self.preprocessing = configuration[:preprocessing] if configuration[:preprocessing]
      self.resolution = configuration[:resolution] if configuration[:resolution]
      self.schedule = configuration[:schedule] if configuration[:schedule]
      self.restitution = configuration[:restitution] if configuration[:restitution]
      self.debug = configuration[:debug] if configuration[:debug]
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
      self.resolution_iterations = resolution[:iterations]
      self.resolution_iterations_without_improvment = resolution[:iterations_without_improvment]
      self.resolution_stable_iterations = resolution[:stable_iterations]
      self.resolution_stable_coefficient = resolution[:stable_coefficient]
      self.resolution_minimum_duration = resolution[:initial_time_out] || resolution[:minimum_duration]
      self.resolution_init_duration = resolution[:init_duration]
      self.resolution_time_out_multiplier = resolution[:time_out_multiplier]
      self.resolution_vehicle_limit = resolution[:vehicle_limit]
      self.resolution_solver_parameter = resolution[:solver_parameter]
      self.resolution_solver = resolution[:solver]
      self.resolution_same_point_day = resolution[:same_point_day]
      self.resolution_allow_partial_assignment = resolution[:allow_partial_assignment]
      self.resolution_evaluate_only = resolution[:evaluate_only]
      self.resolution_several_solutions = resolution[:several_solutions]
      self.resolution_variation_ratio = resolution[:variation_ratio]
      self.resolution_batch_heuristic = resolution[:batch_heuristic]
    end

    def preprocessing=(preprocessing)
      self.preprocessing_force_cluster = preprocessing[:force_cluster]
      self.preprocessing_max_split_size = preprocessing[:max_split_size]
      self.preprocessing_split_number = preprocessing[:split_number]
      self.preprocessing_partition_method = preprocessing[:partition_method]
      self.preprocessing_partition_metric = preprocessing[:partition_metric]
      self.preprocessing_kmeans_centroids = preprocessing[:kmeans_centroids]
      self.preprocessing_cluster_threshold = preprocessing[:cluster_threshold]
      self.preprocessing_prefer_short_segment = preprocessing[:prefer_short_segment]
      self.preprocessing_neighbourhood_size = preprocessing[:neighbourhood_size]
      self.preprocessing_first_solution_strategy = preprocessing[:first_solution_strategy]
      self.preprocessing_partitions = preprocessing[:partitions]
      self.preprocessing_heuristic_result = {}
    end

    def schedule=(schedule)
      self.schedule_range_indices = schedule[:range_indices]
      self.schedule_range_date = schedule[:range_date]
      self.schedule_unavailable_indices = schedule[:unavailable_indices]
      self.schedule_unavailable_date = schedule[:unavailable_date]
    end

    def debug=(debug)
      self.debug_output_kmeans_centroids = debug[:output_kmeans_centroids]
      self.debug_output_clusters_in_csv = debug[:output_clusters_in_csv]
    end

    def need_matrix_time?
     !(services.find{ |service|
        !service.activity.timewindows.empty? || service.activity.late_multiplier && service.activity.late_multiplier != 0
      } ||
      shipments.find{ |shipment|
        !shipment.pickup.timewindows.empty? || shipment.pickup.late_multiplier && shipment.pickup.late_multiplier != 0 ||
        !shipment.delivery.timewindows.empty? || shipment.delivery.late_multiplier && shipment.delivery.late_multiplier != 0
      } ||
      vehicles.find{ |vehicle|
        vehicle.need_matrix_time?
      }).nil?
    end

    def need_matrix_distance?
      !(vehicles.find{ |vehicle|
        vehicle.need_matrix_distance?
      }).nil?
    end

    def need_matrix_value?
      false
    end

    def services_duration
      Helper.services_duration(self.services)
    end
  end
end
