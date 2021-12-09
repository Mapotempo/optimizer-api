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
require './util/config'
require './models/base'
require './models/concerns/distance_matrix'
require './models/concerns/validate_data'
require './models/concerns/expand_data'
require './models/concerns/periodic_service'

module Models
  class Vrp < Base
    include VrpAsJson

    include DistanceMatrix
    include ValidateData
    include ExpandData
    include PeriodicService

    field :name, default: nil
    field :router, default: OptimizerWrapper.router(OptimizerWrapper.config[:router][:api_key]), as_json: :none

    has_many :matrices, class_name: 'Models::Matrix'
    has_many :points, class_name: 'Models::Point'
    has_many :units, class_name: 'Models::Unit'
    has_many :rests, class_name: 'Models::Rest'
    has_many :timewindows, class_name: 'Models::Timewindow', as_json: :none
    has_many :capacities, class_name: 'Models::Capacity', as_json: :none
    has_many :quantities, class_name: 'Models::Quantity', as_json: :none
    has_many :vehicles, class_name: 'Models::Vehicle'
    has_many :services, class_name: 'Models::Service'
    has_many :relations, class_name: 'Models::Relation'
    has_many :routes, class_name: 'Models::Route'
    has_many :subtours, class_name: 'Models::Subtour'
    has_many :zones, class_name: 'Models::Zone'
    belongs_to :configuration, class_name: 'Models::Configuration'

    def self.create(hash, options = {})
      options = { delete: true, check: true }.merge(options)
      hash[:configuration] = {
        preprocessing: {}, resolution: {}, restitution: {}
      }.merge(hash[:configuration] || {})
      Models.delete_all if options[:delete]

      vrp = super({})
      self.convert_shipments_to_services(hash)
      self.filter(hash) # TODO : add filters.rb here
      # moved filter here to make sure we do have configuration.schedule.indices (not date) to do work_day check with lapses
      vrp.check_consistency(hash) if options[:check]
      self.convert_expected_string_to_symbol(hash)
      self.ensure_retrocompatibility(hash)
      [:name, :matrices, :units, :points, :rests, :zones, :capacities, :quantities, :timewindows,
       :vehicles, :services, :relations, :subtours, :routes, :configuration].each{ |key|
        vrp.send("#{key}=", hash[key]) if hash[key]
      }

      self.expand_data(vrp)

      vrp
    end

    def expand_vehicles_for_consistent_empty_result
      periodic = Interpreters::PeriodicVisits.new(self)
      periodic.generate_vehicles(self)
    end

    def empty_solution(solver, unassigned_with_reason = [], already_expanded = true)
      self.vehicles = expand_vehicles_for_consistent_empty_result if self.schedule? && !already_expanded
      solution = Models::Solution.new(
        solvers: [solver],
        routes: self.vehicles.map{ |v| self.empty_route(v) },
        unassigned: (unassigned_visits(unassigned_with_reason) +
                     unassigned_rests)
      )
      solution.parse(self)
    end

    def empty_route(vehicle)
      route_start_time = [[vehicle.timewindow], vehicle.sequence_timewindows].compact.flatten[0]&.start.to_i
      route_end_time = route_start_time
      Models::Solution::Route.new(
        vehicle: vehicle,
        info: Models::Solution::Route::Info.new(
          start_time: route_start_time,
          end_time: route_end_time
        ),
        initial_loads: self.units.map{ |unit|
          Models::Solution::Load.new({
            current: 0,
            quantity: Models::Quantity.new(unit: unit, value: 0)
          })
        }
      )
    end

    def unassigned_visits(unassigned_with_reason)
      unassigned_hash = unassigned_with_reason.map{ |un| [un.id, un.reason] }.to_h
      if self.schedule?
        self.services.flat_map{ |service|
          Array.new(service.visits_number) { |visit_index|
            service_id = self.schedule? ? "#{service.id}_#{visit_index + 1}_#{service.visits_number}" : service.id
            Models::Solution::Stop.new(service, service_id: service_id,
                                                visit_index: visit_index,
                                                reason: unassigned_hash[service.id])
          }
        }
      else
        self.services.map{ |service| Models::Solution::Stop.new(service, reason: unassigned_hash[service.id]) }
      end
    end

    def unassigned_rests
      self.vehicles.flat_map{ |vehicle|
        vehicle.rests.map{ |rest| Models::Solution::Stop.new(rest) }
      }
    end

    def self.convert_partition_method_into_technique(hash)
      # method is an already reserved method name. It was generating conflicts during as_json conversion
      return if hash[:configuration].nil? || hash[:configuration][:preprocessing].nil? ||
                hash[:configuration][:preprocessing][:partitions].nil? ||
                hash[:configuration][:preprocessing][:partitions].empty?

      hash[:configuration][:preprocessing][:partitions].each{ |partition|
        partition[:technique] = partition[:method] if partition[:method] && !partition[:technique]
        partition.delete(:method)
      }
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

        hash[:relations] << { type: :maximum_duration_lapse, linked_ids: @linked_ids[shipment[:id]], lapses: [max_lapse] }
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
          relation[:lapses] ||= relation[:lapse] ? [relation[:lapse]] : [0]
          relation.delete(:lapse)
        when :same_route, :same_vehicle
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
      vrp.provide_original_info # TODO: this should be done on hash in order to be sure to have the original information
      vrp.sticky_as_skills # TODO: this should be done on hash in order to completely remove sticky_vehicles from service model
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

    def self.convert_relation_lapse_into_lapses(hash)
      hash[:relations].to_a.each{ |relation|
        if Models::Relation::ONE_LAPSE_TYPES.include?(relation[:type])
          if relation[:lapse]
            relation[:lapses] = [relation[:lapse]]
          end
        elsif Models::Relation::SEVERAL_LAPSE_TYPES.include?(relation[:type])
          if relation[:lapse]
            expected_size = relation[:linked_vehicle_ids].to_a.size + relation[:linked_ids].to_a.size - 1
            relation[:lapses] = Array.new(expected_size, relation[:lapse]) if expected_size > 0
          end
        end
        relation.delete(:lapse)
      }
    end

    def self.convert_expected_string_to_symbol(hash)
      hash[:relations].each{ |relation|
        relation[:type] = relation[:type]&.to_sym
      }

      hash[:services].each{ |service|
        service[:skills] = service[:skills]&.map(&:to_sym)
        service[:type] = service[:type]&.to_sym
        if service[:activity] && service[:activity][:position]&.to_sym
          service[:activity][:position] = service[:activity][:position]&.to_sym
        end

        service[:activities]&.each{ |activity|
          activity[:position] = activity[:position]&.to_sym
        }
      }

      hash[:vehicles].each{ |vehicle|
        vehicle[:router_dimension] = vehicle[:router_dimension]&.to_sym
        vehicle[:router_mode] = vehicle[:router_mode]&.to_sym
        vehicle[:shift_preference] = vehicle[:shift_preference]&.to_sym
        vehicle[:skills] = vehicle[:skills]&.map{ |sk_set| sk_set.map(&:to_sym) }
      }
    end

    def self.ensure_retrocompatibility(hash)
      self.convert_position_relations(hash)
      self.deduce_first_solution_strategy(hash)
      self.deduce_minimum_duration(hash)
      self.deduce_solver_parameter(hash)
      self.convert_route_indice_into_index(hash)
      self.convert_geometry_polylines_to_geometry(hash)
      self.convert_relation_lapse_into_lapses(hash)
      self.convert_partition_method_into_technique(hash)
    end

    def self.filter(hash)
      return hash if hash.empty?

      self.remove_unnecessary_units(hash)
      self.remove_unnecessary_relations(hash)
      self.generate_schedule_indices_from_date(hash)
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
      return unless hash[:relations]&.any?

      # TODO : remove this filter, VRP with duplicated relations should not be accepted
      uniq_relations = []
      hash[:relations].group_by{ |r| r[:type] }.each{ |_type, relations_set|
        uniq_relations += relations_set.uniq
      }
      hash[:relations] = uniq_relations

      return if hash[:configuration].to_h[:preprocessing].to_h[:partitions].to_a.any?{ |p| p[:entity] == :vehicle } ||
                hash[:relations].none?{ |r| r[:type] == :same_vehicle }

      hash[:relations].each{ |relation|
        next unless relation[:type] == :same_vehicle

        # when no partition with vehicle entity is provided then :same_vehicle corresponds to same_route
        relation[:type] = :same_route
      }
    end

    def self.find_relative_index(value, start_index)
      value.to_date.ajd.to_i - start_index
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

      start_value = find_relative_index(hash[:configuration][:schedule][:range_date][:start], start_index)
      element[unavailable_dates_key].to_a.each{ |unavailable_date|
        new_index = find_relative_index(unavailable_date, start_value)
        element[:unavailable_days] |= [new_index] if new_index.between?(start_index, end_index)
      }
      element.delete(unavailable_dates_key)

      return unless element[:unavailable_date_ranges]

      element[:unavailable_index_ranges] ||= []
      element[:unavailable_index_ranges] += element[:unavailable_date_ranges].collect{ |range|
        {
          start: find_relative_index(range[:start], start_value),
          end: find_relative_index(range[:end], start_value),
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

    def self.deduce_possible_days(hash, element, start_index)
      convert_possible_dates_into_indices(element, hash, start_index)

      element[:first_possible_days] = element[:first_possible_day_indices].to_a.slice(0..(element[:visits_number] || 1) - 1)
      element[:last_possible_days] = element[:last_possible_day_indices].to_a.slice(0..(element[:visits_number] || 1) - 1)

      %i[first_possible_day_indices first_possible_dates last_possible_day_indices last_possible_dates].each{ |k|
        element.delete(k)
      }
    end

    def self.convert_possible_dates_into_indices(element, hash, start_index)
      return unless hash[:configuration][:schedule][:range_date]

      start_value = find_relative_index(hash[:configuration][:schedule][:range_date][:start], start_index)
      element[:first_possible_day_indices] ||= element[:first_possible_dates].to_a.collect{ |date|
        find_relative_index(date, start_value)
      }

      element[:last_possible_day_indices] ||= element[:last_possible_dates].to_a.collect{ |date|
        find_relative_index(date, start_value)
      }
    end

    def self.detect_date_indices_inconsistency(hash)
      missions_and_vehicles = hash[:services] + hash[:vehicles]
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
      hash[:services].each{ |element|
        deduce_unavailable_days(hash, element, start_index, end_index, :visit)
        deduce_possible_days(hash, element, start_index)
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

      # remove schedule.range_date
      hash[:configuration][:schedule][:range_indices] = {
        start: start_index,
        end: end_index
      }
      hash[:configuration][:schedule][:start_date] = hash[:configuration][:schedule][:range_date][:start]
      hash[:configuration][:schedule].delete(:range_date)

      hash
    end

    def services_duration
      Helper.services_duration(self.services)
    end

    def visits
      Helper.visits(self.services)
    end

    def total_work_times
      schedule_start = self.configuration.schedule.range_indices[:start]
      schedule_end = self.configuration.schedule.range_indices[:end]
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
        tsp = TSPHelper.create_tsp(self, end_point: nil)
        solution = TSPHelper.solve(tsp)
        total_travel_time = solution.info.total_travel_time

        total_vehicle_work_time = vehicles.map{ |vehicle| vehicle.duration || vehicle.timewindow.end - vehicle.timewindow.start }.reduce(:+)
        average_vehicles_work_time = total_vehicle_work_time / vehicles.size.to_f
        total_service_time = services.map{ |service| service.activity.duration.to_i }.reduce(:+)

        # TODO: It assumes there is only one uniq location for all vehicle starts and ends
        depot = vehicles.collect(&:start_point).compact[0]
        approx_depot_time_correction =
          if depot.nil?
            0
          else
            average_loc = points.inject([0, 0]) { |sum, point|
              [sum[0] + point.location.lat, sum[1] + point.location.lon]
            }
            average_loc = [average_loc[0] / points.size, average_loc[1] / points.size]

            approximate_number_of_vehicles_used =
              ((total_service_time.to_f + total_travel_time) / average_vehicles_work_time).ceil

            approximate_number_of_vehicles_used * 2 *
              Helper.flying_distance(average_loc, [depot.location.lat, depot.location.lon])

            # TODO: Here we use flying_distance for approx_depot_time_correction;
            # however, this value is in terms of meters instead of seconds. Still since all dicho parameters
            # (i.e.: resolution.dicho_exclusion_scaling_angle, resolution.dicho_exclusion_rate, etc.)
            # are calculated with this functionality, correcting this bug makes the calculated parameters perform
            # less effective. We need to calculate new parameters after correcting the bug.

            # point_closest_to_center =
            # points.min_by{ |point| Helper::flying_distance(average_loc, [point.location.lat, point.location.lon]) }
            # ave_dist_to_depot = matrices[0][:time][point_closest_to_center.matrix_index][depot.matrix_index]
            # ave_dist_from_depot = matrices[0][:time][depot.matrix_index][point_closest_to_center.matrix_index]
            # approximate_number_of_vehicles_used * (ave_dist_to_depot + ave_dist_from_depot)
          end

        total_time_load = total_service_time + total_travel_time + approx_depot_time_correction

        average_service_load = total_time_load / services.size.to_f
        average_number_of_services_per_vehicle = average_vehicles_work_time / average_service_load
        exclusion_rate = configuration.resolution.dicho_exclusion_rate * average_number_of_services_per_vehicle
         # Angle needs to be in between 0 and 45 - 0 means only uniform cost is used -
         # 45 means only variable cost is used
        angle = configuration.resolution.dicho_exclusion_scaling_angle
        tan_variable = Math.tan(angle * Math::PI / 180)
        tan_uniform = Math.tan((45 - angle) * Math::PI / 180)
        coeff_variable_cost = tan_variable / (1 - tan_variable * tan_uniform)
        coeff_uniform_cost = tan_uniform / (1 - tan_variable * tan_uniform)

        services.each{ |service|
          service.exclusion_cost = (coeff_variable_cost *
            (max_fixed_cost / exclusion_rate * service.activity.duration / average_service_load) +
            coeff_uniform_cost * (max_fixed_cost / exclusion_rate)).ceil
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
      self.configuration.schedule && !self.configuration.schedule.range_indices.nil?
    end

    def periodic_heuristic?
      self.configuration.preprocessing.first_solution_strategy.to_a.include?('periodic')
    end
  end
end
