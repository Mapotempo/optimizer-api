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
require './test/test_helper'

module Models
  class TimewindowTest < Minitest::Test
    def test_compatibility_between_timewindows
      tw1 = Models::Timewindow.new(start: 10, end: 20, day_index: 0)
      assert_raises RuntimeError do
        tw1.compatible_with?([0, 10], false)
      end
      assert tw1.compatible_with?(tw1, false)

      tw2 = Models::Timewindow.new(start: 10, end: 20, day_index: 1)
      assert tw1.compatible_with?(tw2, false)
      refute tw1.compatible_with?(tw2)
      refute tw1.compatible_with?(tw2, true) # lateness has no impact on days incompatibility

      # ignore days :
      tw2.start = 21
      tw2.end = 25
      refute tw1.compatible_with?(tw2, false)
      tw2.start = 5
      assert tw1.compatible_with?(tw2, false)
      tw2.end = 8
      refute tw1.compatible_with?(tw2, false)
    end
  end
end
