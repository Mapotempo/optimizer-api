# Copyright © Mapotempo, 2021
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
require 'active_support/concern'

# Expands provided data
module ValidateData
  extend ActiveSupport::Concern
  POSITION_RELATIONS = %i[order sequence shipment].freeze
  def check_consistency(hash)
    hash[:services] ||= []
    hash[:vehicles] ||= []
    hash[:relations] ||= []
    @hash = hash

    ensure_no_conflicting_skills

    configuration = @hash[:configuration]
    schedule = configuration && configuration[:schedule]
    periodic_heuristic = schedule &&
                         configuration[:preprocessing] &&
                         configuration[:preprocessing][:first_solution_strategy].to_a.include?('periodic')
    check_matrices
    check_vehicles(periodic_heuristic)
    check_relations(periodic_heuristic)
    check_services(schedule)

    check_routes(periodic_heuristic)
    check_configuration(configuration, periodic_heuristic)
  end

  def ensure_no_conflicting_skills
    all_skills = (@hash[:vehicles] + @hash[:services]).flat_map{ |mission|
      mission[:skills]
    }.compact.uniq

    return unless ['vehicle_partition_', 'work_day_partition_'].any?{ |str|
      all_skills.any?{ |skill| skill.to_s.start_with?(str) }
    }

    raise OptimizerWrapper::UnsupportedProblemError.new(
      "There are vehicles or services with 'vehicle_partition_*', 'work_day_partition_*' skills. " \
      'These skill patterns are reserved for internal use and they would lead to unexpected behaviour.'
    )
  end

  def check_matrices
    # matrix_index consistency
    if @hash[:matrices].nil? || @hash[:matrices].empty?
      if @hash[:points]&.any?{ |p| p[:matrix_index] }
        raise OptimizerWrapper::DiscordantProblemError.new(
          'There is a point with point[:matrix_index] defined but there is no matrix'
        )
      end
    else
      max_matrix_index = @hash[:points].max{ |p| p[:matrix_index] || -1 }[:matrix_index] || -1
      matrix_not_big_enough = @hash[:matrices].any?{ |matrix_group|
        Models::Matrix.field_names.any?{ |dimension|
          matrix_group[dimension] &&
            (matrix_group[dimension].size <= max_matrix_index ||
              matrix_group[dimension].any?{ |col| col.size <= max_matrix_index })
        }
      }
      if matrix_not_big_enough
        raise OptimizerWrapper::DiscordantProblemError.new(
          'All matrices should have at least maximum(point[:matrix_index]) number of rows and columns'
        )
      end
    end
  end

  def check_vehicles(periodic_heuristic)
    @hash[:vehicles].each{ |v|
      if v[:cost_waiting_time_multiplier].to_f > (v[:cost_time_multiplier] || 1)
        raise OptimizerWrapper::DiscordantProblemError.new(
          'Cost_waiting_time_multiplier cannot be greater than cost_time_multiplier'
        )
      end

      if v[:matrix_id] && (@hash[:matrices].nil? || @hash[:matrices].none?{ |m| m[:id] == v[:matrix_id] })
        raise OptimizerWrapper::DiscordantProblemError.new('There is no matrix with id vehicle[:matrix_id]')
      end

      if v[:timewindow] || v[:sequence_timewindows]
        [v[:timewindow], v[:sequence_timewindows]].compact.flatten.each{ |tw|
          next unless tw[:start] && tw[:end] && tw[:start] > tw[:end]

          raise OptimizerWrapper::DiscordantProblemError.new('Vehicle timewindows are infeasible')
        }
      end

      next unless periodic_heuristic

      if v[:skills].to_a.size > 1
        raise OptimizerWrapper::DiscordantProblemError.new('Periodic heuristic does not support vehicle alternative skills')
      end
    }
  end

  def check_services(schedule)
    @hash[:services]&.each{ |mission|
      if (mission[:minimum_lapse] || 0) > (mission[:maximum_lapse] || 2**32)
        raise OptimizerWrapper::DiscordantProblemError.new('Minimum lapse can not be bigger than maximum lapse')
      end

      next if schedule && schedule[:range_indices] || mission[:visits_number].to_i <= 1

      raise OptimizerWrapper::DiscordantProblemError.new('There can not be more than one visit without schedule')
    }
  end

  # In a sequence s1->s2, s2 cannot be served if its timewindows have ended before
  # any timewindows of s1 have started
  def check_relation_consistent_timewindows
    unconsistent_relation_timewindows = []
    @hash[:relations].each{ |relation|
      unless relation[:linked_ids]&.uniq == relation[:linked_ids]
        raise OptimizerWrapper::DiscordantProblemError.new('Same ID is provided multiple times in one relation.')
      end

      unless relation[:linked_vehicle_ids]&.uniq == relation[:linked_vehicle_ids]
        raise OptimizerWrapper::DiscordantProblemError.new('Same vehicle ID is provided multiple times in one relation.')
      end

      next unless POSITION_RELATIONS.include?(relation[:type])

      latest_sequence_earliest_arrival = nil
      services = relation[:linked_ids].map{ |linked_id|
        @hash[:services].find{ |service| service[:id] == linked_id }
      }
      services.each{ |service|
        next unless service[:activity][:timewindows]&.any?

        earliest_arrival = service[:activity][:timewindows].map{ |tw| (tw[:day_index] || 0) * 86400 + (tw[:start] || 0) }.min
        latest_arrival = service[:activity][:timewindows].map{ |tw| (tw[:day_index] || 0) * 86400 + (tw[:end] || 86399) }.max -
                         service[:activity][:duration]

        latest_sequence_earliest_arrival = [latest_sequence_earliest_arrival, earliest_arrival].compact.max
        if latest_arrival < latest_sequence_earliest_arrival
          unconsistent_relation_timewindows << relation[:linked_ids]
        end
      }
    }
    return unless unconsistent_relation_timewindows.any?

    raise OptimizerWrapper::DiscordantProblemError.new("Unconsistent timewindows within relations: #{unconsistent_relation_timewindows}")
  end

  def check_vehicle_trips_relation_consistency
    # :prioritize_first_available_trips_and_vehicles logic depends on this check
    all_trips = @hash[:relations].flat_map{ |r| r[:linked_vehicle_ids] if r[:type].to_sym == :vehicle_trips }.compact
    return unless @hash[:vehicles].any?{ |v| all_trips.count(v[:id]) > 1 }

    raise OptimizerWrapper::UnsupportedProblemError.new(
      'A vehicle cannot appear in more than one vehicle_trips relation'
    )
  end

  def check_position_relation_specificities
    forbidden_position_pairs = [
      [:always_middle, :always_first],
      [:always_last, :always_middle],
      [:always_last, :always_first]
    ]

    unconsistent_position_services = []
    @hash[:relations].each{ |relation|
      next unless POSITION_RELATIONS.include?(relation[:type])

      services = relation[:linked_ids].map{ |linked_id|
        @hash[:services].find{ |service| service[:id] == linked_id }
      }
      previous_service = nil
      services.each{ |service|
        if previous_service && forbidden_position_pairs.include?([previous_service[:activity][:position], service[:activity][:position]])
          unconsistent_position_services << [previous_service[:id], service[:id]]
        end
        previous_service = service
      }
    }

    return unless unconsistent_position_services.any?

    raise OptimizerWrapper::DiscordantProblemError.new("Unconsistent positions in relations: #{unconsistent_position_services}")
  end

  def calculate_day_availabilities(vehicles, timewindow_arrays)
    vehicles_days = timewindow_arrays.collect{ |timewindows|
      if timewindows.empty?
        []
      else
        days = timewindows.flat_map{ |tw| tw[:day_index] || (0..6).to_a }
        days.compact!
        days.uniq
      end
    }.delete_if(&:empty?)

    vehicles_unavailable_indices = vehicles.collect{ |v| v[:unavailable_work_day_indices] }
    vehicles_unavailable_indices.compact!

    [vehicles_days, vehicles_unavailable_indices]
  end

  def check_vehicle_trips_stores_consistency(relation_vehicles)
    relation_vehicles.each_with_index{ |vehicle_trip, v_i|
      case v_i
      when 0
        unless vehicle_trip[:end_point_id]
          raise OptimizerWrapper::DiscordantProblemError.new('First trip should at least have an end point id')
        end
      when relation_vehicles.size - 1
        unless vehicle_trip[:start_point_id]
          raise OptimizerWrapper::DiscordantProblemError.new('Last trip should at least have a start point id')
        end
      else
        unless vehicle_trip[:start_point_id] && vehicle_trip[:end_point_id]
          raise OptimizerWrapper::DiscordantProblemError.new(
            'Intermediary trips should have a start and an end point ids'
          )
        end
      end

      next if v_i.zero? ||
              vehicle_trip[:start_point_id] == relation_vehicles[v_i - 1][:end_point_id] ||
              (@hash[:points].find{ |pt| pt[:id] == vehicle_trip[:start_point_id] }[:location] ==
                @hash[:points].find{ |pt| pt[:id] == relation_vehicles[v_i - 1][:end_point_id] }[:location])

      raise OptimizerWrapper::DiscordantProblemError.new('One trip should start where the previous trip ended')
    }
  end

  def check_trip_timewindows_consistency(relation_vehicles)
    vehicles_timewindows =
      relation_vehicles.collect{ |v| v[:timewindow] ? [v[:timewindow]] : v[:sequence_timewindows].to_a }

    return if vehicles_timewindows.all?(&:empty?)

    week_days, unavailable_indices = calculate_day_availabilities(relation_vehicles, vehicles_timewindows)
    if week_days.uniq.size > 1 || unavailable_indices.uniq.size > 1
      raise OptimizerWrapper::UnsupportedProblemError.new(
        'Vehicles in vehicle_trips relation should have the same available days'
      )
    end

    vehicles_timewindows.each_with_index{ |v_tw, v_i|
      next if v_i.zero?

      v_tw.each{ |tw|
        day = tw[:day_index]
        previous_tw =
          vehicles_timewindows[v_i - 1].select{ |ptw|
            ptw[:day_index].nil? ||
              ptw[:day_index] == day
          }.min_by{ |ptw| ptw[:start] }

        unless previous_tw.nil? || tw[:end] > previous_tw[:start]
          raise OptimizerWrapper::DiscordantProblemError.new('Timewindows do not allow vehicle trips')
        end
      }
    }
  end

  def check_consistent_ids_provided(relation)
    case relation[:type]
    when *Models::Relation::ON_VEHICLES_TYPES
      if relation[:linked_ids].to_a.any? || relation[:linked_vehicle_ids].to_a.empty?
        raise OptimizerWrapper::DiscordantProblemError.new(
          "#{relation[:type]} relations do not support linked_ids and expect linked_vehicle_ids"
        )
      end
    when *Models::Relation::ON_SERVICES_TYPES
      if relation[:linked_vehicle_ids].to_a.any? || relation[:linked_ids].to_a.empty?
        raise OptimizerWrapper::DiscordantProblemError.new(
          "#{relation[:type]} relations do not support linked_vehicle_ids and expect linked_ids"
        )
      end
    else
      raise 'Unknown relation type' # in case we ever forget to handle a new relation type
    end
  end

  def check_consistent_lapses_provided(relation)
    case relation[:type]
    when *Models::Relation::NO_LAPSE_TYPES
      if relation[:lapse] || relation[:lapses].to_a.any?
        raise OptimizerWrapper::DiscordantProblemError.new(
          "#{relation[:type]} relations do not expect any lapse"
        )
      end
    when *Models::Relation::ONE_LAPSE_TYPES
      if relation[:lapse].nil? && relation[:lapses].to_a.size != 1
        raise OptimizerWrapper::DiscordantProblemError.new(
          "#{relation[:type]} relations expect exactly one lapse"
        )
      end
    when *Models::Relation::SEVERAL_LAPSE_TYPES
      relation[:lapses] = [0] if relation[:type] == :vehicle_trips && relation[:lapse].nil? && relation[:lapses].nil?
      if relation[:lapse].nil? && relation[:lapses].to_a.size != 1
        exp_lapse_count = (relation[:linked_ids]&.size || relation[:linked_vehicle_ids]&.size) - 1
        if relation[:lapses].to_a.size != exp_lapse_count
          raise OptimizerWrapper::DiscordantProblemError.new(
            "#{relation[:type]} relations expect at least one lapse"
          )
        end
      end
    else
      raise 'Unknown relation type' # in case we ever forget to handle a new relation type
    end
  end

  def check_relations(periodic_heuristic)
    return unless @hash[:relations].any?

    @hash[:relations].each{ |relation|
      relation_services =
        relation[:linked_ids].to_a.collect{ |s_id| @hash[:services].find{ |s| s[:id] == s_id } }
      relation_vehicles =
        relation[:linked_vehicle_ids].to_a.collect{ |v_id| @hash[:vehicles].find{ |v| v[:id] == v_id } }

      if relation_vehicles.any?(&:nil?) || relation_services.any?(&:nil?)
        # FIXME: linked_vehicle_ids should be directly related to vehicle objects of the model
        raise OptimizerWrapper::DiscordantProblemError.new(
          'At least one ID in relations does not match with any provided vehicle or service from the data'
        )
      end

      check_consistent_ids_provided(relation)
      check_consistent_lapses_provided(relation)

      case relation[:type].to_sym
      when :vehicle_trips
        check_vehicle_trips_stores_consistency(relation_vehicles)
        check_trip_timewindows_consistency(relation_vehicles)
      end
    }

    # shipment relation consistency
    if @hash[:relations].any?{ |r| r[:type] == :shipment }
      shipment_relations = @hash[:relations].select{ |r| r[:type] == :shipment }
      service_ids = @hash[:services].map{ |s| s[:id] }

      shipments_with_invalid_linked_ids = shipment_relations.reject{ |r| r[:linked_ids].all?{ |s_id| service_ids.include?(s_id) } }
      unless shipments_with_invalid_linked_ids.empty?
        raise OptimizerWrapper::DiscordantProblemError.new(
          'Shipment relations need to have two valid services -- a pickup and a delivery. ' \
          'The following services of shipment relations are invalid: ' \
          "#{shipments_with_invalid_linked_ids.flat_map{ |r| r[:linked_ids].select{ |s_id| service_ids.exclude?(s_id) } }.uniq.sort.join(', ')}"
        )
      end

      shipments_not_having_exactly_two_linked_ids = shipment_relations.reject{ |r| r[:linked_ids].uniq.size == 2 }
      unless shipments_not_having_exactly_two_linked_ids.empty?
        raise OptimizerWrapper::DiscordantProblemError.new(
          'Shipment relations need to have two services -- a pickup and a delivery. ' \
          'Relations of following services does not have exactly two linked_ids: ' \
          "#{shipments_not_having_exactly_two_linked_ids.flat_map{ |r| r[:linked_ids] }.uniq.sort.join(', ')}"
        )
      end

      pickups = shipment_relations.map{ |r| r[:linked_ids].first }
      deliveries = shipment_relations.map{ |r| r[:linked_ids].last }
      services_that_are_both_pickup_and_delivery = pickups & deliveries
      unless services_that_are_both_pickup_and_delivery.empty?
        raise OptimizerWrapper::UnsupportedProblemError.new(
          'A service cannot be both a delivery and a pickup in different relations. '\
          'Following services appear in multiple shipment relations both as pickup and delivery: ',
          [services_that_are_both_pickup_and_delivery]
        )
      end
    end

    check_vehicle_trips_relation_consistency
    check_position_relation_specificities
    check_relation_consistent_timewindows
    check_sticky_relation_consistency

    if periodic_heuristic
      incompatible_relation_types = @hash[:relations].collect{ |r| r[:type] }.uniq - %i[force_first never_first force_end same_vehicle]
      err_msg = "#{incompatible_relation_types} relations not available with specified first_solution_strategy"
      raise OptimizerWrapper::UnsupportedProblemError.new(err_msg) if incompatible_relation_types.any?
    end

    check_relation_visits_number_lapse_consistency
  end

  def check_relation_visits_number_lapse_consistency
    # Do the check from exclusion point of view so that new relations can be considered automatically
    relations_not_needing_matching_visits_number_and_lapses = %i[
      force_end
      force_first
      never_first
      same_vehicle
      vehicle_trips
      vehicle_group_duration
      vehicle_group_duration_on_weeks
      vehicle_group_duration_on_months
      vehicle_group_number
    ].freeze

    @hash[:relations]&.each{ |relation|
      next if relations_not_needing_matching_visits_number_and_lapses.include?(relation[:type].to_sym)

      services_in_relation = relation[:linked_ids]&.collect{ |s_id| @hash[:services].find{ |s| s[:id] == s_id } } || []
      if services_in_relation.uniq{ |s| s[:visits_number] || 1 }.size > 1
        raise OptimizerWrapper::UnsupportedProblemError.new(
          'Services in relations should have the same visits_number. '\
          'Following services in relation but they have different visits_number values: ',
          [relation[:linked_ids]]
        )
      elsif services_in_relation.uniq{ |s| [s[:minimum_lapse] || 1, s[:maximum_lapse].to_i] }.size > 1
        raise OptimizerWrapper::UnsupportedProblemError.new(
          'Services in relations should have the same minimum_lapse and maximum_lapse. '\
          'Following services in relation but they have different lapse values: ',
          [relation[:linked_ids]]
        )
      end
    }
  end

  def check_sticky_relation_consistency
    unconsistent_stickies = []
    @hash[:relations].none?{ |relation|
      relation_sticky_ids = []
      services = @hash[:services].select{ |service| relation[:linked_ids]&.include?(service[:id]) }
      services.none?{ |service|
        sticky_ids = service[:sticky_vehicle_ids] || []

        if relation_sticky_ids.any? && sticky_ids.any? && (sticky_ids & relation_sticky_ids).empty?
          unconsistent_stickies << services.map{ |s| s[:id] }
        end
        relation_sticky_ids += sticky_ids
      }
    }
    return unless unconsistent_stickies.any?

    raise OptimizerWrapper::UnsupportedProblemError.new(
      'All services from a relation should have consistent sticky_vehicle_ids or none'\
      'Following services have different sticky_vehicle_ids: ',
      unconsistent_stickies
    )
  end

  def check_routes(periodic_heuristic)
    @hash[:routes]&.each{ |route|
      route[:mission_ids].each{ |id|
        corresponding = @hash[:services]&.find{ |s| s[:id] == id }

        if corresponding.nil?
          raise OptimizerWrapper::DiscordantProblemError.new('Each mission_ids should refer to an existant id')
        end

        next unless corresponding[:activities] && periodic_heuristic

        raise OptimizerWrapper::UnsupportedProblemError.new('Services in routes should have only one activity')
      }
    }
  end

  def check_configuration(configuration, periodic_heuristic)
    return unless configuration

    check_clustering_parameters(configuration)
    check_schedule_consistency(configuration[:schedule])
    check_periodic_consistency(configuration, periodic_heuristic)
    check_geometry_parameters(configuration)
  end

  def check_clustering_parameters(configuration)
    return unless configuration && configuration[:preprocessing]

    if @hash[:relations].any?{ |relation| relation[:type].to_sym == :vehicle_trips }
      if configuration[:preprocessing][:partitions]&.any?
        raise OptimizerWrapper::UnsupportedProblemError.new(
          'Partitioning is not currently available with vehicle_trips relation'
        )
      end
    end

    return unless configuration[:preprocessing][:partitions]&.any?{ |partition|
      partition[:entity].to_sym == :work_day
    } && configuration[:schedule]

    if @hash[:services].any?{ |s|
        min_lapse = s[:minimum_lapse]&.floor || 1
        max_lapse = s[:maximum_lapse]&.ceil || configuration[:schedule][:range_indices][:end]

        s[:visits_number].to_i > 1 && (
          configuration[:schedule][:range_indices][:end] <= 6 ||
          (min_lapse..max_lapse).none?{ |intermediate_lapse| (intermediate_lapse % 7).zero? }
       )
      }

      raise OptimizerWrapper::DiscordantProblemError.new(
        'Work day partition implies that lapses of all services can be a multiple of 7.
        There are services whose minimum and maximum lapse do not permit such lapse'
      )
    end
  end

  def check_schedule_consistency(schedule)
    return unless schedule

    if schedule[:range_indices][:start] > 6
      raise OptimizerWrapper::DiscordantProblemError.new('Api does not support schedule start index bigger than 6')
      # TODO : allow start bigger than 6 and make code consistent with this
    end

    return unless schedule[:range_indices][:start] > schedule[:range_indices][:end]

    raise OptimizerWrapper::DiscordantProblemError.new('Schedule start index should be less than or equal to end')
  end

  def check_periodic_consistency(configuration, periodic_heuristic)
    return unless configuration && periodic_heuristic

    if @hash[:relations].any?{ |relation| relation[:type] == :vehicle_group_duration_on_months } &&
       (!configuration[:schedule] || configuration[:schedule][:range_indice])
      raise OptimizerWrapper::DiscordantProblemError.new(
        'Vehicle group duration on weeks or months is not available without range_date'
      )
    end

    unless @hash[:vehicles].all?{ |vehicle| vehicle[:rests].to_a.empty? }
      raise OptimizerWrapper::UnsupportedProblemError.new('Rests are not available with periodic heuristic')
    end

    if configuration[:resolution] && configuration[:resolution][:same_point_day] &&
       @hash[:services].any?{ |service| service[:activities].to_a.size.positive? }
      raise OptimizerWrapper.UnsupportedProblemError.new(
        'Same_point_day is not supported if a set has one service with several activities'
      )
    end
  end

  def check_geometry_parameters(configuration)
    return unless configuration &&
                  configuration[:restitution] &&
                  configuration[:restitution][:geometry]&.any?

    return if @hash[:points].all?{ |pt| pt[:location] }

    raise OptimizerWrapper::DiscordantProblemError.new('Geometry is not available if locations are not defined')
  end
end
