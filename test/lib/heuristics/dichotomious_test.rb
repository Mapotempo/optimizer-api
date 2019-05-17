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
require './test/test_helper'

class DichotomiousTest < Minitest::Test

  def test_dichotomious_approach
    vrp = FCT.load_vrp(self)
    t1 = Time.now
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    t2 = Time.now
    assert result

    # Check routes
    assert 16 > result[:routes].size, "Too many routes: #{result[:routes].size}"

    # Check activities
    assert 20 > result[:unassigned].size, "Too many unassigned services #{result[:unassigned].size}"

    # Check elapsed time
    assert t2 - t1 < 1500, "Too long elapsed time: #{t2 - t1}"
    assert t2 - t1 > 1000, "Too short elapsed time: #{t2 - t1}"
    assert result[:elapsed] / 1000 > 1000 && result[:elapsed] / 1000 < 1500, "Incorrect elapsed time: #{result[:elapsed]}"
  end
end
