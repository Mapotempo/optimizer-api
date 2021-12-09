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
    tsp_suffix = Digest::MD5.hexdigest(
      (vrp.points.map(&:id) + vrp.services.map(&:id) + vrp.vehicles.map(&:id) + [Time.now.to_f, rand]).join(' ')
    )
    vehicle = options[:vehicle] || vrp.vehicles.first
    start_point = options.key?(:start_point) ? options[:start_point] : vehicle.start_point
    end_point = options.key?(:start_point) ? options[:end_point] : vehicle.end_point

    tsp_points = [convert_point(start_point, tsp_suffix), convert_point(end_point, tsp_suffix)].compact
    tsp_services = services.map{ |service|
      tsp_points << convert_point(service.activity.point, tsp_suffix)
      convert_service(service, tsp_suffix)
    }
    # raise tsp_points.map(&:id).uniq.inspect
    tsp_vehicle = {
      id: "#{tsp_suffix}_#{vehicle.id}",
      start_point_id: start_point && "#{tsp_suffix}_#{start_point.id}",
      end_point_id: end_point && "#{tsp_suffix}_#{end_point.id}",
      matrix_id: vehicle.matrix_id
    }

    problem = {
      matrices: [vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }],
      points: tsp_points.uniq{ |p| p[:id] },
      services: tsp_services,
      vehicles: [tsp_vehicle]
    }

    Models::Vrp.create(problem, delete: false)
  end

  def self.convert_point(point, tsp_suffix)
    {
      id: "#{tsp_suffix}_#{point.id}",
      matrix_index: point.matrix_index
    }
  end

  def self.convert_service(service, tsp_suffix)
    {
      id: "#{tsp_suffix}_#{service.id}",
      original_id: service.original_id || service.id,
      activity: {
        point_id: "#{tsp_suffix}_#{service.activity.point_id}",
        duration: service.activity.duration
      }
    }
  end

  def self.solve(tsp)
    vroom = OptimizerWrapper::VROOM
    progress = 0
    vroom.solve(tsp){
      progress += 1
    }
  end
end
