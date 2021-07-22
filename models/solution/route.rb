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
        hash['cost_details'] = hash['cost_info']
        hash.delete('cost_info')
        hash['activities'] = hash['steps']
        hash.merge!(info.vrp_result(options))
        hash['detail'] = hash['info']
        hash.delete('info')
        hash.delete('steps')
        hash.merge!(vehicle.vrp_result(options))
        hash.delete_if{ |_k, v| v.nil? }
        hash
      end

      def count_services
        steps.count(&:service_id)
      end
    end
  end
end
