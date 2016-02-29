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

    def solve?(param)
      true # No problemo, I will take care of
    end

    def solve(params, &block)
      {
        'costs': 0,
        'total_travel_distance': 0,
        'total_travel_time': 0,
        'total_waiting_time': 0,
        'start_time': 0,
        'end_time': 0,
        'routes': params['vehicles'] && params['vehicles'].collect{ |vehicle| {
          'vehicle_id': vehicle['vehicle_id'],
          'activities': params['shipments'] && params['shipments'].collect{ |shipment| {
            'point_id': shipment['pickup']['point_id'],
            'travel_distance': 0,
            'travel_start_time': 0,
            'waiting_duration': 0,
            'arrival_time': 0,
            'departure_time': 0,
            'pickup_shipments_id': shipment['shipment_id'],
            'delivery_shipments_id': shipment['shipment_id']
          }}
        }}
      }
    end
  end
end
