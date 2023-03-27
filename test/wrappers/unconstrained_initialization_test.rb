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
  def test_cvrptw
    unconstrained_initialization = OptimizerWrapper.config[:services][:unconstrained_initialization]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 2, 4, 4, 6, 7, 8, 12, 1],
          [1, 0, 1, 2, 4, 4, 6, 7, 8, 12, 1],
          [1, 1, 0, 2, 4, 4, 6, 7, 8, 12, 1],
          [1, 1, 2, 0, 4, 4, 6, 7, 8, 12, 1],
          [4, 4, 4, 4, 0, 4, 6, 7, 8, 12, 1],
          [4, 4, 4, 4, 3, 0, 6, 7, 8, 12, 1],
          [4, 4, 4, 4, 8, 4, 0, 7, 8, 12, 1],
          [4, 4, 4, 4, 8, 4, 6, 0, 8, 12, 1],
          [4, 4, 4, 4, 8, 4, 6, 7, 0, 12, 1],
          [4, 4, 4, 4, 8, 4, 6, 7, 0, 0, 1],
          [4, 4, 4, 4, 8, 4, 6, 7, 0, 12, 0]
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
      }, {
        id: 'point_3',
        matrix_index: 3
      }, {
        id: 'point_4',
        matrix_index: 4
      }, {
        id: 'point_5',
        matrix_index: 5
      }, {
        id: 'point_6',
        matrix_index: 6
      }, {
        id: 'point_7',
        matrix_index: 7
      }, {
        id: 'point_8',
        matrix_index: 8
      }, {
        id: 'point_9',
        matrix_index: 9
      }, {
        id: 'point_10',
        matrix_index: 10
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_fixed: 0,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        force_start: false,
        cost_distance_multiplier: 1,
        cost_time_multiplier: 1,
        cost_late_multiplier: 0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 2000,
          overload_multiplier: 0,
        }],
        timewindow: {
          start: 0,
          end: 100
        }
      }, {
        id: 'vehicle_1',
        cost_fixed: 0,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_distance_multiplier: 1,
        cost_time_multiplier: 1,
        cost_late_multiplier: 0,
        timewindow: {
          start: 0,
          end: 100
        },
        capacities: [{
          unit_id: 'unit_0',
          limit: 100,
          overload_multiplier: 0,
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 1,
          point_id: 'point_1',
          timewindows: [{
            start: 0,
            end: 80
          }],
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 80,
        }]
      }, {
        id: 'service_2',
        activity: {
          duration: 1,
          point_id: 'point_3',
          timewindows: [{
            start: 0,
            end: 80
          }],
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_4',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_4',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_7',
        activity: {
          point_id: 'point_5',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_8',
        activity: {
          point_id: 'point_5',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_9',
        activity: {
          point_id: 'point_6',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_10',
        activity: {
          point_id: 'point_6',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_11',
        activity: {
          point_id: 'point_7',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_12',
        activity: {
          point_id: 'point_7',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_13',
        activity: {
          point_id: 'point_8',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_14',
        activity: {
          point_id: 'point_8',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_15',
        activity: {
          point_id: 'point_8',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_16',
        activity: {
          point_id: 'point_8',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_17',
        activity: {
          point_id: 'point_8',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_18',
        activity: {
          point_id: 'point_9',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_19',
        activity: {
          point_id: 'point_9',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_20',
        activity: {
          point_id: 'point_10',
          timewindows: [{
            start: 0,
            end: 80
          }],

          duration: 2
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
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
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size + 2, solution.routes.first.stops.size
  end

  def test_cvrptw_2
    unconstrained_initialization = OptimizerWrapper.config[:services][:unconstrained_initialization]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 2],
          [1, 0, 1, 2],
          [1, 1, 0, 2],
          [1, 1, 2, 0]
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
      }, {
        id: 'point_3',
        matrix_index: 3
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
          point_id: 'point_3',
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

  def test_route_force_start
    ortools = OptimizerWrapper.config[:services][:unconstrained_initialization]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3, 9],
          [3, 0, 3, 8],
          [3, 3, 0, 8],
          [9, 9, 9, 0]
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
      }, {
        id: 'point_3',
        matrix_index: 3
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        force_start: true
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 0,
          timewindows: [{
            start: 9
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 0,
          timewindows: [{
            start: 18
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          duration: 0,
          timewindows: [{
            start: 18
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 2000
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 5, solution.routes.first.stops.size
    assert_equal 0, solution.routes.first.stops.first.info.begin_time
  end
end
