# Copyright © Mapotempo, 2021
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
  class Solution < Base
    class Route < Base
      field :geometry

      has_many :stops, class_name: 'Models::Solution::Stop'
      has_many :initial_loads, class_name: 'Models::Solution::Load'

      belongs_to :cost_info, class_name: 'Models::Solution::CostInfo'
      belongs_to :info, class_name: 'Models::Solution::Route::Info'
      belongs_to :vehicle, class_name: 'Models::Vehicle', as_json: :id, vrp_result: :hide

      def initialize(options = {})
        options = { info: {}, cost_info: {} }.merge(options)
        super(options)
      end

      def vrp_result(options = {})
        hash = super(options)
        hash['activities'] = hash.delete('stops')
        hash['cost_details'] = hash.delete('cost_info')
        hash['detail'] = hash.delete('info')
        hash.merge!(info.vrp_result(options))
        hash.merge!(vehicle.vrp_result(options))
        hash.delete_if{ |_k, v| v.nil? }
        hash
      end

      def count_services
        stops.count(&:service_id)
      end

      def insert_stop(vrp, stop, index, idle_time = 0)
        stops.insert(index, stop)
        shift_route_times(idle_time + stop.activity.duration, index)
      end

      def shift_route_times(shift_amount, shift_start_index = 0)
        return if shift_amount == 0

        raise 'Cannot shift the route, there are not enough stops' if shift_start_index > self.stops.size

        self.info.start_time += shift_amount if shift_start_index == 0
        self.stops.each_with_index{ |stop, index|
          next if index <= shift_start_index

          stop.info.begin_time += shift_amount
          stop.info.end_time += shift_amount if stop.info.end_time
          stop.info.departure_time += shift_amount if stop.info.departure_time
          stop.info.waiting_time = [stop.info.waiting_time - shift_amount, 0].max
        }
        self.info.end_time += shift_amount if self.info.end_time
      end
    end
  end
end
