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

class Wrappers::UnconstrainedInitializationTest < Minitest::Test
  def test_minimal_problem
    unconstrained_initialization = OptimizerWrapper.config[:services][:unconstrained_initialization]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
        id: 'unit_0',
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
        cost_fixed: 0,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_distance_multiplier: 1,
        cost_time_multiplier: 1,
        timewindow: {
          start: 0,
          end: 10
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 0,
            end: 8
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 0,
            end: 8
          }]
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 0,
            end: 8
          }]
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 0,
            end: 8
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 2000,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = unconstrained_initialization.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 2, solution.routes.first.stops.size
  end
end
