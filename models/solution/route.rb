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
      include SolutionRouteAsJson

      field :geometry

      has_many :steps, class_name: 'Models::Solution::Step'
      has_many :initial_loads, class_name: 'Models::Solution::Load'

      belongs_to :cost_info, class_name: 'Models::Solution::CostInfo'
      belongs_to :info, class_name: 'Models::Solution::Route::Info'
      belongs_to :vehicle, class_name: 'Models::Vehicle'

      def initialize(options = {})
        options = { info: {}, cost_info: {} }.merge(options)
        super(options)
      end

      def vrp_result(options = {})
        hash = super(options)
        hash.delete('vehicle')
        hash['activities'] = hash.delete('steps')
        hash['cost_details'] = hash.delete('cost_info')
        hash['detail'] = hash.delete('info')
        hash.merge!(info.vrp_result(options))
        hash.merge!(vehicle.vrp_result(options))
        hash.delete_if{ |_k, v| v.nil? }
        hash
      end

      def count_services
        steps.count(&:service_id)
      end

      def insert_step(vrp, step_object, index, idle_time = 0)
        steps.insert(index, step_object)
        shift_route_times(idle_time + step_object.activity.duration, index)
      end

      def shift_route_times(shift_amount, shift_start_index = 0)
        return if shift_amount == 0

        raise 'Cannot shift the route, there are not enough steps' if shift_start_index > self.steps.size

        self.info.start_time += shift_amount if shift_start_index == 0
        self.steps.each_with_index{ |step_object, index|
          next if index <= shift_start_index

          step_object.info.begin_time += shift_amount
          step_object.info.end_time += shift_amount if step_object.info.end_time
          step_object.info.departure_time += shift_amount if step_object.info.departure_time
          step_object.info.waiting_time = [step_object.info.waiting_time - shift_amount, 0].max
        }
        self.info.end_time += shift_amount if self.info.end_time
      end
    end
  end
end
