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
    field :cost_fixed, default: 0
    field :cost_distance_multiplier, default: 0
    field :cost_time_multiplier, default: 1
    field :cost_waiting_time_multiplier, default: 1
    field :cost_late_multiplier, default: nil
    field :cost_setup_time_multiplier, default: 0
    field :coef_setup, default: 1
    field :router_mode, default: :car
    field :router_dimension, default: :time
    field :speed_multiplier, default: 1
    field :duration, default: nil
    field :matrix_id, default: nil
    validates_numericality_of :cost_fixed
    validates_numericality_of :cost_distance_multiplier
    validates_numericality_of :cost_time_multiplier
    validates_numericality_of :cost_waiting_time_multiplier
    validates_numericality_of :cost_late_multiplier, allow_nil: true
    validates_numericality_of :cost_setup_time_multiplier
    validates_numericality_of :coef_setup
    validates_inclusion_of :router_mode, in: %w( car car_urban truck pedestrian cycle public_transport )
    validates_inclusion_of :router_dimension, in: %w( time distance )
    validates_numericality_of :speed_multiplier
    field :skills, default: []

    belongs_to :start_point, class_name: 'Models::Point', inverse_of: :vehicle_start
    belongs_to :end_point, class_name: 'Models::Point', inverse_of: :vehicle_end
    belongs_to :timewindow, class_name: 'Models::Timewindow'
    has_many :capacities, class_name: 'Models::Capacity'
    include ValidateTimewindows
    has_many :rests, class_name: 'Models::Rest'

    def need_matrix_time?
      cost_time_multiplier != 0 || cost_waiting_time_multiplier != 0 || cost_late_multiplier != 0 || cost_setup_time_multiplier != 0 ||
      !rest.empty?
    end

    def need_matrix_distance?
      cost_distance_multiplier != 0
    end

    def matrix_time
      matrix && matrix.time
    end

    def matrix_distance
      matrix && matrix.distance
    end

    def matrix_blend(matrix, matrix_indices, dimensions, options = {})
      matrix_indices.collect{ |i|
        matrix_indices.collect{ |j|
          if i && j
            (dimensions.include?(:time) && matrix.time ? matrix.time[i][j] * (options[:cost_time_multiplier] || 1) : 0) +
            (dimensions.include?(:distance) && matrix.distance ? matrix.distance[i][j] * (options[:cost_distance_multiplier] || 1) : 0)
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
  end
end
