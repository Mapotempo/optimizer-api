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
require './test/test_helper'

class Wrappers::UnconstraintedInitializationTest < Minitest::Test
  focus
  def test_minimal_problem
    ortools = OptimizerWrapper.config[:services][:unconstrainted_initialization]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 2000,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end
end
