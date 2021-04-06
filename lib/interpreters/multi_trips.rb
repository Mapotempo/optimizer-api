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

require './models/relation'

module Interpreters
  class MultiTrips
    def expand(vrp)
      vrp.vehicles = vrp.vehicles.collect{ |vehicle|
        if vehicle.trips > 1
          new_ids = Array.new(vehicle.trips) { |index| vehicle.id + '_trip_' + index.to_s }
          new_vehicles = new_ids.collect{ |id|
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle.original_id = new_vehicle.id
            new_vehicle.id = id
            new_vehicle.trips = 1
            new_vehicle
          }

          vrp.relations.select{ |relation| relation.linked_vehicle_ids.include?(vehicle.id) }.each{ |relation|
            relation.linked_vehicle_ids -= [vehicle.id]
            relation.linked_vehicle_ids += new_ids
          }

          vrp.relations += [Models::Relation.new(type: :vehicle_trips, linked_vehicle_ids: new_ids)]
          # vrp.relations += [Models::Relation.new(type: :vehicle_group_duration, linked_vehicle_ids: new_ids, lapse: vehicle.duration)] if vehicle.duration # TODO: Requires a complete rework of overall_duration
          # vrp.relations += [Models::Relation.new(type: :vehicle_group_duration, linked_vehicle_ids: new_ids, lapse: vehicle.overall_duration)] if vehicle.overall_duration # TODO: Requires a complete rework of overall_duration

          vrp.services.select{ |service| service.sticky_vehicles.any?{ |sticky_vehicle| sticky_vehicle.id == vehicle.id } }.each{ |service|
            service.sticky_vehicles -= [vehicle.id]
            service.sticky_vehicles += new_ids
          }

          new_vehicles
        else
          vehicle
        end
      }.flatten
      vrp
    end
  end
end
