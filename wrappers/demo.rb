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
    def initialize(cache, hash = {})
      super(cache, hash)
    end

    def solve(vrp, job = nil, thread_proc = nil, &block)
      {
        cost: 0,
        solvers: [:demo],
        total_travel_distance: 0,
        total_travel_time: 0,
        total_waiting_time: 0,
        start_time: 0,
        end_time: 0,
        routes: vrp.vehicles && vrp.vehicles.collect{ |vehicle| {
          vehicle_id: vehicle.id,
          activities: ([vehicle.start_point && {
              point_id: vehicle.start_point.id,
              travel_distance: 0,
              travel_start_time: 0
          }] + (vrp.shipments && vrp.shipments.collect{ |shipment|
            [:pickup, :delivery].collect{ |a|
              {
                point_id: shipment.send(a).point.id,
                travel_distance: 0,
                travel_start_time: 0,
                waiting_duration: 0,
                arrival_time: 0,
                departure_time: 0,
                a.to_s + '_shipment_id' => shipment.id
              } if shipment.send(a)
            }.compact
          }.flatten) + (vrp.services && vrp.services.collect{ |service|
            {
              point_id: service.activity.point.id,
              travel_distance: 0,
              travel_start_time: 0,
              waiting_duration: 0,
              arrival_time: 0,
              departure_time: 0,
              service_id: service.id
            }
          }) + [vehicle.end_point && {
              point_id: vehicle.end_point.id,
              travel_distance: 0,
              travel_start_time: 0
          }]).compact
        }} || [],
        unassigned: []
      }
    end
  end
end
