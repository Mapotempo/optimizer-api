# Copyright © Mapotempo, 2019
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
require './test/test_helper'

module Models
  class VrpTest < Minitest::Test
    include Rack::Test::Methods

    def test_schedule_range_computation
      vrp = VRP.scheduling_seq_timewindows
      vrp = FCT.create(vrp)

      assert_equal 10, vrp.schedule_indices[1]

      vrp = VRP.scheduling_seq_timewindows
      vrp[:configuration][:schedule][:range_indices] = nil
      vrp[:configuration][:schedule][:range_date] = {
        start: Date.new(2017, 1, 15),
        end: Date.new(2017, 1, 27)
      }
      vrp = FCT.create(vrp)
      assert_equal 12, vrp.schedule_indices[1]
    end

    def test_visits_computation
      vrp = VRP.scheduling_seq_timewindows
      vrp = FCT.create(vrp)

      assert_equal vrp.services.size, vrp.visits

      vrp = VRP.scheduling_seq_timewindows
      vrp = FCT.create(vrp)
      vrp.services.each{ |service| service[:visits_number] *= 2 }

      assert_equal 2 * vrp.services.size, vrp.visits

      vrp = FCT.load_vrp(self, fixture_file: 'instance_clustered')
      assert_equal vrp.services.collect{ |s| s[:visits_number] }.sum, vrp.visits
    end
  end
end
