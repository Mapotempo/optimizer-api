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
  class Vehicle < Base
    field :cost_fixed, default: 0
    field :cost_distance_multiplier, default: 0
    field :cost_time_multiplier, default: 1
    field :cost_waiting_time_multiplier, default: 1
    field :cost_late_multiplier, default: nil
    field :cost_setup_time_multiplier, default: 0
    field :coef_setup, default: 1
    validates_numericality_of :cost_fixed
    validates_numericality_of :cost_distance_multiplier
    validates_numericality_of :cost_time_multiplier
    validates_numericality_of :cost_waiting_time_multiplier
    validates_numericality_of :cost_late_multiplier
    validates_numericality_of :cost_setup_time_multiplier
    validates_numericality_of :coef_setup

    field :skills, default: []

    belongs_to :start_point, class_name: 'Models::Point', inverse_of: :vehicle_start
    belongs_to :end_point, class_name: 'Models::Point', inverse_of: :vehicle_end
    has_many :quantities, class_name: 'Models::VehicleQuantity'
    has_many :timewindows, class_name: 'Models::Timewindow'
    has_many :rests, class_name: 'Models::Rest'

    belongs_to :vrp, class_name: 'Models::Vrp', inverse_of: :vehicles

    def matrix(matrix_indices)
      matrix_indices.collect{ |i|
        matrix_indices.collect{ |j|
          (vrp.matrix_time ? vrp.matrix_time[i][j] * cost_time_multiplier : 0) +
          (vrp.matrix_distance ? vrp.matrix_distance[i][j] * cost_distance_multiplier : 0)
        }
      }
    end

    def vrp
      self.attributes[:vrp]
    end
  end
end
