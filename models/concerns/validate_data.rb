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

  def check_consistency(hash)
    hash[:services] ||= []
    hash[:shipments] ||= []
    @hash = hash

    ensure_uniq_ids
    ensure_no_conflicting_skills

    configuration = @hash[:configuration]
    schedule = configuration[:schedule] if configuration
    periodic_heuristic = configuration &&
                         configuration[:preprocessing] &&
                         configuration[:preprocessing][:first_solution_strategy].to_a.include?('periodic')
    check_matrices
    check_vehicles
    check_relations(periodic_heuristic)
    check_services_and_shipments(schedule)
    check_shipments_specificities

    check_routes(periodic_heuristic)
    check_configuration(configuration, periodic_heuristic) if configuration
  end

  def ensure_uniq_ids
    # TODO: Active Hash should be checking this
    [:matrices, :units, :points, :rests, :zones, :timewindows,
     :vehicles, :services, :shipments, :subtours].each{ |key|
      next if @hash[key]&.collect{ |v| v[:id] }&.uniq!.nil?

      raise OptimizerWrapper::DiscordantProblemError.new("#{key} IDs should be unique")
    }
  end

  def ensure_no_conflicting_skills
    all_skills = (@hash[:vehicles].to_a + @hash[:services].to_a + @hash[:shipments].to_a).flat_map{ |mission|
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

  def check_vehicles
    @hash[:vehicles]&.each{ |v|
      # vehicle time cost consistency
      if v[:cost_waiting_time_multiplier].to_f > (v[:cost_time_multiplier] || 1)
        raise OptimizerWrapper::DiscordantProblemError.new(
          'Cost_waiting_time_multiplier cannot be greater than cost_time_multiplier'
        )
      end

      # matrix_id consistency
      if v[:matrix_id] && (@hash[:matrices].nil? || @hash[:matrices].none?{ |m| m[:id] == v[:matrix_id] })
        raise OptimizerWrapper::DiscordantProblemError.new('There is no matrix with id vehicle[:matrix_id]')
      end
    }
  end

  def check_services_and_shipments(schedule)
    (@hash[:services].to_a + @hash[:shipments].to_a).each{ |mission|
      if (mission[:minimum_lapse] || 0) > (mission[:maximum_lapse] || 2**32)
        raise OptimizerWrapper::DiscordantProblemError.new('Minimum lapse can not be bigger than maximum lapse')
      end

      next if schedule && schedule[:range_indices] || mission[:visits_number].to_i <= 1

      raise OptimizerWrapper::DiscordantProblemError.new('There can not be more than one visit without schedule')
    }
  end

  def check_shipments_specificities
    forbidden_position_pairs = [
      [:always_middle, :always_first],
      [:always_last, :always_middle],
      [:always_last, :always_first]
    ]
    @hash[:shipments]&.each{ |shipment|
      return unless forbidden_position_pairs.include?([shipment[:pickup][:position], shipment[:delivery][:position]])

      raise OptimizerWrapper::DiscordantProblemError.new('Unconsistent positions in shipments.')
    }
  end

  def check_relations(periodic_heuristic)
    return unless @hash[:relations].to_a.any?

    # shipment relation consistency
    shipment_relations = @hash[:relations]&.select{ |r| r[:type] == :shipment }&.flat_map{ |r| r[:linked_ids] }.to_a
    unless shipment_relations.size == shipment_relations.uniq.size
      raise OptimizerWrapper::UnsupportedProblemError.new(
        'Services can appear in at most one shipment relation. '\
        'Following services appear in multiple shipment relations',
        [shipment_relations.select{ |id| shipment_relations.count(id) > 1 }.uniq]
      )
    end

    incompatible_relation_types = @hash[:relations].collect{ |r| r[:type] }.uniq - %i[force_first never_first force_end]
    return unless periodic_heuristic && incompatible_relation_types.any?

    raise OptimizerWrapper::DiscordantProblemError.new(
      "#{incompatible_relation_types} relations not available with specified first_solution_strategy"
    )
  end

  def check_routes(periodic_heuristic)
    @hash[:routes]&.each{ |route|
      route[:mission_ids].each{ |id|
        corresponding = @hash[:services]&.find{ |s| s[:id] == id } || @hash[:shipments]&.find{ |s| s[:id] == id }

        if corresponding.nil?
          raise OptimizerWrapper::DiscordantProblemError.new('Each mission_ids should refer to an existant id')
        end

        next unless corresponding[:activities] && periodic_heuristic

        raise OptimizerWrapper::UnsupportedProblemError.new('Services in routes should have only one activity')
      }
    }
  end

  def check_configuration(configuration, periodic_heuristic)
    check_clustering_parameters(configuration) if configuration[:preprocessing]
    check_schedule_consistency(configuration[:schedule]) if configuration[:schedule]
    check_periodic_consistency(configuration) if periodic_heuristic
    check_geometry_parameters(configuration) if configuration[:restitution]
  end

  def check_clustering_parameters(configuration)
    return unless configuration[:preprocessing][:partitions]&.any?{ |partition|
      partition[:entity].to_sym == :work_day
    }

    if @hash[:services].any?{ |s|
        min_lapse = s[:minimum_lapse]&.floor || 1
        max_lapse = s[:maximum_lapse]&.ceil || @hash[:configuration][:schedule][:range_indices][:end]

        s[:visits_number].to_i > 1 && (
          @hash[:configuration][:schedule][:range_indices][:end] <= 6 ||
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
    if schedule[:range_indices][:start] > 6
      raise OptimizerWrapper::DiscordantProblemError.new('Api does not support schedule start index bigger than 6')
      # TODO : allow start bigger than 6 and make code consistent with this
    end

    return unless schedule[:range_indices][:start] > schedule[:range_indices][:end]

    raise OptimizerWrapper::DiscordantProblemError.new('Schedule start index should be less than or equal to end')
  end

  def check_periodic_consistency(configuration)
    if @hash[:relations].to_a.any?{ |relation| relation[:type] == 'vehicle_group_duration_on_months' } &&
       (!configuration[:schedule] || configuration[:schedule][:range_indice])
      raise OptimizerWrapper::DiscordantProblemError.new(
        'Vehicle group duration on weeks or months is not available without range_date'
      )
    end

    unless @hash[:shipments].to_a.empty?
      raise OptimizerWrapper::DiscordantProblemError.new('Shipments are not available with periodic heuristic')
    end

    unless @hash[:vehicles].all?{ |vehicle| vehicle[:rests].to_a.empty? }
      raise OptimizerWrapper::DiscordantProblemError.new('Rests are not available with periodic heuristic')
    end

    if configuration[:resolution] && configuration[:resolution][:same_point_day] &&
       @hash[:services].any?{ |service| service[:activities].to_a.size.positive? }
      raise OptimizerWrapper.UnsupportedProblemError.new(
        'Same_point_day is not supported if a set has one service with several activities'
      )
    end
  end

  def check_geometry_parameters(configuration)
    return unless configuration[:restitution][:geometry].any? &&
                  !@hash[:points].all?{ |pt| pt[:location] }

    raise OptimizerWrapper::DiscordantProblemError.new('Geometry is not available if locations are not defined')
  end
end
