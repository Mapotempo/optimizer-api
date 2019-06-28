# Copyright © Mapotempo, 2019
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

module DistanceMatrix
  extend ActiveSupport::Concern

  def compute_matrix(&block)
    compute_need_matrix(&block)
  end

  private

  def compute_vrp_need_matrix
    [
      need_matrix_time? ? :time : nil,
      need_matrix_distance? || need_matrix_distance? ? :distance : nil,
      need_matrix_value? ? :value : nil
    ].compact
  end

  def compute_need_matrix(&block)
    vrp_need_matrix = compute_vrp_need_matrix
    need_matrix = vehicles.collect{ |vehicle| [vehicle, vehicle.dimensions] }.select{ |vehicle, dimensions|
      dimensions.find{ |dimension|
        vrp_need_matrix.include?(dimension) && (vehicle.matrix_id.nil? || matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.send(dimension).nil?) && vehicle.send('need_matrix_' + dimension.to_s + '?')
      }
    }
    if !need_matrix.empty?
      matrix_points = points.each_with_index.collect{ |point, index|
        point.matrix_index = index
        [point.location.lat, point.location.lon]
      }
      vehicles.select(&:start_point).each{ |v|
        v.start_point.matrix_index = points.find{ |p| p.id == v.start_point.id }.matrix_index
      }
      vehicles.select(&:end_point).each{ |v|
        v.end_point.matrix_index = points.find{ |p| p.id == v.end_point.id }.matrix_index
      }

      uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
        [vehicle.router_mode.to_sym, dimensions | vrp_need_matrix, vehicle.router_options]
      }.uniq

      i = 0
      id = 0
      uniq_need_matrix = Hash[uniq_need_matrix.collect{ |mode, dimensions, options|
        block.call(nil, i += 1, uniq_need_matrix.size, 'compute matrix', nil, nil, nil) if block
        # set matrix_time and matrix_distance depending of dimensions order
        router_matrices = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], mode, dimensions, matrix_points, matrix_points, options)
        m = Models::Matrix.create(
          id: 'm' + (id += 1).to_s,
          time: (router_matrices[dimensions.index(:time)] if dimensions.index(:time)),
          distance: (router_matrices[dimensions.index(:distance)] if dimensions.index(:distance)),
          value: (router_matrices[dimensions.index(:value)] if dimensions.index(:value))
        )
        self.matrices += [m]
        [[mode, dimensions, options], m]
      }]

      uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
        vehicle.matrix_id = matrices.find{ |matrix| matrix == uniq_need_matrix[[vehicle.router_mode.to_sym, dimensions | vrp_need_matrix, vehicle.router_options]] }.id
      }
    end
  end

  def need_matrix_time?
    !(services.find{ |service|
      !service.activity.timewindows.empty? || service.activity.late_multiplier && service.activity.late_multiplier != 0
    } ||
    shipments.find{ |shipment|
      !shipment.pickup.timewindows.empty? || shipment.pickup.late_multiplier && shipment.pickup.late_multiplier != 0 ||
      !shipment.delivery.timewindows.empty? || shipment.delivery.late_multiplier && shipment.delivery.late_multiplier != 0
    } ||
    vehicles.find(&:need_matrix_time?)).nil?
  end

  def need_matrix_distance?
    !vehicles.find(&:need_matrix_distance?).nil?
  end

  def need_matrix_value?
    false
  end
end
