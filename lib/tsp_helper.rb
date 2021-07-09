# Copyright © Mapotempo, 2018
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

module TSPHelper
  def self.create_tsp(vrp, options = {})
    services = options[:services] || vrp.services
    vehicle = options[:vehicle] || vrp.vehicles.first
    start_point = options.key?(:start_point) ? options[:start_point] : vehicle.start_point
    end_point = options.key?(:start_point) ? options[:end_point] : vehicle.end_point

    tsp_points = [convert_point(start_point), convert_point(end_point)].compact
    tsp_services = services.map{ |service|
      tsp_points << convert_point(service.activity.point)
      convert_service(service)
    }
    # raise tsp_points.map(&:id).uniq.inspect
    tsp_vehicle = {
      id: vehicle.id,
      start_point_id: start_point&.id,
      end_point_id: end_point.id,
      matrix_id: vehicle.matrix_id
    }

    problem = {
      matrices: [vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }],
      points: tsp_points.uniq,
      services: tsp_services,
      vehicles: [tsp_vehicle]
    }
    Models::Vrp.create(problem)
  end

  def self.convert_point(point)
    {
      id: point.id,
      matrix_index: point.matrix_index
    }
  end

  def self.convert_service(service)
    {
      id: service.id,
      activity: {
        point_id: service.activity.point_id,
        duration: service.activity.duration
      }
    }
  end

  def self.solve(tsp)
    vroom = OptimizerWrapper::VROOM
    progress = 0
    result = vroom.solve(tsp){
      progress += 1
    }
  end
end
