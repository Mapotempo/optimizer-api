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

    field :restitution_geometry, default: false
    field :restitution_geometry_polyline, default: false
    field :restitution_intermediate_solutions, default: true
    field :restitution_csv, default: false
    field :restitution_allow_empty_result, default: false

    field :schedule_range_indices, default: nil # extends schedule_range_date
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
    has_many :shipments, class_name: 'Models::Shipment'
    has_many :relations, class_name: 'Models::Relation'
    has_many :routes, class_name: 'Models::Route'
    has_many :subtours, class_name: 'Models::Subtour'
    has_many :zones, class_name: 'Models::Zone'
    belongs_to :config, class_name: 'Models::Configuration' # can be renamed to configuration after the transition if wanted

    def self.create(hash, delete = true)
      Models.delete_all if delete

      vrp = super({})
      self.filter(hash) # TODO : add filters.rb here
      # moved filter here to make sure we do have schedule_indices (not date) to do work_day check with lapses
      self.check_consistency(hash)
      self.ensure_retrocompatibility(hash)
      [:name, :matrices, :units, :points, :rests, :zones, :capacities, :quantities, :timewindows,
       :vehicles, :services, :shipments, :relations, :subtours, :routes, :configuration].each{ |key|
        vrp.send("#{key}=", hash[key]) if hash[key]
      }

      self.expand_data(vrp)

      vrp
    end

    def self.check_consistency(hash)
      hash[:services] ||= []
      hash[:shipments] ||= []

      # shipment relation consistency
      shipment_relations = hash[:relations]&.select{ |r| r[:type] == :shipment }&.flat_map{ |r| r[:linked_ids] }.to_a
      unless shipment_relations.size == shipment_relations.uniq.size
        raise OptimizerWrapper::UnsupportedProblemError.new(
          'Services can appear in at most one shipment relation. '\
          'Following services appear in multiple shipment relations',
          shipment_relations.detect{ |id| shipment_relations.count(id) > 1 }
        )
      end

      # vehicle time cost consistency
      if hash[:vehicles]&.any?{ |v| v[:cost_waiting_time_multiplier].to_f > (v[:cost_time_multiplier] || 1) }
        raise OptimizerWrapper::DiscordantProblemError, 'cost_waiting_time_multiplier cannot be greater than cost_time_multiplier'
      end

      # ensure IDs are unique
      # TODO: Active Hash should be checking this
      [:matrices, :units, :points, :rests, :zones, :timewindows,
       :vehicles, :services, :shipments, :subtours].each{ |key|
        next if hash[key]&.collect{ |v| v[:id] }&.uniq!.nil?

        raise OptimizerWrapper::DiscordantProblemError.new("#{key} IDs should be unique")
      }

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

      # services consistency
      if (hash[:services] + hash[:shipments]).any?{ |s| (s[:minimum_lapse] || 0) > (s[:maximum_lapse] || 2**32) }
        raise OptimizerWrapper::DiscordantProblemError.new('Minimum lapse can not be bigger than maximum lapse')
      end

      # shipment position consistency
      forbidden_position_pairs = [[:always_middle, :always_first], [:always_last, :always_middle], [:always_last, :always_first]]
      hash[:shipments].each{ |shipment|
        raise OptimizerWrapper::DiscordantProblemError, 'Unconsistent positions in shipments.' if forbidden_position_pairs.include?([shipment[:pickup][:position], shipment[:delivery][:position]])
      }

      # routes consistency
      periodic = hash[:configuration] && hash[:configuration][:preprocessing] && hash[:configuration][:preprocessing][:first_solution_strategy].to_a.include?('periodic')
      hash[:routes]&.each{ |route|
        route[:mission_ids].each{ |id|
          corresponding_service = hash[:services]&.find{ |s| s[:id] == id } || hash[:shipments].find{ |s| s[:id] == id }

          raise OptimizerWrapper::DiscordantProblemError, 'Each mission_ids should refer to an existant service or shipment' if corresponding_service.nil?
          raise OptimizerWrapper::UnsupportedProblemError, 'Services in initialize routes should have only one activity' if corresponding_service[:activities] && periodic
        }
      }

      configuration = hash[:configuration]
      return unless configuration

      # configuration consistency
      if configuration[:preprocessing]
        if configuration[:preprocessing][:partitions]&.any?{ |partition| partition[:entity].to_sym == :work_day }
          if hash[:services].any?{ |s|
              if hash[:configuration][:schedule][:range_indices][:end] <= 6
                (s[:visits_number] || 1) > 1
              else
                (s[:visits_number] || 1) > 1 &&
                ((s[:minimum_lapse]&.floor || 1)..(s[:maximum_lapse]&.ceil || hash[:configuration][:schedule][:range_indices][:end])).none?{ |intermediate_lapse| (intermediate_lapse % 7).zero? }
              end
            }

            raise OptimizerWrapper::DiscordantProblemError, 'Work day partition implies that lapses of all services can be a multiple of 7. There are services whose minimum and maximum lapse do not permit such lapse'
          end
        end
      end

      if configuration[:schedule]
        if configuration[:schedule][:range_indices][:start] > 6
          raise OptimizerWrapper::DiscordantProblemError.new('Api does not support schedule start index bigger than 6 yet')
          # TODO : allow start bigger than 6 and make code consistent with this
        end

        if configuration[:schedule][:range_indices][:start] > configuration[:schedule][:range_indices][:end]
          raise OptimizerWrapper::DiscordantProblemError.new('Schedule start index should be less than or equal to end')
        end
      else
        (hash[:services] + hash[:shipments]).each{ |s|
          raise OptimizerWrapper::DiscordantProblemError.new(
            'There can not be more than one visit if no schedule is provided') unless s[:visits_number].to_i <= 1
        }
      end

      # periodic consistency
      return unless periodic

      if hash[:relations]
        incompatible_relation_types = hash[:relations].collect{ |r| r[:type] }.uniq - %i[force_first never_first force_end]
        raise OptimizerWrapper::DiscordantProblemError, "#{incompatible_relation_types} relations not available with specified first_solution_strategy" unless incompatible_relation_types.empty?
      end

      raise OptimizerWrapper::DiscordantProblemError, 'Vehicle group duration on weeks or months is not available with schedule_range_date.' if hash[:relations].to_a.any?{ |relation| relation[:type] == :vehicle_group_duration_on_months } &&
                                                                                                                                                (!configuration[:schedule] || configuration[:schedule][:range_indice])

      raise OptimizerWrapper::DiscordantProblemError, 'Shipments are not available with periodic heuristic.' unless hash[:shipments].empty?

      raise OptimizerWrapper::DiscordantProblemError, 'Rests are not available with periodic heuristic.' unless hash[:vehicles].all?{ |vehicle| vehicle[:rests].to_a.empty? }

      if hash[:configuration][:resolution][:same_point_day]
        raise OptimizerWrapper.UnsupportedProblemError, 'Same_point_day is not supported if a set has one service with several activities' if hash[:services].any?{ |service| service[:activities].to_a.size.positive? }
      end
    end

    def self.expand_data(vrp)
      vrp.add_relation_references
      vrp.add_sticky_vehicle_if_routes_and_partitions
      vrp.adapt_relations_between_shipments
      vrp.expand_unavailable_days
      vrp.provide_original_ids
    end

    def self.convert_position_relations(hash)
      relations_to_remove = []
      hash[:relations]&.each_with_index{ |r, r_i|
        case r[:type]
        when :force_first
          r[:linked_ids].each{ |id|
            to_modify = [hash[:services], hash[:shipments]].flatten.find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Force first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :always_first
          }
          relations_to_remove << r_i
        when :never_first
          r[:linked_ids].each{ |id|
            to_modify = [hash[:services], hash[:shipments]].flatten.find{ |s| s[:id] == id }
            raise OptimizerWrapper::DiscordantProblemError, 'Never first relation with service with activities. Use position field instead.' unless to_modify[:activity]

            to_modify[:activity][:position] = :never_first
          }
          relations_to_remove << r_i
        when :force_end
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

    def self.ensure_retrocompatibility(hash)
      self.convert_position_relations(hash)
      self.deduce_first_solution_strategy(hash)
      self.deduce_minimum_duration(hash)
      self.deduce_solver_parameter(hash)
      self.convert_route_indice_into_index(hash)
    end

    def self.filter(hash)
      return hash if hash.empty?

      self.remove_unnecessary_units(hash)
      self.remove_unnecessary_relations(hash)
      self.generate_schedule_indices_from_date(hash)
      self.generate_linked_service_ids_for_relations(hash)
    end

    def self.remove_unnecessary_units(hash)
      return hash if !hash[:units] || !hash[:vehicles] || (!hash[:services] && !hash[:shipments])

      vehicle_units = hash[:vehicles]&.flat_map{ |v| v[:capacities]&.map{ |c| c[:unit_id] } || [] } || []
      subtour_units = hash[:subtours]&.flat_map{ |v| v[:capacities]&.map{ |c| c[:unit_id] } || [] } || []
      service_units = hash[:services]&.flat_map{ |s| s[:quantities]&.map{ |c| c[:unit_id] } || [] } || []
      shipment_units = hash[:shipments]&.flat_map{ |s| s[:quantities]&.map{ |c| c[:unit_id] } || [] } || []

      capacity_units = (hash[:capacities]&.map{ |c| c[:unit_id] } || []) | vehicle_units | subtour_units
      quantity_units = (hash[:quantities]&.map{ |q| q[:unit_id] } || []) | service_units | shipment_units
      needed_units = capacity_units & quantity_units

      hash[:units].delete_if{ |u| needed_units.exclude? u[:id] }

      rejected_capacities = hash[:capacities]&.select{ |capacity| needed_units.exclude? capacity[:unit_id] }&.map{ |capacity| capacity[:id] } || []
      rejected_quantities = hash[:quantities]&.select{ |quantity| needed_units.exclude? quantity[:unit_id] }&.map{ |quantity| quantity[:id] } || []

      hash[:vehicles]&.each{ |v| rejected_capacities.each{ |r_c| v[:capacity_ids]&.gsub!(/\b#{r_c}\b/, '') } }
      hash[:subtours]&.each{ |v| rejected_capacities.each{ |r_c| v[:capacity_ids]&.gsub!(/\b#{r_c}\b/, '') } }
      hash[:services]&.each{ |s| rejected_quantities.each{ |r_q| s[:quantity_ids]&.gsub!(/\b#{r_q}\b/, '') } }
      hash[:shipments]&.each{ |s| rejected_quantities.each{ |r_q| s[:quantity_ids]&.gsub!(/\b#{r_q}\b/, '') } }

      hash[:capacities]&.delete_if{ |capacity| rejected_capacities.include? capacity[:id] }
      hash[:quantities]&.delete_if{ |quantity| rejected_quantities.include? quantity[:id] }

      hash[:vehicles]&.each{ |v| v[:capacities]&.delete_if{ |capacity| needed_units.exclude? capacity[:unit_id] } }
      hash[:subtours]&.each{ |v| v[:capacities]&.delete_if{ |capacity| needed_units.exclude? capacity[:unit_id] } }
      hash[:services]&.each{ |v| v[:quantities]&.delete_if{ |quantity| needed_units.exclude? quantity[:unit_id] } }
      hash[:shipments]&.each{ |s| s[:quantities]&.delete_if{ |quantity| needed_units.exclude? quantity[:unit_id] } }
    end

    def self.remove_unnecessary_relations(hash)
      return hash unless hash[:relations]&.any?

      types_with_duration =
        %i[minimum_day_lapse maximum_day_lapse
           minimum_duration_lapse maximum_duration_lapse
           vehicle_group_duration vehicle_group_duration_on_weeks
           vehicle_group_duration_on_months vehicle_group_number]

      hash[:relations].delete_if{ |r| r[:lapse].nil? && types_with_duration.include?(r[:type]) }
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
      missions_and_vehicles = hash[:services].to_a + hash[:shipments].to_a + hash[:vehicles].to_a
      has_date = missions_and_vehicles.any?{ |m|
        (m[:unavailable_date_ranges] || m[:unavailable_work_date])&.any?
      }
      has_index = missions_and_vehicles.any?{ |m|
        (m[:unavailable_index_ranges] || m[:unavailable_work_day_indices])&.any?
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
      [hash[:services].to_a + hash[:shipments].to_a].flatten.each{ |element|
        deduce_unavailable_days(hash, element, start_index, end_index, :visit)
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
      hash[:configuration][:schedule].delete(:range_date)

      hash
    end

    def self.generate_linked_service_ids_for_relations(hash)
      hash[:relations]&.each{ |relation|
        next unless relation[:linked_ids]&.any?

        relation[:linked_service_ids] = relation[:linked_ids].select{ |id| hash[:services]&.any?{ |s| s[:id] == id } }
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
      self.schedule_unavailable_days = schedule[:unavailable_days]
      self.schedule_months_indices = schedule[:months_indices]
    end

    def services_duration
      Helper.services_duration(self.services)
    end

    def visits
      Helper.visits(self.services, self.shipments)
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

    def scheduling?
      !self.schedule_range_indices.nil?
    end

    def periodic_heuristic?
      self.preprocessing_first_solution_strategy.to_a.include?('periodic')
    end
  end
end
