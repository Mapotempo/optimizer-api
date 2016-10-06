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


class Wrappers::OrtoolsTest < Minitest::Test

  def test_minimal_problem
    ortools = OptimizerWrapper::ORTOOLS
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
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

    def test_alternative_stop_conditions
    ortools = OptimizerWrapper::ORTOOLS
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
          iterations_without_improvment: 10,
          initial_time_out: 500,
          time_out_multiplier: 3
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_loop_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 655, 1948, 5231, 2971],
          [603, 0, 1692, 4977, 2715],
          [1861, 1636, 0, 6143, 1532],
          [5184, 4951, 6221, 0, 7244],
          [2982, 2758, 1652, 7264, 0],
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
      }, {
        id: 'point_3',
        matrix_index: 3
      }, {
        id: 'point_4',
        matrix_index: 4
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4'
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
  end

  def test_without_start_end_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 655, 1948, 5231, 2971],
          [603, 0, 1692, 4977, 2715],
          [1861, 1636, 0, 6143, 1532],
          [5184, 4951, 6221, 0, 7244],
          [2982, 2758, 1652, 7264, 0],
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
      }, {
        id: 'point_3',
        matrix_index: 3
      }, {
        id: 'point_4',
        matrix_index: 4
      }],
      vehicles: [{
        id: 'vehicle_0',
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
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4'
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size
  end

  def test_with_rest
    ortools = OptimizerWrapper::ORTOOLS
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 2
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0']
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
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + problem[:rests].size + 1, result[:routes][0][:activities].size
  end

  def test_negative_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
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
          point_id: 'point_1',
          timewindows: [{
            start: -3,
            end: 2
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 7
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_quantities
    ortools = OptimizerWrapper::ORTOOLS
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
      units: [{
        id: 'unit_0',
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 10,
          overload_multiplier: 0,
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 8,
        }]
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
  end

  def test_vehicles_timewindow_soft
    ortools = OptimizerWrapper::ORTOOLS
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
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 10,
          end: 12,
        },
        cost_late_multiplier: 1,
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        },
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_vehicles_timewindow_hard
    ortools = OptimizerWrapper::ORTOOLS
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
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 10,
          end: 12,
        },
        cost_late_multiplier: 0,
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        },
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
  end

  def test_multiples_vehicles
    ortools = OptimizerWrapper::ORTOOLS
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
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 10,
          end: 12,
        },
        cost_late_multiplier: 0,
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 10,
          end: 12,
        },
        cost_late_multiplier: 0,
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        },
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][0][:activities].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][1][:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_multiple_soft_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5, 5],
          [5, 0, 5],
          [5, 5, 0]
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
        late_multiplier: 1,
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }],
        }
      }, {
        id: 'service_2',
        late_multiplier: 1,
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          },{
            start: 10,
            end: 11
          }],
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_multiple_hard_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5, 5],
          [5, 0, 5],
          [5, 5, 0]
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
        late_multiplier: 0,
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }],
        }
      }, {
        id: 'service_2',
        late_multiplier: 0,
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          },{
            start: 10,
            end: 11
          }],
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size
  end
end
