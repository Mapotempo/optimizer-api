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
require './wrappers/wrapper'

module Wrappers
  class Demo < Wrapper
    def initialize(hash = {})
      super(hash)
    end

    def build_route_activity(mission, type, activity)
      timewindows = []
      if activity.timewindows && !activity.timewindows.empty?
        timewindows = [{
          start: timewindows&.first&.start,
          end: timewindows&.first&.end,
        }]
      end
      {
        point_id: activity.point.id,
        travel_time: 0,
        travel_distance: 0,
        travel_start_time: 0,
        waiting_time: 0,
        arrival_time: 0,
        departure_time: 0,
        type: type,
        begin_time: 0,
        end_time: 0,
        detail: {
          lat: activity.point&.location&.lat,
          lon: activity.point&.location&.lon,
          setup_duration: activity.setup_duration,
          duration: activity.duration,
          timewindows: timewindows,
          quantities: mission.quantities,
        }
      }
    end

    def build_route_depot(point)
      point && {
          point_id: point.id,
          travel_time: 0,
          travel_distance: 0,
          travel_start_time: 0,
          type: 'depot',
          begin_time: 0,
          end_time: 0,
          detail: {
            lat: point.location&.lat,
            lon: point.location&.lon,
          }
      }
    end

    def solve(vrp, _job = nil, _thread_proc = nil, &_block)
      {
        cost: 0,
        cost_details: Models::CostDetails.new({}),
        solvers: [:demo],
        total_travel_distance: 0,
        total_travel_time: 0,
        total_waiting_time: 0,
        start_time: 0,
        end_time: 0,
        routes: vrp.vehicles.collect{ |vehicle|
          {
            vehicle_id: vehicle.id,
            activities: (
              [build_route_depot(vehicle.start_point)] +
              vrp.shipments.collect{ |shipment|
                [:pickup, :delivery].collect{ |a|
                  mission_hash = build_route_activity(shipment, a.to_s, shipment.send(a))
                  mission_hash[a.to_s + '_shipment_id'] = shipment.id if shipment.send(a)
                  mission_hash
                }.compact
              }.flatten +
              vrp.services.collect{ |service|
                mission_hash = build_route_activity(service, 'service', service.activity || service.activities.first)
                mission_hash[:service_id] = service.id
                mission_hash
              } +
              [build_route_depot(vehicle.end_point)]
            ).compact
          }
        } || [],
        unassigned: []
      }
    end
  end
end
