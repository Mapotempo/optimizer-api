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
        if vehicle.trips && vehicle.trips >= 1
          new_ids = (0..vehicle.trips - 1).collect{ |index| vehicle.id + '_trip_' + index.to_s }
          containing_relations = vrp.relations.select{ |relation| relation.linked_vehicle_ids.include?(vehicle.id) }.each{ |relation|
            relation.linked_vehicle_ids -= vehicle.id
            relation.linked_vehicle_ids += new_ids
          }
          vrp.relations += [Models::Relation.new(type: 'vehicle_trips', linked_vehicle_ids: new_ids)]

          (0..vehicle.trips - 1).collect{ |index|
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle.id += "_trip_#{index}"
            new_vehicle
          }
        else
          vehicle
        end
      }.flatten
      vrp
    end
  end
end
