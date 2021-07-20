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
require './models/concerns/validate_data'
require './models/concerns/expand_data'
require './models/concerns/periodic_service'

module Models
  class Vrp < Base
    include DistanceMatrix
    include ValidateData
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
    field :preprocessing_first_solution_strategy, default: []
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

    field :restitution_geometry, default: []
    field :restitution_intermediate_solutions, default: true
    field :restitution_csv, default: false
    field :restitution_use_deprecated_csv_headers, default: false
    field :restitution_allow_empty_result, default: false

    field :schedule_range_indices, default: nil # extends schedule_range_date
    field :schedule_start_date, default: nil
    field :schedule_unavailable_days, default: Set[] # extends unavailable_date and schedule_unavailable_indices
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
    has_many :relations, class_name: 'Models::Relation'
    has_many :routes, class_name: 'Models::Route'
    has_many :subtours, class_name: 'Models::Subtour'
    has_many :zones, class_name: 'Models::Zone'
    belongs_to :config, class_name: 'Models::Configuration' # can be renamed to configuration after the transition if wanted

    def self.create(hash, delete = true)
      Models.delete_all if delete

      vrp = super({})
      self.convert_shipments_to_services(hash)
      self.filter(hash) # TODO : add filters.rb here
      # moved filter here to make sure we do have schedule_indices (not date) to do work_day check with lapses
      vrp.check_consistency(hash)
      self.ensure_retrocompatibility(hash)
      [:name, :matrices, :units, :points, :rests, :zones, :capacities, :quantities, :timewindows,
       :vehicles, :services, :relations, :subtours, :routes, :configuration].each{ |key|
        vrp.send("#{key}=", hash[key]) if hash[key]
      }

      self.expand_data(vrp)

      vrp
    end

    def self.convert_shipments_to_services(hash)
      hash[:services] ||= []
      hash[:relations] ||= []
      @linked_ids = {}
      service_ids = hash[:services].map{ |service| service[:id] }
      hash[:shipments]&.each{ |shipment|
        @linked_ids[shipment[:id]] = []
        %i[pickup delivery].each{ |part|
          service = Oj.load(Oj.dump(shipment))
          service[:original_id] = shipment[:id]
          service[:id] += "_#{part}"
          service[:id] += '_conv' while service_ids.any?{ |id| id == service[:id] } # protect against id clash
          @linked_ids[shipment[:id]] << service[:id]
          service[:type] = part.to_sym
          service[:activity] = service[part]
          %i[pickup delivery direct maximum_inroute_duration].each{ |key| service.delete(key) }

          if part == :delivery
            service[:quantities]&.each{ |quantity|
              quantity[:value] = -quantity[:value] if quantity[:value]
              quantity[:setup_value] = -quantity[:setup_value] if quantity[:setup_value]
            }
          end
          hash[:services] << service
        }
        convert_relations_of_shipment_to_services(hash,
                                                  shipment[:id],
                                                  @linked_ids[shipment[:id]][0],
                                                  @linked_ids[shipment[:id]][1])
        hash[:relations] << { type: :shipment, linked_ids: @linked_ids[shipment[:id]] }
        hash[:relations] << { type: :sequence, linked_ids: @linked_ids[shipment[:id]] } if shipment[:direct]
        max_lapse = shipment[:maximum_inroute_duration]
        next unless max_lapse

        hash[:relations] << { type: :maximum_duration_lapse, linked_ids: @linked_ids[shipment[:id]], lapse: max_lapse }
      }
      convert_shipment_within_routes(hash)
      hash.delete(:shipments)
    end

    def self.convert_relations_of_shipment_to_services(hash, shipment_id, pickup_service_id, delivery_service_id)
      hash[:relations].each{ |relation|
        case relation[:type]
        when :minimum_duration_lapse, :maximum_duration_lapse
          relation[:linked_ids][0] = delivery_service_id if relation[:linked_ids][0] == shipment_id
          relation[:linked_ids][1] = pickup_service_id if relation[:linked_ids][1] == shipment_id
          relation[:lapse] ||= 0
        when :same_route
          relation[:linked_ids].each_with_index{ |id, id_i|
            next unless id == shipment_id

            relation[:linked_ids][id_i] = pickup_service_id # which will be in same_route as delivery
          }
        when :sequence, :order
          if relation[:linked_ids].any?{ |id| id == shipment_id }
            msg = 'Relation between shipment pickup and delivery should be explicitly specified for `:sequence` and `:order` relations.'
            raise OptimizerWrapper::DiscordantProblemError.new(msg)
          end
        else
          if relation[:linked_ids].any?{ |id| id == shipment_id }
            msg = "Relations of type #{relation[:type]} cannot be linked using the shipment object."
            raise OptimizerWrapper::DiscordantProblemError.new(msg)
          end
        end
      }
    end

    def self.convert_shipment_within_routes(hash)
      return unless hash[:shipments]

      shipment_ids = {}
      hash[:shipments].each{ |shipment| shipment_ids[shipment[:id]] = 0 }
      hash[:routes]&.each{ |route|
        route[:mission_ids].map!{ |mission_id|
          if shipment_ids.key?(mission_id)
            if shipment_ids[mission_id].zero?
              shipment_ids[mission_id] += 1
              @linked_ids[mission_id][0]
            elsif shipment_ids[mission_id] == 1
              shipment_ids[mission_id] += 1
              @linked_ids[mission_id][1]
            else
              raise OptimizerWrapper::DiscordantProblemError.new('A shipment could only appear twice in routes.')
            end
          else
            mission_id
          end
        }
      }
    end

    def self.expand_data(vrp)
      vrp.add_relation_references
      vrp.add_sticky_vehicle_if_routes_and_partitions
      vrp.expand_unavailable_days
      vrp.provide_original_info
    end

    def self.convert_position_relations(hash)
      relations_to_remove = []
      hash[:relations]&.each_with_index{ |r, r_i|
        case r[:type]
        when :force_first
          r[:linked_ids].each{ |id|
            to_modify = hash[:services].find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Force first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :always_first
          }
          relations_to_remove << r_i
        when :never_first
          r[:linked_ids].each{ |id|
            to_modify = hash[:services].find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Never first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :never_first
          }
          relations_to_remove << r_i
        when :force_end
          r[:linked_ids].each{ |id|
            to_modify = hash[:services].find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Force end relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :always_last
          }
          relations_to_remove << r_i
        end
      }

      relations_to_remove.reverse_each{ |index| hash[:relations].delete_at(index) }
    end

    def self.deduce_first_solution_strategy(hash)
      preprocessing = hash[:configuration] && hash[:configuration][:preprocessing]
      return unless preprocessing

      # To make sure that internal vrp conforms with the Grape vrp.
      preprocessing[:first_solution_strategy] ||= []
      preprocessing[:first_solution_strategy] = [preprocessing[:first_solution_strategy]].flatten
    end

    def self.deduce_minimum_duration(hash)
      resolution = hash[:configuration] && hash[:configuration][:resolution]
      return unless resolution && resolution[:initial_time_out]

      log 'initial_time_out and minimum_duration parameters are mutually_exclusive', level: :warn if resolution[:minimum_duration]
      resolution[:minimum_duration] = resolution[:initial_time_out]
      resolution.delete(:initial_time_out)
    end

    def self.deduce_solver_parameter(hash)
      resolution = hash[:configuration] && hash[:configuration][:resolution]
      return unless resolution

      if resolution[:solver_parameter] == -1
        resolution[:solver] = false
        resolution.delete(:solver_parameter)
      elsif resolution[:solver_parameter]
        correspondant = { 0 => 'path_cheapest_arc', 1 => 'global_cheapest_arc', 2 => 'local_cheapest_insertion', 3 => 'savings', 4 => 'parallel_cheapest_insertion', 5 => 'first_unbound', 6 => 'christofides' }
        hash[:configuration][:preprocessing] ||= {}
        hash[:configuration][:preprocessing][:first_solution_strategy] = [correspondant[hash[:configuration][:resolution][:solver_parameter]]]
        resolution[:solver] = true
        resolution.delete(:solver_parameter)
      end
    end

    def self.convert_route_indice_into_index(hash)
      hash[:routes]&.each{ |route|
        next unless route[:indice]

        log 'Route indice was used instead of route index', level: :warn
        route[:day_index] = route[:indice]
        route.delete(:indice)
      }
    end

    def self.convert_geometry_polylines_to_geometry(hash)
      return unless hash[:configuration] && hash[:configuration][:restitution].to_h[:geometry]

      hash[:configuration][:restitution][:geometry] -=
        if hash[:configuration][:restitution][:geometry_polyline]
          [:polylines]
        else
          [:encoded_polylines]
        end
      hash[:configuration][:restitution].delete(:geometry_polyline)
    end

    def self.ensure_retrocompatibility(hash)
      self.convert_position_relations(hash)
      self.deduce_first_solution_strategy(hash)
      self.deduce_minimum_duration(hash)
      self.deduce_solver_parameter(hash)
      self.convert_route_indice_into_index(hash)
      self.convert_geometry_polylines_to_geometry(hash)
    end

    def self.filter(hash)
      return hash if hash.empty?

      self.remove_unnecessary_units(hash)
      self.remove_unnecessary_relations(hash)
      self.generate_schedule_indices_from_date(hash)
      self.generate_linked_service_ids_for_relations(hash)
      self.generate_first_last_possible_day_for_first_visit(hash)
    end

    def self.remove_unnecessary_units(hash)
      return hash if !hash[:units]

      vehicle_units = hash[:vehicles]&.flat_map{ |v| v[:capacities]&.map{ |c| c[:unit_id] } || [] } || []
      subtour_units = hash[:subtours]&.flat_map{ |v| v[:capacities]&.map{ |c| c[:unit_id] } || [] } || []
      service_units = hash[:services]&.flat_map{ |s| s[:quantities]&.map{ |c| c[:unit_id] } || [] } || []

      capacity_units = (hash[:capacities]&.map{ |c| c[:unit_id] } || []) | vehicle_units | subtour_units
      quantity_units = (hash[:quantities]&.map{ |q| q[:unit_id] } || []) | service_units
      needed_units = capacity_units & quantity_units

      hash[:units].delete_if{ |u| needed_units.exclude? u[:id] }

      rejected_capacities = hash[:capacities]&.select{ |capacity| needed_units.exclude? capacity[:unit_id] }&.map{ |capacity| capacity[:id] } || []
      rejected_quantities = hash[:quantities]&.select{ |quantity| needed_units.exclude? quantity[:unit_id] }&.map{ |quantity| quantity[:id] } || []

      hash[:vehicles]&.each{ |v| rejected_capacities.each{ |r_c| v[:capacity_ids]&.gsub!(/\b#{r_c}\b/, '') } }
      hash[:subtours]&.each{ |v| rejected_capacities.each{ |r_c| v[:capacity_ids]&.gsub!(/\b#{r_c}\b/, '') } }
      hash[:services]&.each{ |s| rejected_quantities.each{ |r_q| s[:quantity_ids]&.gsub!(/\b#{r_q}\b/, '') } }

      hash[:capacities]&.delete_if{ |capacity| rejected_capacities.include? capacity[:id] }
      hash[:quantities]&.delete_if{ |quantity| rejected_quantities.include? quantity[:id] }

      hash[:vehicles]&.each{ |v| v[:capacities]&.delete_if{ |capacity| needed_units.exclude? capacity[:unit_id] } }
      hash[:subtours]&.each{ |v| v[:capacities]&.delete_if{ |capacity| needed_units.exclude? capacity[:unit_id] } }
      hash[:services]&.each{ |v| v[:quantities]&.delete_if{ |quantity| needed_units.exclude? quantity[:unit_id] } }
    end

    def self.remove_unnecessary_relations(hash)
      return hash unless hash[:relations]&.any?

      types_with_duration =
        %i[minimum_day_lapse maximum_day_lapse
           minimum_duration_lapse maximum_duration_lapse
           vehicle_group_duration vehicle_group_duration_on_weeks
           vehicle_group_duration_on_months vehicle_group_number]

      hash[:relations].delete_if{ |r| r[:lapse].nil? && types_with_duration.include?(r[:type]) }

      # TODO : remove this filter, VRP with duplicated relations should not be accepted
      uniq_relations = []
      hash[:relations].group_by{ |r| r[:type] }.each{ |_type, relations_set|
        uniq_relations += relations_set.uniq
      }
      hash[:relations] = uniq_relations
    end

    def self.convert_availability_dates_into_indices(element, hash, start_index, end_index, type)
      unavailable_indices_key, unavailable_dates_key =
        case type
        when :visit
          [:unavailable_visit_day_indices, :unavailable_visit_day_date]
        when :vehicle
          [:unavailable_work_day_indices, :unavailable_work_date]
        when :schedule
          [:unavailable_indices, :unavailable_date]
        end

      element[:unavailable_days] = (element[unavailable_indices_key] || []).to_set
      element.delete(unavailable_indices_key)

      return unless hash[:configuration][:schedule][:range_date]

      start_value = hash[:configuration][:schedule][:range_date][:start].to_date.ajd.to_i - start_index
      element[unavailable_dates_key].to_a.each{ |unavailable_date|
        new_index = unavailable_date.to_date.ajd.to_i - start_value
        element[:unavailable_days] |= [new_index] if new_index.between?(start_index, end_index)
      }
      element.delete(unavailable_dates_key)

      return unless element[:unavailable_date_ranges]

      element[:unavailable_index_ranges] ||= []
      element[:unavailable_index_ranges] += element[:unavailable_date_ranges].collect{ |range|
        {
          start: range[:start].to_date.ajd.to_i - start_value,
          end: range[:end].to_date.ajd.to_i - start_value,
        }
      }
      element.delete(:unavailable_date_ranges)
    end

    def self.collect_unavaible_day_indices(element, start_index, end_index)
      return [] unless element[:unavailable_index_ranges].to_a.size.positive?

      element[:unavailable_days] += element[:unavailable_index_ranges].collect{ |range|
        ([range[:start], start_index].max..[range[:end], end_index].min).to_a
      }.flatten.uniq
      element.delete(:unavailable_index_ranges)
    end

    def self.deduce_unavailable_days(hash, element, start_index, end_index, type)
      convert_availability_dates_into_indices(element, hash, start_index, end_index, type)
      collect_unavaible_day_indices(element, start_index, end_index)
    end

    def self.detect_date_indices_inconsistency(hash)
      missions_and_vehicles = hash[:services] + hash[:vehicles]
      has_date = missions_and_vehicles.any?{ |m|
        (m[:unavailable_date_ranges] || m[:unavailable_work_date])&.any? || m[:last_performed_visit_date]
      }
      has_index = missions_and_vehicles.any?{ |m|
        (m[:unavailable_index_ranges] || m[:unavailable_work_day_indices])&.any? || m[:last_performed_visit_day_index]
      }
      if (hash[:configuration][:schedule][:range_indices] && has_date) ||
         (hash[:configuration][:schedule][:range_date] && has_index)
        raise OptimizerWrapper::DiscordantProblemError.new(
          'Date intervals are not compatible with schedule range indices'
        )
      end
    end

    def self.generate_schedule_indices_from_date(hash)
      return hash if !hash[:configuration] || !hash[:configuration][:schedule]

      schedule = hash[:configuration][:schedule]
      if (!schedule[:range_indices] || schedule[:range_indices][:start].nil? || schedule[:range_indices][:end].nil?) &&
         (!schedule[:range_date] || schedule[:range_date][:start].nil? || schedule[:range_date][:end].nil?)
        raise OptimizerWrapper::DiscordantProblemError.new('Schedule need range indices or range dates')
      end

      detect_date_indices_inconsistency(hash)

      start_index, end_index =
        if hash[:configuration][:schedule][:range_indices]
          [hash[:configuration][:schedule][:range_indices][:start],
           hash[:configuration][:schedule][:range_indices][:end]]
        else
          start_ = hash[:configuration][:schedule][:range_date][:start].to_date.cwday - 1
          end_ = (hash[:configuration][:schedule][:range_date][:end].to_date -
                  hash[:configuration][:schedule][:range_date][:start].to_date).to_i + start_
          [start_, end_]
        end

      # remove unavailable dates and ranges :
      hash[:vehicles].each{ |v| deduce_unavailable_days(hash, v, start_index, end_index, :vehicle) }
      hash[:services].each{ |element|
        deduce_unavailable_days(hash, element, start_index, end_index, :visit)
        next unless element[:last_performed_visit_date]

        element[:last_performed_visit_day_index] =
          start_index -
          (hash[:configuration][:schedule][:range_date][:start].to_date - element[:last_performed_visit_date].to_date).to_i

        element.delete(:last_performed_visit_date)
      }
      if hash[:configuration][:schedule]
        deduce_unavailable_days(hash, hash[:configuration][:schedule], start_index, end_index, :schedule)
      end

      return hash if hash[:configuration][:schedule][:range_indices]

      # provide months
      months_indices = []
      current_month = hash[:configuration][:schedule][:range_date][:start].to_date.month
      current_indices = []
      current_index = start_index
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
      hash[:configuration][:schedule][:months_indices] = months_indices

      # convert route dates into indices
      hash[:routes]&.each{ |route|
        next if route[:day_index]

        route[:day_index] = (route[:date].to_date -
                            hash[:configuration][:schedule][:range_date][:start].to_date).to_i + start_index
        route.delete(:date)
      }

      # remove schedule_range_date
      hash[:configuration][:schedule][:range_indices] = {
        start: start_index,
        end: end_index
      }
      hash[:configuration][:schedule][:start_date] = hash[:configuration][:schedule][:range_date][:start]
      hash[:configuration][:schedule].delete(:range_date)

      hash
    end

    def self.generate_linked_service_ids_for_relations(hash)
      hash[:relations]&.each{ |relation|
        next unless relation[:linked_ids]&.any?

        relation[:linked_service_ids] = relation[:linked_ids].select{ |id| hash[:services]&.any?{ |s| s[:id] == id } }
      }
    end

    def self.generate_first_last_possible_day_for_first_visit(hash)
      [hash[:services], hash[:shipments]].compact.flatten.each{ |s|
        next unless s[:last_performed_visit_day_index]

        s[:first_possible_days] = [
          if s[:minimum_lapse]
            [hash[:configuration][:schedule][:range_indices][:start],
             s[:last_performed_visit_day_index] + s[:minimum_lapse]].max
          else
            hash[:configuration][:schedule][:range_indices][:start]
          end
        ]

        s[:last_possible_days] = [
          if s[:maximum_lapse]
            [hash[:configuration][:schedule][:range_indices][:end],
             s[:last_performed_visit_day_index] + s[:maximum_lapse]].min
          else
            hash[:configuration][:schedule][:range_indices][:end]
          end
        ]

        s.delete(:last_performed_visit_day_index)
      }
    end

    def configuration=(configuration)
      self.config = configuration
      self.preprocessing = configuration[:preprocessing] if configuration[:preprocessing]
      self.resolution = configuration[:resolution] if configuration[:resolution]
      self.schedule = configuration[:schedule] if configuration[:schedule]
      self.restitution = configuration[:restitution] if configuration[:restitution]
    end

    def restitution=(restitution)
      self.restitution_geometry = restitution[:geometry]
      self.restitution_intermediate_solutions = restitution[:intermediate_solutions]
      self.restitution_csv = restitution[:csv]
      self.restitution_use_deprecated_csv_headers = restitution[:use_deprecated_csv_headers]
      self.restitution_allow_empty_result = restitution[:allow_empty_result]
    end

    def resolution=(resolution)
      self.resolution_duration = resolution[:duration]
      self.resolution_total_duration = resolution[:duration]
      self.resolution_iterations = resolution[:iterations]
      self.resolution_iterations_without_improvment = resolution[:iterations_without_improvment]
      self.resolution_stable_iterations = resolution[:stable_iterations]
      self.resolution_stable_coefficient = resolution[:stable_coefficient]
      self.resolution_minimum_duration = resolution[:minimum_duration]
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
      self.preprocessing_first_solution_strategy = preprocessing[:first_solution_strategy]
      self.preprocessing_partitions = preprocessing[:partitions]
      self.preprocessing_heuristic_result = {}
    end

    def schedule=(schedule)
      self.schedule_range_indices = schedule[:range_indices]
      self.schedule_start_date = schedule[:start_date]
      self.schedule_unavailable_days = schedule[:unavailable_days]
      self.schedule_months_indices = schedule[:months_indices]
    end

    def services_duration
      Helper.services_duration(self.services)
    end

    def visits
      Helper.visits(self.services)
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

    def transactions
      vehicles.count * points.count
    end

    def schedule?
      !self.schedule_range_indices.nil?
    end

    def periodic_heuristic?
      self.preprocessing_first_solution_strategy.to_a.include?('periodic')
    end
  end
end
