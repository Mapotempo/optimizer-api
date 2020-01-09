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
  class VehicleTest < Minitest::Test
    include Rack::Test::Methods

    def test_work_duration
      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)

      assert_nil vrp.vehicles.first.work_duration

      vrp.vehicles.first.sequence_timewindows = []
      assert_equal 2**32, vrp.vehicles.first.work_duration

      vrp.vehicles.first.timewindow = { start: 10 }
      assert_nil vrp.vehicles.first.work_duration

      vrp.vehicles.first.timewindow = { end: 10 }
      assert_nil vrp.vehicles.first.work_duration

      vrp.vehicles.first.timewindow = { start: 10, end: 20 }
      assert_equal 10, vrp.vehicles.first.work_duration
    end
  end
end
