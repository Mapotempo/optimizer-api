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
    field :preprocessing_cluster_threshold, default: nil
    field :preprocessing_prefer_short_segment, default: false
    field :resolution_duration, default: nil
    field :resolution_iterations, default: nil
    field :resolution_iterations_without_improvment, default: 100
    field :resolution_stable_iterations, default: nil
    field :resolution_stable_coefficient, default: nil
    validates_numericality_of :preprocessing_cluster_threshold
    validates_numericality_of :resolution_duration
    validates_numericality_of :resolution_iterations
    validates_numericality_of :resolution_iterations_without_improvment
    validates_numericality_of :resolution_stable_iterations
    validates_numericality_of :resolution_stable_coefficient

    fields :matrix_time, :matrix_distance

    has_many :points, class_name: 'Models::Point'
    has_many :services, class_name: 'Models::Service'
    has_many :shipments, class_name: 'Models::Shipment'
    has_many :rests, class_name: 'Models::Rest'
    has_many :vehicles, class_name: 'Models::Vehicle'
    has_many :units, class_name: 'Models::Units'

    def matrices=(matrices)
      self.matrix_time = matrices[:time]
      self.matrix_distance = matrices[:distance]
    end

    def configuration=(configuration)
      self.preprocessing = configuration[:preprocessing] if configuration[:preprocessing]
      self.resolution = configuration[:resolustion] if configuration[:resolustion]
    end

    def resolution=(resolution)
      self.resolution_duration = resolution[:duration]
      self.resolution_iterations = resolution[:iterations]
      self.resolution_iterations_without_improvment = resolution[:iterations_without_improvment]
      self.resolution_stable_iterations = resolution[:stable_iterations]
      self.resolution_stable_coefficient = resolution[:stable_coefficient]
    end

    def preprocessing=(preprocessing)
      self.preprocessing_cluster_threshold = preprocessing[:cluster_threshold]
      self.preprocessing_prefer_short_segment = preprocessing[:prefer_short_segment]
    end

    def need_matrix_time?
      vehicles.find{ |vehicle|
        vehicle.cost_time_multiplier || vehicle.cost_waiting_time_multiplier || vehicle.cost_late_multiplier || vehicle.cost_setup_time_multiplier ||
        !vehicle.rest.empty?
      } ||
      services.find{ |service|
        !service.timewindows.empty? || service.late_multiplier
      } ||
      shipments.find{ |shipment|
        !shipments.pickup.timewindows.empty? || shipments.pickup.late_multiplier ||
        !shipments.delivery.timewindows.empty? || shipments.delivery.late_multiplier
      }
    end

    def need_matrix_distance?
      vehicles.find{ |vehicle|
        vehicle.cost_distance_multiplier
      }
    end

    def matrix(matrix_indices, cost_time_multiplier, cost_distance_multiplier)
      matrix_indices.collect{ |i|
        matrix_indices.collect{ |j|
          (matrix_time ? matrix_time[i][j] * cost_time_multiplier : 0) +
          (matrix_distance ? matrix_distance[i][j] * cost_distance_multiplier : 0)
        }
      }
    end
  end
end
