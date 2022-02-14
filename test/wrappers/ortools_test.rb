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
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end

  def test_group_overall_duration_first_vehicle
    skip 'Requires an entire review of the :overall_duration feature'
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
        matrix_id: 'matrix_0',
        cost_fixed: 20
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
      }, {
        id: 'vehicle_2',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 1,
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          duration: 1,
          point_id: 'point_2'
        }
      }],
      relations: [{
        type: :vehicle_group_duration,
        linked_vehicle_ids: ['vehicle_0', 'vehicle_2'],
        lapse: 2
      }],
      configuration: {
        restitution: {
          intermediate_solutions: false,
        },
        resolution: {
          duration: 100,
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 3, solutions[0].routes[1].stops.size
    # TODO : providing lapse = 0 should unable all vehicles
  end

  def test_group_number
    problem = VRP.lat_lon_capacitated
    problem[:vehicles] << problem[:vehicles][0].dup
    problem[:vehicles][1][:id] = 'vehicle_1'
    problem[:vehicles][1][:capacities][0][:limit] = 2
    problem[:vehicles] << problem[:vehicles][0].dup
    problem[:vehicles][2][:id] = 'vehicle_2'

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert(solutions[0].routes.all?{ |r| r.stops.any?{ |a| a.type == :service } })

    problem[:relations] = [{
      type: :vehicle_group_number,
      linked_vehicle_ids: ['vehicle_0', 'vehicle_1', 'vehicle_2'],
      lapses: [2]
    }]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 2, (solutions[0].routes.count{ |r| r.stops.any?{ |a| a.type == :service } })

    # extreme case : lapse is 0
    problem[:relations].first[:lapses] = [0]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_empty(solutions[0].routes.select{ |r| r.stops.any?{ |a| a.type == :service } })
  end

  def test_periodic_overall_duration
    skip 'Requires an entire review of the :overall_duration feature'
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
        id: 'depot',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'voiture4',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        }
      }, {
        id: 'voiture3',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        overall_duration: 3,
        timewindow: {
          start: 0
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 1,
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          duration: 1,
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 1000,
        },
        schedule:
            {
                range_indices:
                {
                    start: 0,
                    end: 2
                }
            },
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 0, solutions[0].unassigned_stops.size
    assert_equal solutions[0].routes.first.stops.size, solutions[0].routes[1].stops.size
  end

  def test_periodic_with_group_duration
    skip 'Requires an entire review of the :overall_duration feature'
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
        id: 'depot',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_1',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        }
      }, {
        id: 'vehicle_3',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 1,
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          duration: 1,
          point_id: 'point_2'
        }
      }],
      relations: [{
        type: :vehicle_group_duration,
        linked_vehicle_ids: ['vehicle_1', 'vehicle_2'],
        lapse: 1
      }],
      configuration: {
        resolution: {
          duration: 1000,
        },
        schedule:
            {
                range_indices:
                {
                    start: 0,
                    end: 2
                }
            },
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 0, solutions[0].unassigned_stops.size
    assert_equal 3, solutions[0].routes[2].stops.size
  end

  def test_overall_duration_with_rest_no_vehicle_tw
    skip 'Requires an entire review of the :overall_duration feature'
    # conflict with rests
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
        id: 'depot',
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
        duration: 1,
        timewindows: [{
          day_index: 0
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        overall_duration: 1,
        timewindow: {
          start: 1,
          end: 10
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        overall_duration: 1,
        timewindow: {
          start: 1,
          end: 10
        }
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
          duration: 20,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 0
          }
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 3, solutions[0].routes.find{ |route| route[:vehicle_id] == 'vehicle_1_0' }.stops.size
    assert_equal 2, solutions[0].routes.find{ |route| route[:vehicle_id] == 'vehicle_0_0' }.stops.size
    assert_equal 0, solutions[0].unassigned_stops.size
  end

  def test_duration_adjusted_by_presence_of_rest
    # Rest duration is added to vehicle duration
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
          start: 0,
          end: 1
        }],
        duration: 1,
      }],
      vehicles: [{
        id: 'vehicle_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        duration: 1
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 200,
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, solutions[0].unassigned_stops.size
  end

  def test_overall_duration_with_rest
    skip 'Requires an entire review of the :overall_duration feature'
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
        id: 'depot',
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
        duration: 1,
        timewindows: [{
          start: 1,
          end: 1
          }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        cost_fixed: 20,
        timewindow: {
          start: 0
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        overall_duration: 1,
        sequence_timewindows: [{
          start: 0,
          end: 5
        }]
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
          duration: 20,
        },
        schedule:
            {
                range_indices:
                {
                    start: 0,
                    end: 1
                }
            }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 3, solutions[0].routes.first.stops.size
  end

  def test_overall_duration_on_months
    skip 'Requires an entire review of the :overall_duration feature'
    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_months,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 100,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
    }

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([4, 1], solutions[0].routes.collect{ |r| r.stops.size })

    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_months,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 6,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([3, 2], solutions[0].routes.collect{ |r| r.stops.size })
    # TODO : providing lapse = 0 should unable all vehicles
  end

  def test_overall_duration_on_weeks
    skip 'Requires an entire review of the :overall_duration feature'
    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_weeks,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 100,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_indices: { start: 6, end: 7 }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([4, 1], solutions[0].routes.collect{ |r| r.stops.size })

    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_weeks,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 6,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_indices: { start: 6, end: 7 }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([3, 2], solutions[0].routes.collect{ |r| r.stops.size })
    # TODO : providing lapse = 0 should unable all vehicles
  end

  def test_overall_duration_on_weeks_date
    skip 'Requires an entire review of the :overall_duration feature'
    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_weeks,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 100,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 5), end: Date.new(2020, 1, 6) }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([4, 1], solutions[0].routes.collect{ |r| r.stops.size })

    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration_on_weeks,
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 6,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 5), end: Date.new(2020, 1, 6) }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal([3, 2], solutions[0].routes.collect{ |r| r.stops.size })
  end

  def test_alternative_stop_conditions
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          minimum_duration: 500,
          time_out_multiplier: 3
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end

  def test_loop_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 2, solution.routes.first.stops.size
  end

  def test_without_start_end_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size
  end

  def test_with_rest
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + problem[:rests].size + 1, solution.routes.first.stops.size
  end

  def test_with_rest_multiple_reference
    ortools = OptimizerWrapper.config[:services][:ortools]
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
      }, {
        id: 'vehicle_1',
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size + problem[:vehicles].sum{ |vehicle| vehicle[:rest_ids].size } + 2,
                 (solution.routes.sum{ |route| route.stops.size })
  end

  def test_negative_time_windows_problem
    skip 'Negative timewindows is not supported, or-tools ignores the negative part completely. '\
         'A preprocessing routine is needed to correctly handle negative timewindows -- i.e., '\
         'Adding the absolute value of the most negative TW to all other TWs so that everything '\
         'shifted into positive time horizon and then a postprocessing is needed to correct the '\
         'time values (begin_time, end_time, etc) of the activities of the solution.'
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end

  def test_quantities
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1 - 1, solution.routes.first.stops.size
    assert_equal 1, solution.unassigned_stops.size
  end

  def test_vehicles_timewindow_soft
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 2, solution.routes.first.stops.size
    assert_equal 0, solution.unassigned_stops.size
  end

  def test_vehicles_timewindow_hard
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 2 - 1, solution.routes.first.stops.size
    assert_equal 1, solution.unassigned_stops.size
  end

  def test_multiples_vehicles
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size + 2 - 1, solution.routes.first.stops.size
    assert_equal problem[:services].size + 2 - 1, solution.routes[1].stops.size
    assert_equal 0, solution.unassigned_stops.size
  end

  def test_double_soft_time_windows_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }],
          late_multiplier: 1,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          }, {
            maximum_lateness: 10,
            start: 10,
            end: 11
          }],
          late_multiplier: 1,
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end

  def test_triple_soft_time_windows_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }, {
            start: 11,
            end: 12
          }],
          late_multiplier: 1,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          }, {
            start: 10,
            end: 11
          }, {
            start: 15,
            end: 16
          }],
          late_multiplier: 1,
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size
  end

  def test_double_hard_time_windows_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          }, {
            start: 10,
            end: 11
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size
  end

  def test_triple_hard_time_windows_problem
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 9, 9],
          [9, 0, 9],
          [9, 9, 0]
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
            start: 3,
            end: 4
          }, {
            start: 7,
            end: 8
          }, {
            start: 11,
            end: 12
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 5,
            end: 6
          }, {
            start: 10,
            end: 11
          }, {
            start: 15,
            end: 16
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size
  end

  def test_nearby_specific_ordder
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 6, 10, 127, 44, 36, 42, 219, 219],
          [64, 0, 4, 122, 38, 31, 36, 214, 214],
          [60, 44, 0, 117, 34, 27, 32, 209, 209],
          [68, 53, 8, 0, 42, 35, 40, 218, 218],
          [53, 38, 42, 111, 0, 20, 25, 203, 203],
          [61, 18, 22, 118, 7, 0, 5, 210, 210],
          [77, 12, 17, 134, 50, 43, 0, 226, 226],
          [180, 184, 188, 244, 173, 166, 171, 0, 0],
          [180, 184, 188, 244, 173, 166, 171, 0, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_7',
        end_point_id: 'point_8',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0',
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4',
          late_multiplier: 0,
        }
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5',
          late_multiplier: 0,
        }
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_6',
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
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
    assert solution.routes.first.stops[1..-2].collect.with_index{ |activity, index|
      activity.service_id == "service_#{index}"
    }.all?
    assert_equal problem[:services].size + 2, solution.routes.first.stops.size
  end

  def test_distance_matrix
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        distance: [
          [0, 3, 3, 3],
          [3, 0, 3, 3],
          [3, 3, 0, 3],
          [3, 3, 3, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
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
  end

  def test_max_ride_distance
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        distance: [
          [0, 1000, 3, 3],
          [1000, 0, 1000, 1000],
          [3, 1000, 0, 3],
          [3, 1000, 3, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        maximum_ride_distance: 4
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.unassigned_stops.size
  end

  def test_two_vehicles_one_matrix_each
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3, 3000],
          [3, 0, 3, 3000],
          [3, 3, 0, 3000],
          [3000, 3000, 3000, 0]
        ]
      }, {
        id: 'matrix_1',
        time: [
          [0, 1, 1, 1000],
          [1, 0, 1, 1000],
          [1, 1, 0, 1000],
          [1000, 1000, 1000, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_1'
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 2980,
            end: 3020
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          timewindows: [{
            start: 2980,
            end: 3020
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          timewindows: [{
            start: 2980,
            end: 3020
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
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
    assert_equal 4, solution.routes.first.stops.size
    assert_equal 3, solution.routes[1].stops.size
  end

  def test_skills
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3, 3],
          [3, 0, 3, 3],
          [3, 3, 0, 3],
          [3, 3, 3, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        skills: [['frozen']]
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        skills: [['cool']]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        },
        skills: ['frozen']
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        },
        skills: ['cool']
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        skills: ['frozen']
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        skills: ['cool']
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
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
    assert_equal 4, solution.routes.first.stops.size
    assert_equal 4, solution.routes[1].stops.size
  end

  def test_setup_duration
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5],
          [5, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 3,
          end: 16
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 3,
          end: 16
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          setup_duration: 2,
          duration: 1,
          point_id: 'point_1',
          timewindows: [{
            start: 10,
            end: 15
          }],
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          setup_duration: 2,
          duration: 1,
          point_id: 'point_1',
          timewindows: [{
            start: 10,
            end: 15
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size - 1
    assert_equal problem[:services].size, solution.routes[1].stops.size - 1
  end

  def test_route_duration
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3, 3],
          [3, 0, 3, 3],
          [3, 3, 0, 3],
          [3, 3, 3, 0]
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
        duration: 9
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5,
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          duration: 5,
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.unassigned_stops.size
    assert_equal 3, solution.routes.first.stops.size
  end

  def test_route_force_start
    ortools = OptimizerWrapper.config[:services][:ortools]
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
          duration: 100
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
    assert_equal 'service_0', solution.routes.first.stops[1].service_id
  end

  def test_route_shift_preference_to_force_start
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        shift_preference: 'force_start',
        timewindow: {
          start: 0
        }
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
          duration: 100
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
    assert_equal 'service_0', solution.routes.first.stops[1].service_id
  end

  def test_route_shift_preference_to_force_end
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        shift_preference: 'force_end'
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
          duration: 100
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
    assert_equal 18, solution.routes.first.stops[1].info.begin_time
  end

  def test_route_shift_preference_to_minimize_span
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        shift_preference: 'force_end'
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
          duration: 100
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
    assert_equal 18, solution.routes.first.stops[1].info.begin_time
  end

  def test_vehicle_limit
    ortools = OptimizerWrapper.config[:services][:ortools]
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
        matrix_id: 'matrix_0',
        timewindow: {
          end: 1
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          end: 1
        }
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
          duration: 20,
          vehicle_limit: 1
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size + 1,
                 solution.routes.first.stops.size + solution.routes[1].stops.size
  end

  def test_minimum_day_lapse
    # extreme case : lapse of 0
    problem = VRP.basic
    problem[:vehicles].each{ |v| v.delete(:start_point_id) }
    problem[:relations] = [{
      type: :minimum_day_lapse,
      lapses: [0],
      linked_ids: ['service_1', 'service_2', 'service_3']
    }]
    problem[:configuration][:schedule] = { range_indices: { start: 0, end: 4 }}

    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},
                                             TestHelper.create(problem), nil)
    assert_equal 5, solutions[0].routes.size
    assert_empty solutions[0].unassigned_stops
    assert_equal [0, 1, 2],
                 solutions[0].routes.collect{ |r| r.stops.any? ? r.vehicle.global_day_index : nil }.compact

    # standard case
    problem[:relations].first[:lapses] = [2]
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},
                                             TestHelper.create(problem), nil)
    assert_equal 5, solutions[0].routes.size
    # There should be a lapse of 2 between each visits :
    assert_equal [0, 2, 4],
                 solutions[0].routes.collect{ |r| r.stops.any? ? r.vehicle.global_day_index : nil }.compact
  end

  def test_maximum_day_lapse
    # extreme case : lapse of 0
    problem = VRP.basic
    relation = [{
      type: :maximum_day_lapse,
      lapses: [0],
      linked_ids: ['service_1', 'service_3']
    }]
    problem[:relations] = relation
    problem[:configuration][:schedule] = { range_indices: { start: 0, end: 4 }}

    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},
                                             TestHelper.create(problem), nil)
    assert_equal 5, solutions[0].routes.size
    route_with_service = solutions[0].routes.find{ |r| r.stops.any?{ |a| a.service_id.to_s == 'service_1_1_1' } }
    # service_1 and service_3 should be in the same route because lapse is 0:
    assert(route_with_service.stops.any?{ |a| a.service_id.to_s == 'service_3_1_1' })

    # add quantities to prevent from assigning all services at the same day :
    problem[:units] = [{ id: 'visit' }]
    problem[:vehicles].each{ |v|
      v.delete(:start_point_id)
      v[:capacities] = [{ unit_id: 'visit', limit: 1 }]
    }
    problem[:services].each{ |s|
      s[:quantities] = [{ unit_id: 'visit', value: 1 }]
    }
    problem.delete(:relations)
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal [['service_1_1_1'], ['service_2_1_1'], ['service_3_1_1'], [], []],
                 (solutions[0].routes.collect{ |r| r.stops.collect{ |a| a.service_id } })

    problem[:relations] = relation
    problem[:relations].first[:lapses] = [1]
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal [['service_1_1_1'], ['service_3_1_1'], ['service_2_1_1'], [], []],
                 (solutions[0].routes.collect{ |r| r.stops.collect{ |a| a.service_id } })
  end

  def test_counting_quantities
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
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
      }],
      units: [{
        id: 'unit_0',
        counting: true
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 2
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'unit_0',
          setup_value: 1,
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'unit_0',
          setup_value: 1,
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2',
        },
        quantities: [{
          unit_id: 'unit_0',
          setup_value: 1,
        }]
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_3',
        },
        quantities: [{
          unit_id: 'unit_0',
          setup_value: 1,
        }]
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size - 1, solution.routes.first.stops.count(&:service_id)
    assert_equal 1, solution.unassigned_stops.size
  end

  def test_shipments
    ortools = OptimizerWrapper.config[:services][:ortools]
    vrp = TestHelper.create(VRP.pud)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } <
           solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } <
           solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 6, solution.routes.first.stops.size
  end

  def test_shipments_quantities
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3],
          [3, 0, 3],
          [3, 3, 0]
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
        cost_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 2
        }]
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2
        }]
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal(solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } + 1,
                 solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' })
    assert_equal(solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } + 1,
                 solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' })
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 6, solution.routes.first.stops.size
  end

  def test_shipments_with_multiple_timewindows_and_lateness
    # OR-Tools will generate separate nodes for disjoint timewindows with lateness
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = VRP.pud
    keys = [:pickup, :delivery]
    problem[:shipments].each{ |shipment|
      keys.each{ |key|
        shipment[key][:timewindows] = [
          { start: 0, end: 14, maximum_lateness: 15 },
          { start: 17, end: 29, maximum_lateness: 15}
        ]
        shipment[key][:late_multiplier] = 0.3
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert_equal 0, solution.cost_info.lateness
    assert solution.routes[0].stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } <
           solution.routes[0].stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert solution.routes[0].stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } <
           solution.routes[0].stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 6, solution.routes[0].stops.size
  end

  def test_shipments_inroute_duration
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = VRP.pud
    problem[:vehicles].each{ |v| v[:timewindow] = { start: 10, end: 10000 } }
    problem[:shipments].each{ |s| s[:maximum_inroute_duration] = 12 }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal(
      solution.routes.first.stops.find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } + 1,
      solution.routes.first.stops.find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    )
    assert_equal(
      solution.routes.first.stops.find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } + 1,
      solution.routes.first.stops.find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    )
    assert_operator(
      solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' },
      :<,
      solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    )
    assert_operator(
      solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' },
      :<,
      solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    )
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 6, solution.routes.first.stops.size
  end

  def test_mixed_shipments_and_services
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
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
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'unit_0',
          setup_value: 1,
        }]
      }],
      shipments: [{
        id: 'shipment_1',
        pickup: {
          point_id: 'point_2',
          duration: 1,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_3',
          duration: 1,
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } <
           solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 5, solution.routes.first.stops.size
  end

  def test_shipments_distance
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = VRP.pud
    problem[:matrices].first[:distance] = problem[:matrices].first[:time]
    problem[:matrices].first.delete(:time)
    problem[:vehicles].each{ |v|
      v[:cost_time_multiplier] = 0
      v[:cost_distance_multiplier] = 1
    }
    problem[:shipments].find{ |s| s[:id] == 'shipment_1' }[:pickup][:point_id] = 'point_3'
    problem[:shipments].find{ |s| s[:id] == 'shipment_1' }[:delivery][:point_id] = 'point_1'
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } <
           solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert solution.routes.first.stops.index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } <
           solution.routes.first.stops.index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 6, solution.routes.first.stops.size
  end

  def test_maximum_duration_lapse_shipments
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = VRP.pud
    problem[:shipments].each{ |s| s[:pickup][:timewindows] = [{ start: 0, end: 100 }] }
    problem[:shipments][0][:delivery][:timewindows] = [{ start: 300, end: 400 }]
    problem[:shipments][1][:delivery][:timewindows] = [{ start: 100, end: 200 }]
    problem[:relations] = [{
      type: :maximum_duration_lapse,
      lapses: [100],
      linked_ids: ['shipment_0_pickup', 'shipment_0_delivery']
    }, {
      type: :maximum_duration_lapse,
      lapses: [100],
      linked_ids: ['shipment_1_pickup', 'shipment_1_delivery']
    }]
    solution = ortools.solve(TestHelper.create(problem), 'test')
    pickup_index = solution.routes.first.stops.index{ |activity| activity.pickup_shipment_id == 'shipment_1' }
    delivery_index = solution.routes.first.stops.index{ |activity| activity.delivery_shipment_id == 'shipment_1' }
    assert_operator pickup_index, :<, delivery_index
    assert_operator solution.routes.first.stops[pickup_index].info.end_time + 100,
                    :>=,
                    solution.routes.first.stops[delivery_index].info.begin_time
    assert_equal 2, solution.unassigned_stops.size

    problem[:relations].each{ |r|
      r[:lapses] = [0] if r[:lapses]
    }
    solution = ortools.solve(TestHelper.create(problem), 'test')
    # pickup and delivery at not at same location so it is impossible to assign with lapse 0
    # we could use direct shipment instead
    assert_equal 4, solution.unassigned_stops.size
  end

  def test_value_matrix
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
        ],
        value: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
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
      }],
      units: [{
        id: 'unit_0',
        counting: true
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        value_matrix_id: 'matrix_0',
        cost_time_multiplier: 1,
        cost_value_multiplier: 1
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        value_matrix_id: 'matrix_0',
        cost_time_multiplier: 10,
        cost_value_multiplier: 0.5
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2',
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_3',
          additional_value: 90
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal 4, solution.routes.first.stops.size
    assert_equal 2, solution.routes[1].stops.size
  end

  def test_sequence
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 2, 5],
          [1, 0, 2, 10],
          [1, 2, 0, 5],
          [1, 3, 8, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0'
      }, {
        id: 'vehicle_1',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        skills: [['skill1']]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        skills: ['skill1']
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
      }],
      relations: [{
        id: 'sequence_1',
        type: :sequence,
        linked_ids: ['service_1', 'service_3', 'service_2']
      }],
      configuration: {
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal 2, solution.routes.first.stops.size
    assert_equal 5, solution.routes[1].stops.size
  end

  def test_unreachable_destination
    skip "This test fails. In fact, the issue is not in the test. More specificaly, currently
          if a point is unreachable, router returns the distance result using an 'auxiliary'
          point which is the closest reachable point from the unreachable point.
          However, if the distance between this 'auxiliary' point and our
          real point is too much, we should raise a flag (or depending on the distance,
          mark point unreachable and replace the data of the point with 'nil').
          That is, until we filter the router distance restuls this test will keep failing."
    problem = {
      configuration: {
        resolution: {
              duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      },
      points: [{
          id: 'point_0',
          location: {
              lat: 43.8,
              lon: 5.8
          }
      }, {
          id: 'point_1',
          location: {
              lat: -43.8,
              lon: 5.8
          }
      }, {
          id: 'point_2',
          location: {
              lat: 44.8,
              lon: 4.8
          }
      }, {
          id: 'agent_home',
          location: {
              lat: 44.0,
              lon: 5.1
          }
      }],
      vehicles: [{
          id: 'vehicle_1',
          cost_time_multiplier: 1.0,
          cost_waiting_time_multiplier: 1.0,
          cost_distance_multiplier: 1.0,
          router_mode: 'car',
          router_dimension: 'time',
          speed_multiplier: 1.0,
          start_point_id: 'agent_home',
          end_point_id: 'agent_home'
      }],
      services: [{
          id: 'service_0',
          activity: {
            duration: 100.0,
            point_id: 'point_0'
          }
      }, {
          id: 'service_1',
          activity: {
              duration: 100.0,
              point_id: 'point_1'
          }
      }, {
          id: 'service_2',
          activity: {
              duration: 100.0,
              point_id: 'point_2'
          }
      }]
    }
    vrp = TestHelper.create(problem)
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 4, solutions[0].routes.first.stops.size
    assert solutions[0][:cost] < 2**32
  end

  def test_initial_load_output
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [
        {
          id: 'kg',
          label: 'Kg'
        },
        {
          id: 'l',
          label: 'L'
        }
      ],
      points: [
        {
          id: 'point_0',
          matrix_index: 0
        },
        {
          id: 'point_1',
          matrix_index: 1
        },
        {
          id: 'point_2',
          matrix_index: 2
        }
      ],
      vehicles: [
        {
          id: 'vehicle_0',
          start_point_id: 'point_0',
          matrix_id: 'matrix_0',
          capacities: [
              {
              unit_id: 'kg',
              limit: 5
            }
          ]
        }
      ],
      services: [
        {
          id: 'service_1',
          activity: {
            point_id: 'point_1'
          },
          quantities: [
            {
              unit_id: 'kg',
              value: -5
            }
          ]
        },
        {
          id: 'service_2',
          activity: {
            point_id: 'point_2'
          },
          quantities: [
            {
              unit_id: 'kg',
              value: 4
            },
            {
              unit_id: 'l',
              value: -1
            }
          ]
        }
      ],
      configuration: {
        resolution: {
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size + 1, solution.routes.first.stops.size

    case solution.routes.first.stops[1].service_id
    when 'service_1'
      assert_equal 5, solution.routes.first.initial_loads.first.current
    when 'service_2'
      assert_equal 1, solution.routes.first.initial_loads.first.current
    else
      flunk 'This is not possible!'
    end
  end

  def test_force_first
    problem = VRP.basic
    problem[:vehicles] << problem[:vehicles][0].dup
    problem[:vehicles][1][:id] += '_copy'
    problem[:vehicles].each{ |v| v[:start_point_id] = nil }
    problem[:relations] = [{
      id: 'force_first',
      type: :force_first,
      linked_ids: ['service_1', 'service_3']
    }]

    vrp = TestHelper.create(problem)
    assert_equal :always_first, vrp.services[0].activity.position
    assert_equal :neutral, vrp.services[1].activity.position
    assert_equal :always_first, vrp.services[2].activity.position
    solution = OptimizerWrapper.config[:services][:ortools].solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size + solution.routes[1].stops.size
    assert(solution.routes.any?{ |route| route.stops.first.service_id == 'service_1' })
    assert(solution.routes.any?{ |route| route.stops.first.service_id == 'service_3' })
  end

  def test_force_end
    problem = VRP.basic
    problem[:vehicles] << problem[:vehicles][0].dup
    problem[:vehicles][1][:id] += '_copy'
    problem[:vehicles].each{ |v| v[:start_point_id] = nil }
    problem[:relations] = [{
      id: 'force_end',
      type: :force_end,
      linked_ids: ['service_1']
    }, {
      id: 'force_end2',
      type: :force_end,
      linked_ids: ['service_3']
    }]

    vrp = TestHelper.create(problem)
    assert_equal :always_last, vrp.services[0].activity.position
    assert_equal :neutral, vrp.services[1].activity.position
    assert_equal :always_last, vrp.services[2].activity.position
    solution = OptimizerWrapper.config[:services][:ortools].solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size + solution.routes[1].stops.size
    assert(solution.routes.any?{ |route| route.stops.last.service_id == 'service_1' })
    assert(solution.routes.any?{ |route| route.stops.last.service_id == 'service_3' })
  end

  def test_never_first
    problem = VRP.basic
    problem[:vehicles] << problem[:vehicles][0].dup
    problem[:vehicles][1][:id] += '_copy'
    problem[:vehicles].each{ |v| v[:start_point_id] = nil }
    problem[:relations] = [{
      id: 'never_first',
      type: :never_first,
      linked_ids: ['service_1', 'service_3']
    }]

    vrp = TestHelper.create(problem)
    assert_equal :never_first, vrp.services[0].activity.position
    assert_equal :never_first, vrp.services[2].activity.position
    solution = OptimizerWrapper.config[:services][:ortools].solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal problem[:services].size, [solution.routes.first.stops.size, solution.routes[1].stops.size].max
    assert_equal 'service_2', solution.routes.first.stops.first.service_id || solution.routes[1].stops.first.service_id
  end

  def test_never_last
    problem = VRP.basic
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    assert_equal 'service_3', solution.routes.first.stops.last.service_id

    problem[:services].last[:activity][:position] = :never_last
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    assert_operator 'service_3', :!=, solution.routes.first.stops.last.service_id
  end

  def test_always_middle
    problem = VRP.basic
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    assert_equal 'service_3', solution.routes.first.stops.last.service_id

    problem[:services].last[:activity][:position] = :always_middle
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    assert_equal 'service_3', solution.routes.first.stops[2].service_id
  end

  def test_never_middle
    problem = VRP.basic
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    assert_equal 'service_2', solution.routes.first.stops[2].service_id

    problem[:services][1][:activity][:position] = :never_middle
    solution = OptimizerWrapper.config[:services][:ortools].solve(TestHelper.create(problem), 'test')
    refute_equal('service_2', solution.routes.first.stops[2].service_id)
  end

  def test_fill_quantities
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      units: [{
        id: 'kg',
        label: 'kg'
      }],
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
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'kg',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'kg',
          fill: true
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'kg',
          value: -5
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'kg',
          value: -5
        }]
      }],
      relations: [{
        id: 'never_first',
        type: :never_first,
        linked_ids: ['service_1', 'service_3']
      }],
      configuration: {
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal problem[:services].size, solution.routes.first.stops.size
    assert solution.routes.first.stops.first.service_id == 'service_2' || solution.routes.first.stops.last.service_id == 'service_2'
    assert solution.routes.first.stops.first.service_id == 'service_3' || solution.routes.first.stops.last.service_id == 'service_3'
    assert_equal 'service_1', solution.routes.first.stops[1].service_id
    assert_equal 5, solution.routes.first.initial_loads.first.current
  end

  def test_max_ride_time
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5, 11],
          [5, 0, 11],
          [11, 11, 0]
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
        matrix_id: 'matrix_0',
        maximum_ride_time: 10
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.routes.size
    assert_equal problem[:services].size, solution.routes.first.stops.size
    assert_equal 1, solution.unassigned_stops.size
  end

  def test_vehicle_max_distance
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        distance: [
          [0, 11, 9],
          [11, 0, 6],
          [9, 6, 0]
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
        matrix_id: 'matrix_0',
        cost_distance_multiplier: 1,
        distance: 10
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_distance_multiplier: 1,
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal problem[:services].size + 1, solution.routes[1].stops.size
    assert_equal 0, solution.unassigned_stops.size
  end

  def test_vehicle_max_distance_one_per_vehicle
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        distance: [
          [0, 5, 11],
          [5, 0, 11],
          [11, 11, 0]
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
        matrix_id: 'matrix_0',
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        distance: 11
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        distance: 10
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert_equal solution.routes.first.stops.size, solution.routes[1].stops.size
  end

  def test_max_ride_time_never_from_or_to_depot
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5, 11],
          [5, 0, 11],
          [11, 11, 0]
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
        cost_fixed: 10,
        matrix_id: 'matrix_0',
        maximum_ride_time: 10
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        cost_fixed: 10,
        matrix_id: 'matrix_0',
        maximum_ride_time: 10
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal 52, solution.cost
    assert_equal 3, solution.routes.first.stops.size
    assert_equal 3, solution.routes[1].stops.size
    assert_equal 0, solution.unassigned_stops.size
  end

  def test_initial_routes
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0'
      }, {
        id: 'vehicle_1',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        skills: [['skill1']]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        skills: ['skill1']
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
      }],
      routes: [
        {
          vehicle_id: 'vehicle_0',
          mission_ids: ['service_2', 'service_3']
        },
        {
          vehicle_id: 'vehicle_1',
          mission_ids: ['service_1']
        }
      ],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    # Initial routes are soft assignment
    assert_equal 2, solution.routes.size
    assert_equal 2, solution.routes.first.stops.size
    assert_equal 5, solution.routes[1].stops.size
  end

  def test_pud_initial_routes
    ortools = OptimizerWrapper.config[:services][:ortools]
    vrp = TestHelper.load_vrp(self)
    expecting = vrp[:routes].collect{ |route| route[:mission_ids].size }

    OptimizerWrapper.config[:services][:ortools].stub(
      :run_ortools,
      lambda { |problem, _, _|
        # check no service has been filtered :
        assert_equal expecting, (problem.routes.collect{ |r| r.service_ids.size })

        'Job killed' # Return "Job killed" to stop gracefully
      }
    ) do
      ortools.solve(vrp, 'test')
    end
  end

  def test_alternative_service
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = VRP.basic
    problem[:matrices][0][:time] = [
      [0, 1, 1000],
      [1, 0, 1000],
      [1000, 1000, 0],
    ]
    problem[:points] = problem[:points][0..-2]
    problem[:vehicles][0][:cost_time_multiplier] = 1
    problem[:vehicles][0][:end_point_id] = 'point_0' # start/end = point_0
    problem[:services] = [{
      id: 'service_1',
      activities: [{
        point_id: 'point_1'
      }, {
        point_id: 'point_2'
      }]
    }]
    problem[:configuration][:resolution][:duration] = 20

    solution = ortools.solve(TestHelper.create(problem), 'test')
    assert solution
    assert_equal [], solution.unassigned_stops
    assert_equal 0, solution.routes.first.stops[1].alternative
  end

  def test_rest_with_exclusion_cost
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
        exclusion_cost: 10,
        duration: 1,
        timewindows: [{
          start: 0,
          end: 1
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        duration: 2
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          duration: 1,
          point_id: 'point_1'
        }
      }],
      configuration: {
        resolution: {
          duration: 200,
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, solutions[0].unassigned_stops.size
  end

  def test_rest_with_late_multiplier
    skip 'Rest currently cannot be late'
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
        late_multiplier: 0.3,
        duration: 3,
        timewindows: [{
          start: 0,
          end: 1
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0']
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          duration: 2,
          timewindows: [{
            start: 0,
            end: 1
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, solutions[0].unassigned_stops.size
  end

  def test_evaluate_only
    ortools = OptimizerWrapper.config[:services][:ortools]
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
      routes: [{
        mission_ids: ['service_1', 'service_2'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 3, solution.routes.first.stops.size
    assert_equal 2, solution.cost
    assert_equal 1, solution.iterations
  end

  def test_evaluate_only_not_every_service_has_route
    ortools = OptimizerWrapper.config[:services][:ortools]
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
      routes: [{
        mission_ids: ['service_1'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 1, solution.unassigned_stops.size
    assert_equal 1, solution.cost_info.total # exclusion costs are not included in the cost_details
    assert_equal 1, solution.iterations
  end

  def test_evaluate_only_not_every_vehicle_has_route
    ortools = OptimizerWrapper.config[:services][:ortools]
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
      }, {
        id: 'vehicle_1',
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
      routes: [{
        mission_ids: ['service_1', 'service_2'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    assert solution
    assert_equal 2, solution.routes.size
    assert_equal 0, solution.unassigned_stops.size
    assert_equal 2, solution.cost
    assert_equal 1, solution.iterations
  end

  def test_evaluate_only_with_computed_solution
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 2, 2],
          [2, 0, 2],
          [2, 2, 0]
        ]
      }],
      points: [{
        id: 'depot',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_1',
          duration: 2
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_2',
          duration: 1
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    expected_cost = solutions[0].cost
    expected_route = solutions[0].routes.first.stops.collect(&:service_id)

    problem[:configuration][:resolution][:evaluate_only] = true
    problem[:routes] = [{
      mission_ids: expected_route.compact,
      vehicle_id: 'vehicle_1'
    }]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal expected_cost, solutions[0].cost
    assert_equal 1, solutions[0].iterations
  end

  def test_try_several_heuristics_to_fix_ortools_solver_parameter
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 2, 2],
          [2, 0, 2],
          [2, 2, 0]
        ]
      }],
      points: [{
        id: 'depot',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_1',
          duration: 2
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_2',
          duration: 1
        }
      }],
      configuration: {
        resolution: {
          duration: 1000
        },
        preprocessing: {
          first_solution_strategy: ['global_cheapest_arc', 'local_cheapest_insertion', 'savings']
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_equal 3, solutions[0].heuristic_synthesis.size
    assert solutions[0].heuristic_synthesis.min_by{ |heuristic| heuristic[:cost] || Helper.fixnum_max }[:used]
    assert solutions[0].cost
  end

  def test_self_selection_first_solution_strategy
    vrp = VRP.lat_lon_two_vehicles
    vrp[:configuration][:preprocessing] = { first_solution_strategy: 'self_selection' }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert solutions[0]
    assert_equal 3, solutions[0].heuristic_synthesis.size
    assert solutions[0].heuristic_synthesis.min_by{ |heuristic| heuristic[:cost] || Helper.fixnum_max }[:used]
  end

  def test_self_selection_first_solution_strategy_with_routes
    problem = VRP.lat_lon_two_vehicles
    problem[:routes] = [{
      vehicle_id: 'vehicle_0',
      mission_ids: %w[service_4 service_5 service_3 service_2]
    }]
    problem[:configuration][:preprocessing] = { first_solution_strategy: 'self_selection' }
    vrp = TestHelper.create(problem)
    list = Interpreters::SeveralSolutions.collect_heuristics(vrp, ['self_selection'])

    call_to_solve = 0
    OptimizerWrapper.config[:services][:ortools].stub(
      :solve, lambda{ |vrp_in, _job|
        call_to_solve += 1

        # force to prefer solution provided by routes :
        if call_to_solve <= list.size

          Models::Solution.new(cost: 2**32.0,
                                         solvers: [:ortools],
                                         routes: [
                                           Models::Solution::Route.new(
                                             vehicle: vrp_in.vehicles[0],
                                           ),
                                           Models::Solution::Route.new(
                                             vehicle: vrp_in.vehicles[1]
                                           )
                                        ])
        else
          Models::Solution.new(cost: 10.0,
                                         solvers: [:ortools],
                                         routes: [
                                           Models::Solution::Route.new(
                                             vehicle: vrp_in.vehicles[0],
                                             stops: [Models::Solution::Stop.new(vrp_in.vehicles.first.start_point)] +
                                               vrp_in.routes.first.mission_ids.map{ |id|
                                                 Models::Solution::Stop.new(vrp_in.services.find{ |s| s.id == id })
                                               } + [Models::Solution::Stop.new(vrp_in.vehicles.first.end_point)]
                                           ),
                                           Models::Solution::Route.new(
                                             vehicle: vrp_in.vehicles[1]
                                           )
                                        ])
        end
      }
    ) do
      best_heuristic = Interpreters::SeveralSolutions.find_best_heuristic({ service: :ortools, vrp: vrp })
      refute_equal best_heuristic[:vrp].configuration.preprocessing.first_solution_strategy, 'supplied_initial_routes'
      assert_equal %w[service_4 service_5 service_3 service_2], best_heuristic[:vrp].routes.first.mission_ids,
                   'Initial route does not match with expected returned route'
    end
    assert_equal list.size + 1, call_to_solve, 'We should have used initial routes as additional first_solution_strategy'
  end

  def test_self_selection_computes_saving_only_once_if_rest
    vrp = VRP.lat_lon_two_vehicles
    list = Interpreters::SeveralSolutions.collect_heuristics(TestHelper.create(vrp), ['self_selection'])
    assert_equal 3, list.size

    vrp[:rests] = [{
      id: 'rest_0',
      timewindows: [{
        day_index: 0,
        start: 1,
        end: 1
      }],
      duration: 1
    }]
    vrp[:vehicles].first[:rest_ids] = ['rest_0']

    list = Interpreters::SeveralSolutions.collect_heuristics(TestHelper.create(vrp), ['self_selection'])
    assert_equal 3, list.size
  end

  def test_self_selection_first_solution_strategy_with_rest_should_call_savings
    vrp = VRP.lat_lon
    vrp[:vehicles].first[:end_point_id] = 'point_1'
    list = Interpreters::SeveralSolutions.collect_heuristics(TestHelper.create(vrp), ['self_selection'])
    refute_includes list, 'savings'

    vrp[:rests] = [{
      id: 'rest_0',
      timewindows: [{
        day_index: 0,
        start: 1,
        end: 1
      }],
      duration: 1
    }]
    vrp[:vehicles].first[:rest_ids] = ['rest_0']

    list = Interpreters::SeveralSolutions.collect_heuristics(TestHelper.create(vrp), ['self_selection'])
    assert_includes list, 'savings'
  end

  def test_no_solver_with_ortools_single_heuristic
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 2, 2],
          [2, 0, 2],
          [2, 2, 0]
        ]
      }],
      points: [{
        id: 'depot',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_1',
          duration: 1
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_1',
          duration: 2
        }
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_2',
          duration: 2
        }
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_2',
          duration: 1
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        preprocessing: {
          first_solution_strategy: ['first_unbound']
        }
      }
    }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0]
    assert_respond_to solutions[0], :cost
  end

  def test_insert_with_order
    vrp = TestHelper.load_vrp(self, fixture_file: 'instance_order')
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    assert solutions[0]
    assert_equal 0, solutions[0].unassigned_stops.size, 'All services should be planned.'

    order_in_route = vrp[:relations][0][:linked_ids].collect{ |service_id|
      solutions[0].routes.first.stops.find_index{ |activity| activity.service_id == service_id }
    }
    assert_equal order_in_route.sort, order_in_route, 'Services with order relation should appear in correct order in route.'
  end

  def test_ordre_with_2_vehicles
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1, 1, 1],
          [1, 0, 1, 1, 1, 1],
          [1, 1, 0, 1, 1, 1],
          [1, 1, 1, 0, 1, 1],
          [1, 1, 1, 1, 0, 1],
          [1, 1, 1, 1, 1, 0]
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }, {
        id: 'vehicle_1',
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2,
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2,
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 1,
        }]
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2,
        }]
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2,
        }]
      }],
      routes: [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1', 'service_2', 'service_3']
      }, {
        vehicle_id: 'vehicle_1',
        mission_ids: ['service_4', 'service_5']
      }],
      relations: [{
        id: 1,
        type: :order,
        linked_ids: ['service_1', 'service_2', 'service_3']
      }, {
        id: 2,
        type: :order,
        linked_ids: ['service_4', 'service_5']
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solution = ortools.solve(vrp, 'test')
    vrp[:relations].each_with_index{ |relation, index|
      previous_index = nil
      relation[:linked_ids].each{ |service_id|
        current_index = solution.routes[index].stops.find_index{ |activity| activity.service_id == service_id }
        assert((previous_index || -1) < current_index) if current_index
        previous_index = current_index
      }
    }
  end

  def test_regroup_timewindows
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
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
          day_index: 0
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
          timewindows: [
            { start: 0, end: 2, day_index: 0 },
            { start: 2, end: 5, day_index: 0 }
          ]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
          timewindows: [
            { start: 0, end: 2, day_index: 0 },
            { start: 4, end: 5, day_index: 0 }
          ]
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 1
          }
        }
      }
    }
    vrp = TestHelper.create(problem)
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 1, solutions[0].routes.first.stops.find{ |stop|
      stop.service_id == 'service_1_1_1'
    }.activity.timewindows.size
  end

  def test_subproblem_with_one_vehicle_and_no_possible_service
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 4, 5],
          [4, 0, 4],
          [8, 4, 0]
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
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
          end: 10
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
          timewindows: [{
            start: 0,
            end: 2,
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
          duration: 3,
          timewindows: [{
            start: 0,
            end: 6,
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 20,
        }
      }
    }
    vrp = TestHelper.create(problem)
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 0, solutions[0].routes[0].stops.size, 'All services should be eliminated'
    assert_equal 2, solutions[0].unassigned_stops.size, 'All services should be eliminated'
    assert_equal 0, solutions[0].cost, 'All eliminated, cost should be 0'
  end

  def test_ortools_performance_when_duration_limit
    # Test agains optim-ortools model regression wrt vehicle duration limit
    vrp = TestHelper.load_vrp(self)

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)

    assert_equal 0, solutions[0].unassigned_stops.size, 'There should be no unassigned.'
  end

  def test_unavailable_visit_day_date
    vrp = VRP.basic
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 1) }}
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 0, solutions[0].unassigned_stops.size

    vrp = VRP.basic
    vrp[:services] = [vrp[:services].first]
    vrp[:services].first[:unavailable_visit_day_date] = [Date.new(2020, 1, 1)]
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 1) }}
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 1, solutions[0].unassigned_stops.size

    vrp = VRP.basic
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['local_cheapest_insertion']
    vrp[:services] = [vrp[:services].first]
    vrp[:services].first[:unavailable_visit_day_date] = [Date.new(2020, 1, 1)]
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 2) }}
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, solutions[0].routes.find{ |r| r.vehicle_id == 'vehicle_0_3' }.stops.size

    vrp = VRP.basic
    vrp[:services] = [vrp[:services].first]
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['local_cheapest_insertion']
    vrp[:services].first[:unavailable_visit_day_date] = [Date.new(2020, 1, 2)]
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 2) }}
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, solutions[0].routes.find{ |r| r.vehicle.id == 'vehicle_0_2' }.stops.size
  end

  def test_minimum_duration_lapse
    vrp = VRP.lat_lon
    vrp[:vehicles].first[:timewindow] = { start: 10, end: 10000 }
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    first_index = solutions[0].routes.first.stops.find_index{ |stop| stop.service_id == 'service_1' }
    second_index = solutions[0].routes.first.stops.find_index{ |stop| stop.service_id == 'service_2' }
    # those services are at same location, they should be planned together :
    assert_includes [second_index - 1, second_index + 1], first_index
    assert_equal solutions[0].routes.first.stops[first_index].info.begin_time,
                 solutions[0].routes.first.stops[second_index].info.begin_time
    previous_solution = solutions[0].routes.collect{ |r| r.stops.map(&:service_id) }

    vrp[:relations] = [{
      type: :minimum_duration_lapse,
      linked_ids: ['service_1', 'service_2'],
      lapses: [0]
    }]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal previous_solution, (solutions[0].routes.collect{ |r| r.stops.map(&:service_id) })

    vrp[:relations].first[:lapses] = [10]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    route = solutions[0].routes.first.stops
    first_index = route.find_index{ |stop| stop.service_id == 'service_1' }
    second_index = route.find_index{ |stop| stop.service_id == 'service_2' }
    assert_operator first_index, :<, second_index
    assert_operator route[first_index].info.departure_time + 10, :<=,
                    route[second_index].info.begin_time
  end

  def test_minimum_duration_lapse_shipments
    vrp = TestHelper.load_vrp(self)
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_empty solutions[0].unassigned_stops
    shipment_route = solutions[0].routes.find{ |r| r.stops.any?{ |stop| stop.pickup_shipment_id == 'shipment_0' } }
    ordered_pickup_ids = shipment_route.stops.map(&:pickup_shipment_id).compact
    delivery1 = vrp.services.find{ |service| service.id == "#{ordered_pickup_ids[1]}_delivery" }
    pickup0 = vrp.services.find{ |service| service.id == "#{ordered_pickup_ids[0]}_pickup" }

    # add consecutivity:
    vrp = TestHelper.load_vrp(self)
    vrp.relations << Models::Relation.create(
      type: :minimum_duration_lapse,
      linked_ids: [delivery1.id, pickup0.id],
      lapses: [1800]
    )
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    shipment1_route = solutions[0].routes.find{ |r|
      r.stops.any?{ |stop| stop[:pickup_shipment_id] == delivery1.original_id }
    }
    delivery1_index = shipment1_route.stops.find_index{ |stop|
      stop.delivery_shipment_id == delivery1.original_id
    }
    shipment0_route = solutions[0].routes.find{ |r|
      r.stops.any?{ |stop| stop.pickup_shipment_id == pickup0.original_id }
    }
    pickup0_index = shipment0_route.stops.find_index{ |stop|
      stop.delivery_shipment_id == pickup0.original_id
    }
    assert pickup0_index
    assert_operator shipment1_route.stops[delivery1_index].info.departure_time + 1800, :<=,
                    shipment0_route.stops[pickup0_index].info.begin_time
  end

  def test_cost_info
    vrp = VRP.basic
    vrp[:units] = [{ id: 'kg' }]
    vrp[:vehicles].first.merge!(cost_fixed: 1, cost_time_multiplier: 2,
                                capacities: [{ unit_id: 'kg', limit: 1, overload_multiplier: 0.3 }])
    vrp[:services].first[:quantities] = [{ unit_id: 'kg', value: 2 }]
    vrp[:services].first[:activity].merge!(timewindows: [{ start: 0, end: 1, maximum_lateness: 3 }], late_multiplier: 0.007)
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 21.321, solutions[0].cost_info.total.round(3)
    assert_equal 1, solutions[0].cost_info.fixed
    assert_equal 20, solutions[0].cost_info.time
    assert_equal 0, solutions[0].cost_info.distance
    assert_equal 0, solutions[0].cost_info.value
    assert_equal 0.021, solutions[0].cost_info.lateness.round(3)
    assert_equal 0.3, solutions[0].cost_info.overload.round(3)
  end

  def test_direct_shipment
    vrp = VRP.pud
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp.dup), nil)
    route = solutions[0].routes.first.stops
    pickup_index = route.find_index{ |stop| stop[:pickup_shipment_id] }
    pickup_id = route[pickup_index][:pickup_shipment_id]
    delivery_index = route.find_index{ |stop| stop[:delivery_shipment_id] == pickup_id }
    assert_operator pickup_index + 1, :<, delivery_index,
                    'If this is case, we should edit the services to make sure we are testing direct shipment properly'
    vrp[:shipments].find{ |s| s[:id] == pickup_id }[:direct] = true
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp.dup), nil)
    route = solutions[0].routes.first.stops
    pickup_index = route.find_index{ |stop| stop[:pickup_shipment_id] == pickup_id }
    delivery_index = route.find_index{ |stop| stop[:delivery_shipment_id] == pickup_id }
    assert_equal pickup_index + 1, delivery_index
  end

  def test_ensure_total_time_and_travel_info_with_ortools
    vrp = VRP.basic
    vrp[:matrices].first[:distance] = vrp[:matrices].first[:time]
    solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert solutions[0].routes.all?{ |route| route.stops.empty? || route.info.total_time },
           'At least one route total_time was not provided'
    assert solutions[0].routes.all?{ |route| route.stops.empty? || route.info.total_travel_time },
           'At least one route total_travel_time was not provided'
    assert solutions[0].routes.all?{ |route| route.stops.empty? || route.info.total_distance },
           'At least one route total_travel_distance was not provided'
  end

  def test_optimization_over_more_than_a_week
    # overall data
    problem = VRP.basic
    problem[:units] = [
      { id: 'visit' }
    ]
    problem[:matrices].first[:time] = [
      [0, 1, 1, 1],
      [1, 0, 1, 1],
      [1, 1, 0, 1],
      [1, 1, 1, 0]
    ]
    problem[:vehicles].each{ |vehicle|
      vehicle[:capacities] = [{ unit_id: 'visit', limit: 1 }]
    }
    problem[:services].each{ |service|
      service[:quantities] = [{ unit_id: 'visit', value: 1.0 }]
    }
    problem[:configuration][:schedule] = { range_indices: { start: 0, end: 7 }}

    # evolutive data
    correspondance = ['without timewindow', 'with timewindows', 'with timewindows containing day index']
    tws_sets = [
      nil,
      [{ start: 0, end: 1000 }],
      (0..4).collect{ |day_index| { start: 0, end: 1000, day_index: day_index } }
    ]

    tws_sets.each_with_index{ |tw_set, v_tw_i|
      problem[:vehicles].first[:sequence_timewindows] = tw_set

      tws_sets.each_with_index{ |service_tw_set, s_tw_i|
        problem[:services].each{ |s|
          s[:activity][:timewindows] = service_tw_set
        }
        # this field is removed whenever we create vrp, so it should be added again at each loop
        problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]

        solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
        saturday_vehicle = solutions[0].routes.find{ |r| r[:vehicle_id] == 'vehicle_0_5' }
        sunday_vehicle = solutions[0].routes.find{ |r| r[:vehicle_id] == 'vehicle_0_6' }
        assert_nil saturday_vehicle, 'Vehicle should not be generated if it is not available a given day ' \
                                     "(case vehicle #{correspondance[v_tw_i]} and service #{correspondance[s_tw_i]})"
        assert_nil sunday_vehicle, 'Vehicle should not be generated if it is not available a given day ' \
                                   "(case vehicle #{correspondance[v_tw_i]} and service #{correspondance[s_tw_i]})"
        assert_empty solutions[0].unassigned_stops,
                     "We expect no unassigned services (case vehicle #{correspondance[v_tw_i]} and " \
                     "service #{correspondance[s_tw_i]})"
      }
    }
  end

  def test_force_start_when_there_is_a_service_with_late_tw_begin
    # ortools should return a sensible order for services
    # even if the begining and end of the route is fixed
    # by the force_start and a service with a very late TW

    vrp = VRP.basic

    size = 3

    # A time matrix that leads to incorrect order in the old force_start implementation
    array_first_column = [1]
    vrp[:matrices] = [
      {
        id: 'matrix_0',
        time: [(0..size - 2).to_a + [15, 17]] +
          (1..size).collect{ |i| array_first_column + (0..i - 1).to_a.reverse + Array.new(size - i){ |j| 2 * (j + 1) } }
      }
    ]

    vrp[:points] = Array.new(size + 1){ |p| { id: "point_#{p}", matrix_index: p } }

    vrp[:services] = Array.new(size){ |s|
      {
        id: "service_#{s + 1}",
        activity: {
          duration: 1,
          point_id: "point_#{s + 1}",
          timewindows: [{ start: 0, end: 30 }]
        }
      }
    }
    vrp[:services][-1][:activity][:timewindows] = [{ start: 28, end: nil }] # "bad" TW

    vrp[:vehicles] = [
      {
        id: 'vehicle',
        cost_time_multiplier: 1,
        cost_waiting_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        shift_preference: 'force_start',
        timewindow: { start: 0, end: 30 }
      }
    ]

    vrp[:routes] = [
      {
        vehicle_id: 'vehicle',
        mission_ids: ([size - 1] + (1..size - 2).to_a.sample(size - 2) + [size]).collect{ |i| "service_#{i}" }
      }
    ]

    vrp[:configuration][:resolution][:duration] = 20
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['global_cheapest_arc']

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

    visit_order = solutions[0].routes.first.stops.collect{ |s| s.activity.point.id&.split('_')&.last&.to_i }

    assert_equal (0..size).to_a + [0], visit_order, 'Services are not visited in the expected order'
  end

  def test_pause_should_be_last_if_possible
    vrp = VRP.basic

    vrp[:services].each{ |s|
      s[:activity][:duration] = 1
      s[:activity][:timewindows] = [{ start: 0, end: 100 }]
    }

    vrp[:rests] = [{ id: 'rest', timewindows: [{ start: 0, end: 50 }], duration: 10 }]

    vrp[:vehicles][0] = {
      id: 'vehicle',
      cost_time_multiplier: 1,
      cost_waiting_time_multiplier: 1,
      start_point_id: 'point_0',
      end_point_id: 'point_0',
      matrix_id: 'matrix_0',
      # shift_preference: 'force_start', # with force_start pause is already at the correct place
      timewindow: { start: 0, end: 200 },
      rest_ids: ['rest']
    }
    vrp[:routes] = [
      {
        vehicle_id: 'vehicle',
        mission_ids: [3, 1, 2].collect{ |i| "service_#{i}" } # start from the optimal solution
      }
    ]

    vrp[:configuration][:resolution][:duration] = 50
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['global_cheapest_arc'] # don't waste time with heuristic selector

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

    assert_equal solutions[0].routes.first.stops[-2].type, :rest, 'Pause should be at the last spot'
  end

  def test_no_nil_in_corresponding_mission_ids
    assert_empty OptimizerWrapper.config[:services][:ortools].send(:corresponding_mission_ids, ['only_id'], ['non_id'])
  end

  def test_self_selection_should_not_change_vehicle_ids
    problem = VRP.independent_skills
    problem[:configuration][:preprocessing] = { first_solution_strategy: ['self_selection'] }
    vrp = TestHelper.create(problem)
    heuristic_counter = 0
    OptimizerWrapper.config[:services][:ortools].stub(
      :solve, lambda{ |_vrp_in, _job|
        heuristic_counter += 1
        if heuristic_counter == 1
          Models::Solution.new(cost: 27648.0,
                                         solvers: [:ortools],
                                         elapsed: 0.94,
                                         routes: [
                                           Models::Solution::Route.new(vehicle: vrp.vehicles[0]),
                                           Models::Solution::Route.new(vehicle: vrp.vehicles[1]),
                                           Models::Solution::Route.new(vehicle: vrp.vehicles[2])
                                        ])
        else
          Models::Solution.new(cost: 14.0,
                                         solvers: [:ortools],
                                         elapsed: 0.94,
                                         routes: [
                                           Models::Solution::Route.new(
                                             vehicle: vrp.vehicles[0],
                                             stops: [Models::Solution::Stop.new(vrp.vehicles[0].start_point)]
                                           ),
                                           Models::Solution::Route.new(
                                             vehicle: vrp.vehicles[1],
                                             stops: [
                                               Models::Solution::Stop.new(vrp.vehicles[1].start_point),
                                               Models::Solution::Stop.new(vrp.services[4]),
                                               Models::Solution::Stop.new(vrp.services[2]),
                                               Models::Solution::Stop.new(vrp.services[0]),
                                               Models::Solution::Stop.new(vrp.services[1])
                                             ]
                                           ),
                                           Models::Solution::Route.new(
                                             vehicle: vrp.vehicles[2],
                                             stops: [Models::Solution::Stop.new(vrp.vehicles[2].start_point)]
                                           )
                                        ])
        end
      }
    ) do
      Interpreters::SeveralSolutions.stub(
        :collect_heuristics,
        lambda{ |_, _| %w[global_cheapest_arc parallel_cheapest_insertion local_cheapest_insertion savings] }
      ) do
        service_vrp = Interpreters::SeveralSolutions.find_best_heuristic({ service: :ortools, vrp: vrp })
        assert_equal vrp[:vehicles].size, service_vrp[:vrp].vehicles.collect(&:id).uniq.size, 'We expect same number of IDs as initial vehicles in problem'
        assert_equal vrp[:services].size, service_vrp[:vrp].services.collect(&:id).uniq.size, 'We expect same number of IDs as initial services in problem'
        assert_equal 4, service_vrp[:vrp].configuration.preprocessing.heuristic_synthesis.size
        assert_equal ['parallel_cheapest_insertion'], service_vrp[:vrp].configuration.preprocessing.first_solution_strategy
        assert_equal 1, service_vrp[:vrp].routes.size
        assert_equal 'vehicle_1', service_vrp[:vrp].routes.first.vehicle.id
        assert_equal ['service_5', 'service_3', 'service_1', 'service_2'], service_vrp[:vrp].routes.first.mission_ids
      end
    end
  end

  def test_quantity_precision
    problem = VRP.basic
    problem[:services].each{ |service|
      service[:quantities] = [{ unit_id: 'kg', value: 1.001 }]
    }
    problem[:vehicles].each{ |vehicle|
      vehicle[:capacities] = [{ unit_id: 'kg', limit: 3 }]
    }

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, solutions[0].unassigned_stops.size, 'The result is expected to contain 1 unassigned'

    assert_operator solutions[0].routes.first.stops.count(&:service_id), :<=, 2,
                    'The vehicle cannot load more than 2 services and 3 kg'
    solutions[0].routes.first.stops.each{ |activity|
      next unless activity.service_id

      assert_equal 1.001, activity.loads.first.quantity.value
    }
  end

  def test_initial_quantity
    problem = VRP.basic
    problem[:services].first[:quantities] = [{ unit_id: 'kg', value: -1 }]
    problem[:services].last[:quantities] = [{ unit_id: 'kg', value: -1 }]
    problem[:vehicles].each{ |vehicle|
      vehicle[:capacities] = [{ unit_id: 'kg', limit: 3, initial: 0 }]
    }

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 2, solutions[0].unassigned_stops.size, 'The result is expected to contain 2 unassigned'

    problem = VRP.basic
    problem[:services].first[:quantities] = [{ unit_id: 'kg', value: -1 }]
    problem[:services].last[:quantities] = [{ unit_id: 'kg', value: 1 }]
    problem[:vehicles].each{ |vehicle|
      vehicle[:capacities] = [{ unit_id: 'kg', limit: 3, initial: 0 }]
    }

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert solutions[0].routes.first.stops.index{ |act| act.service_id == problem[:services].last[:id] } <
           solutions[0].routes.first.stops.index{ |act| act.service_id == problem[:services].first[:id] }
  end

  def test_simplify_vehicle_pause_without_timewindow_or_duration
    complete_vrp = VRP.pud
    complete_vrp[:rests] = [{
      id: 'rest_0',
      duration: 1,
      timewindows: [{ day_index: 0 }]
    }]
    complete_vrp[:vehicles].first[:rest_ids] = ['rest_0']
    complete_vrp[:services] = [{
      id: 'service_0',
      activity: {
        point_id: 'point_0'
      }
    }]

    # main interest of this test is to ensure test does not fail even though we have no timewindow end on rest/vehicle
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(complete_vrp), nil)
    assert(solutions[0].routes.first.stops.any?{ |stop| stop.type == :rest })
    assert_empty solutions[0].unassigned_stops
  end

  def test_respect_timewindows_without_end
    # first two services are forced to be performed at 5 and 10 due to travel time and their TW
    # this pushes the third service out of its first TW (i.e., {start:5, end:10}) and
    # forces it to be processed after 20 because of its second TW (i.e., {start:20})
    # even though the vehicle arrives there at 15.
    problem = VRP.basic
    problem[:matrices][0][:time] = [
      [0, 5, 5, 5],
      [5, 0, 5, 5],
      [5, 5, 0, 5],
      [5, 5, 5, 0]
    ]
    problem[:services].each{ |s|
      s[:activity][:timewindows] = [{ start: 5, end: 10 }]
    }
    problem[:services].last[:activity][:timewindows] << { start: 20 }

    vrp = TestHelper.create(problem)
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)

    assert_empty solutions[0].unassigned_stops, 'All three services should be planned. There is an obvious feasible solution.'

    vrp.services.each{ |service|
      planned_begin_time = solutions[0].routes[0].stops.find{ |s| s.service_id == service.id }.info.begin_time
      assert service.activity.timewindows.one?{ |tw|
        planned_begin_time >= tw.start && (tw.end.nil? || planned_begin_time <= tw.end)
      }, 'Services should respect the TW without end and fall within exactly one of its TW ranges'
    }

    assert_equal 20, solutions[0].routes[0].stops.last.info.begin_time, 'Third service should be planned at 20'
  end

  def test_relations_sent_to_ortools_when_different_lapses
    problem = VRP.lat_lon_two_vehicles
    problem[:vehicles] << problem[:vehicles].last.dup
    problem[:vehicles].last[:id] += '_dup'
    relations = [
      { type: :sequence, linked_ids: problem[:services].slice(0..1).map{ |s| s[:id] } },
      { type: :vehicle_group_duration, linked_vehicle_ids: problem[:vehicles].map{ |s| s[:id] }, lapse: 2 },
      { type: :minimum_duration_lapse, linked_ids: problem[:services].slice(0..2).map{ |s| s[:id] }, lapse: 2 },
      { type: :minimum_duration_lapse, linked_ids: problem[:services].slice(0..2).map{ |s| s[:id] }, lapses: [2, 2] },
      { type: :minimum_duration_lapse, linked_ids: problem[:services].slice(0..2).map{ |s| s[:id] }, lapses: [2, 3] },
      { type: :vehicle_trips, linked_vehicle_ids: problem[:vehicles].slice(0..2).map{ |s| s[:id] }, lapses: [2, 3] },
      # same but we will provide schedule (index 6 :)
      { type: :vehicle_trips, linked_vehicle_ids: problem[:vehicles].slice(0..2).map{ |s| s[:id] }, lapses: [2, 3] }
    ]
    expected_number_of_relations = [1, 1, 1, 1, 2, 2, 8]

    relations.each_with_index{ |relation, pb_index|
      problem[:relations] = [relation]
      if [1, 6].include?(pb_index)
        problem[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }}
      else
        problem[:configuration].delete(:schedule)
      end
      OptimizerWrapper.config[:services][:ortools].stub(
        :run_ortools,
        lambda { |ortools_problem, _, _|
          # check number of relations sent to ortools
          assert_equal expected_number_of_relations[pb_index], ortools_problem.relations.size

          Models::Solution.new(status: :killed)
        }
      ) do
        OptimizerWrapper.solve(service: :ortools, vrp: TestHelper.create(problem.dup))
      end
    }
  end
end
