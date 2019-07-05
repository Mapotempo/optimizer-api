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
require './models/concerns/validate_timewindows'

module Models
  class Vehicle < Base
    field :original_id, default: nil
    field :cost_fixed, default: 0
    field :cost_distance_multiplier, default: 0
    field :cost_time_multiplier, default: 1
    field :cost_waiting_time_multiplier, default: nil
    field :cost_value_multiplier, default: 0
    field :cost_late_multiplier, default: nil
    field :cost_setup_time_multiplier, default: 0
    field :coef_service, default: 1
    field :coef_setup, default: 1
    field :additional_service, default: 0
    field :additional_setup, default: 0

    field :router_mode, default: :car
    field :router_dimension, default: :time
    field :traffic, default: false
    field :departure, default: nil
    field :speed_multiplier, default: 1
    field :area, default: []
    field :speed_multiplier_area, default: []
    field :motorway, default: true
    field :track, default: true
    field :toll, default: true
    field :trailers, default: nil
    field :weight, default: nil
    field :weight_per_axle, default: nil
    field :height, default: nil
    field :width, default: nil
    field :length, default: nil
    field :hazardous_goods, default: nil
    field :max_walk_distance, default: 750
    field :approach, default: nil
    field :snap, default: nil
    field :strict_restriction, default: false

    field :force_start, default: false
    field :shift_preference, default: :minimize_span
    field :trips, default: nil
    field :duration, default: nil
    field :overall_duration, default: nil
    field :distance, default: nil
    field :maximum_ride_time, default: nil
    field :maximum_ride_distance, default: nil
    field :matrix_id, default: nil
    field :value_matrix_id, default: nil

    field :unavailable_work_day_indices, default: []
    field :unavailable_work_date, default: nil
    field :global_day_index, default: nil

    field :skills, default: []

    field :free_approach, default: false
    field :free_return, default: false
    field :type_index, default: nil

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :cost_fixed
    # validates_numericality_of :cost_distance_multiplier
    # validates_numericality_of :cost_time_multiplier
    # validates_numericality_of :cost_waiting_time_multiplier
    # validates_numericality_of :cost_value_multiplier
    # validates_numericality_of :cost_late_multiplier, allow_nil: true
    # validates_numericality_of :cost_setup_time_multiplier
    # validates_numericality_of :coef_setup
    # validates_numericality_of :coef_service
    # validates_numericality_of :additional_setup
    # validates_numericality_of :additional_travel_time
    # validates_numericality_of :global_day_index, allow_nil: true
    # validates_inclusion_of :router_dimension, in: %w( time distance )
    # validates_inclusion_of :shift_preference, in: %w( force_start force_end minimize_span )
    # validates_numericality_of :trips, greater_than_or_equal_to: 0
    # validates_numericality_of :speed_multiplier
    # validates_numericality_of :duration, greater_than_or_equal_to: 0
    # validates_numericality_of :overall_duration, greater_than_or_equal_to: 0
    # validates_numericality_of :distance, greater_than_or_equal_to: 0

    has_many :sequence_timewindows, class_name: 'Models::Timewindow'

    belongs_to :start_point, class_name: 'Models::Point', inverse_of: :vehicle_start
    belongs_to :end_point, class_name: 'Models::Point', inverse_of: :vehicle_end
    belongs_to :timewindow, class_name: 'Models::Timewindow'
    has_many :capacities, class_name: 'Models::Capacity'
    # include ValidateTimewindows #<- This doesn't work
    has_many :rests, class_name: 'Models::Rest'

    def self.create(hash)
      if hash[:sequence_timewindows]&.size&.positive? && hash[:unavailable_work_day_indices]&.size&.positive? # X&.size&.positive? is not the same as !X&.empty?
        work_day_indices = hash[:sequence_timewindows].collect{ |tw| tw[:day_index] }
        hash[:unavailable_work_day_indices].delete_if{ |index| !work_day_indices.include?(index.modulo(7)) }
      end
      super(hash)
    end

    def need_matrix_time?
      cost_time_multiplier != 0 || cost_late_multiplier && cost_late_multiplier != 0 || cost_setup_time_multiplier != 0 ||
        !rests.empty? || maximum_ride_time || duration || overall_duration
    end

    def need_matrix_distance?
      cost_distance_multiplier != 0 || maximum_ride_distance || distance
    end

    def need_matrix_value?
      false
    end

    def matrix_time
      matrix && matrix.time
    end

    def matrix_distance
      matrix && matrix.distance
    end

    def matrix_value
      matrix && matrix.value
    end

    def matrix_blend(matrix, matrix_indices, dimensions, options = {})
      matrix_indices.collect{ |i|
        matrix_indices.collect{ |j|
          if i && j
            blend = (dimensions.include?(:time) && matrix.time ? matrix.time[i][j] * (options[:cost_time_multiplier] || 1) : 0) + # rubocop:disable Lint/UselessAssignment
                    (dimensions.include?(:distance) && matrix.distance ? matrix.distance[i][j] * (options[:cost_distance_multiplier] || 1) : 0) +
                    (dimensions.include?(:value) && matrix.value ? matrix.value[i][j] * (options[:value_matrix_multiplier] || 1) : 0)
          else
            0
          end
        }
      }
    end

    def dimensions
      d = [:time, :distance]
      dimensions = [d.delete(router_dimension.to_sym)]
      dimensions << d[0] if send('need_matrix_' + d[0].to_s + '?')
      dimensions
    end

    def router_options
      {
        traffic: traffic,
        departure: departure,
        speed_multiplier: speed_multiplier,
        area: area,
        speed_multiplier_area: speed_multiplier_area,
        track: track,
        motorway: motorway,
        toll: toll,
        trailers: trailers,
        weight: weight,
        weight_per_axle: weight_per_axle,
        height: height,
        width: width,
        length: length,
        hazardous_goods: hazardous_goods,
        max_walk_distance: max_walk_distance,
        approach: approach,
        snap: snap,
        strict_restriction: strict_restriction
      }
    end

    def working_week_days()
      return @working_week_days ||= self[:sequence_timewindows].collect(&:day_index)
    end

    def working_day_indices_in_range(range_start, range_end)
      @working_range_indices ||= {}

      if @working_range_indices[[range_start, range_end]].nil? # if info for this range is not already calculated, calculate
        range = (range_start..range_end).to_a
        unavailable_work_day_indices = self[:unavailable_work_day_indices] || [] # We do this because unavailable_work_day_indices can be nil instead of []. Normally create function should handle this
        @working_range_indices[[range_start, range_end]] = (range - unavailable_work_day_indices).delete_if{ |range_day| !working_week_days().include?(range_day.modulo(7)) }
      end

      return @working_range_indices[[range_start, range_end]]
    end

    def total_work_days_in_range(range_start, range_end)
      return working_day_indices_in_range(range_start, range_end).size
    end

    def total_work_time_in_range(range_start, range_end)
      @total_work_time_in_range ||= {}

      if @total_work_time_in_range[[range_start, range_end]].nil? # if info for this range is not already calculated, calculate
        total_work_time = 0
        working_day_indices_in_range(range_start, range_end).group_by{ |range_day| range_day.modulo(7) }.each{ |group|
          week_day_index = group[0]
          occurence = group[1].size
          tw_index = working_week_days().find_index(week_day_index)
          tw = self[:sequence_timewindows][tw_index]
          total_work_time += (tw[:end] - tw[:start]) * occurence
        }
        @total_work_time_in_range[[range_start, range_end]] = total_work_time
      end

      return @total_work_time_in_range[[range_start, range_end]]
    end
  end
end
