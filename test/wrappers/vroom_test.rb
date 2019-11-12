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


class Wrappers::VroomTest < Minitest::Test
  def test_minimal_problem
    vroom = OptimizerWrapper.config[:services][:vroom]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1],
          [1, 0]
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
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0'
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }],
    }
    vrp = Models::Vrp.create(problem)

    result = vroom.solve(vrp)

    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_loop_problem
    vroom = OptimizerWrapper.config[:services][:vroom]
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
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort
  end

  def test_no_end_problem
    vroom = OptimizerWrapper.config[:services][:vroom]
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
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-1].collect{ |a| a[:service_id] }.sort
  end

  def test_start_different_end_problem
    vroom = OptimizerWrapper.config[:services][:vroom]
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
        end_point_id: 'point_4',
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
      }],
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort
  end

  def test_vehicle_time_window
    vroom = OptimizerWrapper.config[:services][:vroom]
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1],
          [1, 0]
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
        matrix_id: 'matrix_0',
        timewindow: {
          start: 1,
          end: 10
        },
        cost_late_multiplier: 1
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0'
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }],
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_with_rest
    vroom = OptimizerWrapper.config[:services][:vroom]
    problem = {
      matrices: [{
        id: 'matrix',
        time: [
          [0, 655, 1948, 5231, 2971],
          [603, 0, 1692, 4977, 2715],
          [1861, 1636, 0, 6143, 1532],
          [5184, 4951, 6221, 0, 7244],
          [2982, 2758, 1652, 7264, 0],
        ]
      }],
      points: [{
        id: 'point_a',
        matrix_index: 0
      }, {
        id: 'point_b',
        matrix_index: 1
      }, {
        id: 'point_c',
        matrix_index: 2
      }, {
        id: 'point_d',
        matrix_index: 3
      }, {
        id: 'point_e',
        matrix_index: 4
      }],
      rests: [{
        id: 'rest_a',
        timewindows: [{
          start: 9000,
          end: 10000
        }],
        duration: 1000
      }],
      vehicles: [{
        id: 'vehicle_a',
        start_point_id: 'point_a',
        end_point_id: 'point_a',
        matrix_id: 'matrix',
        timewindow: {
          start: 100,
          end: 20000
        },
        rest_ids: ['rest_a'],
        cost_late_multiplier: 1
      }],
      services: [{
        id: 'service_b',
        activity: {
          point_id: 'point_e'
        }
      }, {
        id: 'service_c',
        activity: {
          point_id: 'point_d'
        }
      }, {
        id: 'service_d',
        activity: {
          point_id: 'point_c'
        }
      }, {
        id: 'service_e',
        activity: {
          point_id: 'point_b'
        }
      }],
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 3, result[:routes][0][:activities].index{ |a| a[:rest_id] }
  end

  def test_with_rest_at_the_end
    vroom = OptimizerWrapper.config[:services][:vroom]
    problem = {
      matrices: [{
        id: 'matrix',
        time: [
          [0, 655, 1948, 5231, 2971],
          [603, 0, 1692, 4977, 2715],
          [1861, 1636, 0, 6143, 1532],
          [5184, 4951, 6221, 0, 7244],
          [2982, 2758, 1652, 7264, 0],
        ]
      }],
      points: [{
        id: 'point_a',
        matrix_index: 0
      }, {
        id: 'point_b',
        matrix_index: 1
      }, {
        id: 'point_c',
        matrix_index: 2
      }, {
        id: 'point_d',
        matrix_index: 3
      }, {
        id: 'point_e',
        matrix_index: 4
      }],
      rests: [{
        id: 'rest_a',
        timewindows: [{
          start: 19000,
          end: 20000
        }],
        duration: 1000
      }],
      vehicles: [{
        id: 'vehicle_a',
        start_point_id: 'point_a',
        end_point_id: 'point_a',
        matrix_id: 'matrix',
        timewindow: {
          start: 100,
          end: 20000
        },
        rest_ids: ['rest_a'],
        cost_late_multiplier: 1
      }],
      services: [{
        id: 'service_b',
        activity: {
          point_id: 'point_e'
        }
      }, {
        id: 'service_c',
        activity: {
          point_id: 'point_d'
        }
      }, {
        id: 'service_d',
        activity: {
          point_id: 'point_c'
        }
      }, {
        id: 'service_e',
        activity: {
          point_id: 'point_b'
        }
      }],
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 5, result[:routes][0][:activities].index{ |a| a[:rest_id] }
  end

  def test_with_rest_at_the_start
    vroom = OptimizerWrapper.config[:services][:vroom]
    problem = {
      matrices: [{
        id: 'matrix',
        time: [
          [0, 655, 1948, 5231, 2971],
          [603, 0, 1692, 4977, 2715],
          [1861, 1636, 0, 6143, 1532],
          [5184, 4951, 6221, 0, 7244],
          [2982, 2758, 1652, 7264, 0],
        ]
      }],
      points: [{
        id: 'point_a',
        matrix_index: 0
      }, {
        id: 'point_b',
        matrix_index: 1
      }, {
        id: 'point_c',
        matrix_index: 2
      }, {
        id: 'point_d',
        matrix_index: 3
      }, {
        id: 'point_e',
        matrix_index: 4
      }],
      rests: [{
        id: 'rest_a',
        timewindows: [{
          start: 200,
          end: 500
        }],
        duration: 1000
      }],
      vehicles: [{
        id: 'vehicle_a',
        start_point_id: 'point_a',
        end_point_id: 'point_a',
        matrix_id: 'matrix',
        timewindow: {
          start: 100,
          end: 20000
        },
        rest_ids: ['rest_a'],
        cost_late_multiplier: 1
      }],
      services: [{
        id: 'service_b',
        activity: {
          point_id: 'point_e'
        }
      }, {
        id: 'service_c',
        activity: {
          point_id: 'point_d'
        }
      }, {
        id: 'service_d',
        activity: {
          point_id: 'point_c'
        }
      }, {
        id: 'service_e',
        activity: {
          point_id: 'point_b'
        }
      }],
    }
    vrp = Models::Vrp.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.compact.sort
    assert_equal 1, result[:routes][0][:activities].index{ |a| a[:rest_id] }
  end

  def test_vroom_with_self_selection
    vrp = VRP.basic
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['self_selection']

    vroom_counter = 0
    OptimizerWrapper.config[:services][:vroom].stub(:solve,
                                                    lambda { |_vrp, _job, _thread_prod|
                                                      vroom_counter += 1
                                                    }) do
      begin
        OptimizerWrapper.wrapper_vrp('vroom', { services: { vrp: [:vroom] }}, FCT.create(vrp), nil)
      rescue => e
        puts e
      end
    end

    assert_equal 1, vroom_counter
  end
end
