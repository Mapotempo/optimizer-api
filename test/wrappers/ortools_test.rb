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
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_group_overall_duration_first_vehicle
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
      },{
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
        type: 'vehicle_group_duration',
        linked_vehicle_ids: ['vehicle_0','vehicle_2'],
        lapse: 2
      }],
      configuration: {
        resolution: {
          duration: 1000,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes][1][:activities].size
  end

  def test_periodic_overall_duration
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
      },{
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
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal result[:routes][0][:activities].size, result[:routes][1][:activities].size
  end

  def test_periodic_with_group_duration
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
      },{
        id: 'vehicle_2',
        start_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
        }
      },{
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
        type: 'vehicle_group_duration',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
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
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 3, result[:routes][2][:activities].size
  end

  def test_overall_duration_with_rest_no_vehicle_tw
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
      },{
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
          duration: 10,
        },
        schedule:{
          range_indices:{
            start: 0,
            end: 1
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_1_0' }[:activities].size
    assert_equal 2, result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_0_0' }[:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_duration_adjusted_by_presence_of_rest
    # conflict with rest
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
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 1, result[:unassigned].size
  end

  def test_overall_duration_with_rest
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
          duration: 10,
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
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:routes][0][:activities].size
  end

  def test_overall_duration_on_weeks
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_weeks',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 1
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 5,
            end: 7
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
  end

  def test_overall_duration_on_weeks_date
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_weeks',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 1
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
           range_date: {
            start: Date.new(2018,3,30),
            end: Date.new(2018,4,2)
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
  end

  def test_overall_duration_on_two_weeks
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_weeks',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 2
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 5,
            end: 7
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 1, result[:unassigned].size
  end

  def test_overall_duration_on_two_weeks_date
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_weeks',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 1
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_date: {
            start: Date.new(2018,3,30),
            end: Date.new(2018,4,9)
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
  end

  def test_overall_duration_on_months
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_months',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 1
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_date: {
            start: Date.new(2018,3,30),
            end: Date.new(2018,4,1)
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 0, result[:unassigned].size
  end

  def test_overall_duration_on_two_months
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
        }
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0
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
      relations: [{
        type: 'vehicle_group_duration_on_months',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 2
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_date: {
            start: Date.new(2018,3,30),
            end: Date.new(2018,4,1)
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 1, result[:unassigned].size
  end

  def test_do_not_solve_if_range_index_and_month_duration
    ortools = OptimizerWrapper::ORTOOLS
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
      }, {
        id: 'vehicle_2',
        start_point_id: 'depot',
        end_point_id: 'depot',
        matrix_id: 'matrix_0',
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
      relations: [{
        type: 'vehicle_group_duration_on_months',
        linked_vehicle_ids: ['vehicle_1','vehicle_2'],
        lapse: 5,
        periodicity: 1
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices:{
            start: 0,
            end: 2
          }
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert !ortools.inapplicable_solve?(vrp).empty?
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + problem[:rests].size + 1, result[:routes][0][:activities].size
  end

  def test_with_rest_multiple_reference
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
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + problem[:vehicles].collect{ |vehicle| vehicle[:rest_ids].size }.inject(:+) + 2, result[:routes].collect{ |route| route[:activities].size }.inject(:+)
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][0][:activities].size
    assert_equal problem[:services].size + 2 - 1, result[:routes][1][:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_double_soft_time_windows_problem
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
          },{
            start: 10,
            end: 11
          }],
          late_multiplier: 1,
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_triple_soft_time_windows_problem
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
          },{
            start: 10,
            end: 11
          },{
            start: 15,
            end: 16
          }],
          late_multiplier: 1,
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_double_hard_time_windows_problem
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
          },{
            start: 10,
            end: 11
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size
  end

  def test_triple_hard_time_windows_problem
    ortools = OptimizerWrapper::ORTOOLS
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
          },{
            start: 10,
            end: 11
          },{
            start: 15,
            end: 16
          }],
          late_multiplier: 0,
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size
  end

  def test_nearby_specific_ordder
    ortools = OptimizerWrapper::ORTOOLS
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert result[:routes][0][:activities][1..-2].collect.with_index{ |activity, index| activity[:service_id] == "service_#{index}" }.all?
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
  end

  def test_distance_matrix
    ortools = OptimizerWrapper::ORTOOLS
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
  end

  def test_max_ride_distance
    ortools = OptimizerWrapper::ORTOOLS
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
  end

  def test_two_vehicles_one_matrix_each
    ortools = OptimizerWrapper::ORTOOLS
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
  end

  def test_skills
    ortools = OptimizerWrapper::ORTOOLS
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
        skills: [["frozen"]]
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        skills: [["cool"]]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        },
        skills: ["frozen"]
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        },
        skills: ["cool"]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        skills: ["frozen"]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        skills: ["cool"]
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 4, result[:routes][1][:activities].size
  end

  def test_setup_duration
    ortools = OptimizerWrapper::ORTOOLS
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
          setup_duration: 2,
          duration: 1,
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
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size , result[:routes][0][:activities].size - 1
    assert_equal problem[:services].size , result[:routes][1][:activities].size - 1
  end

  def test_pickup_delivery
    ortools = OptimizerWrapper::ORTOOLS
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
        capacities: [{
          unit_id: 'unit_0',
          limit: 10,
          overload_multiplier: 0,
        }]
      }],
      services: [{
        id: 'service_0',
        type: 'pickup',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 4,
        }]
      }, {
        id: 'service_1',
        type: 'pickup',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 4,
        }]
      }, {
        id: 'service_2',
        type: 'delivery',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 10,
        }]
      }, {
        id: 'service_3',
        type: 'delivery',
        activity: {
          point_id: 'point_3',
          late_multiplier: 0,
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
  end

  def test_pickup_delivery_2
    ortools = OptimizerWrapper::ORTOOLS
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
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit_0',
          limit: 10,
          overload_multiplier: 0,
        }]
      }],
      services: [{
        id: 'service_0',
        type: 'pickup',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }, {
        id: 'service_1',
        type: 'pickup',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }, {
        id: 'service_2',
        type: 'delivery',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }, {
        id: 'service_3',
        type: 'delivery',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }, {
        id: 'service_4',
        type: 'delivery',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }, {
        id: 'service_5',
        type: 'pickup',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9,
        }]
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 8, result[:routes][0][:activities].size
  end

  def test_pickup_delivery_3
    ortools = OptimizerWrapper::ORTOOLS
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
      }, {
        id: 'unit_1',
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
        capacities: [{
          unit_id: 'unit_0',
          limit: 2,
          overload_multiplier: 0,
        }, {
          unit_id: 'unit_1',
          limit: 2,
          overload_multiplier: 0,
        }]
      }],
      services: [{
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: -1,
        }, {
          unit_id: 'unit_1',
          value: 1,
        }]
      }, {
        id: 'service_2',
        type: 'pickup',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 2,
        }, {
          unit_id: 'unit_1',
          value: -2,
        }]
      }, {
        id: 'service_3',
        type: 'delivery',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: -1,
        }, {
          unit_id: 'unit_0',
          value: -1,
        }]
      }, {
        id: 'service_4',
        type: 'delivery',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: -3,
        }, {
          unit_id: 'unit_0',
          value: 3,
        }]
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size

    assert_equal 'service_3', result[:routes][0][:activities][1][:service_id]
    assert_equal 'service_1', result[:routes][0][:activities][2][:service_id]
    assert_equal 'service_2', result[:routes][0][:activities][3][:service_id]
  end

  def test_route_duration
    ortools = OptimizerWrapper::ORTOOLS
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
        type: 'service',
        activity: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_2',
          duration: 5,
          late_multiplier: 0,
        }
      }, {
        id: 'service_2',
        type: 'service',
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:unassigned].size
    assert_equal 3, result[:routes][0][:activities].size
  end

  def test_route_force_start
    ortools = OptimizerWrapper::ORTOOLS
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
        type: 'service',
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
        type: 'service',
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
        type: 'service',
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal "service_0", result[:routes][0][:activities][1][:service_id]
  end

  def test_route_shift_preference_to_force_start
    ortools = OptimizerWrapper::ORTOOLS
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
        type: 'service',
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
        type: 'service',
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
        type: 'service',
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal "service_0", result[:routes][0][:activities][1][:service_id]
  end

  def test_route_shift_preference_to_force_end
    ortools = OptimizerWrapper::ORTOOLS
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
        type: 'service',
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
        type: 'service',
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
        type: 'service',
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal 18, result[:routes][0][:activities][1][:begin_time]
  end

  def test_route_shift_preference_to_minimize_span
    ortools = OptimizerWrapper::ORTOOLS
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
        type: 'service',
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
        type: 'service',
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
        type: 'service',
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal 18, result[:routes][0][:activities][1][:begin_time]
  end

  def test_vehicle_limit
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
          duration: 10,
          vehicle_limit: 1
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size + result[:routes][1][:activities].size
  end

  def test_minimum_day_lapse
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
        matrix_id: 'matrix_0',
        global_day_index: 0
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        global_day_index: 1
      }, {
        id: 'vehicle_2',
        matrix_id: 'matrix_0',
        global_day_index: 2
      }, {
        id: 'vehicle_3',
        matrix_id: 'matrix_0',
        global_day_index: 3
      }, {
        id: 'vehicle_4',
        matrix_id: 'matrix_0',
        global_day_index: 4
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
          point_id: 'point_2'
        }
      }],
      relations: [{
        id: 'minimum_lapse_1',
        type: "minimum_day_lapse",
        lapse: 2,
        linked_ids: ['service_1', 'service_2', 'service_3']
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 5, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][2][:activities].size + result[:routes][4][:activities].size
    assert_equal result[:routes][0][:activities].size, result[:routes][2][:activities].size
    assert_equal result[:routes][2][:activities].size, result[:routes][4][:activities].size
  end

  def test_maximum_day_lapse
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
      units: [{
        id: 'unit'
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
        global_day_index: 0,
        capacities: [{
          unit_id: 'unit',
          limit: 1
        }]
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        global_day_index: 4,
        capacities: [{
          unit_id: 'unit',
          limit: 1
        }]
      }, {
        id: 'vehicle_2',
        matrix_id: 'matrix_0',
        global_day_index: 3,
        capacities: [{
          unit_id: 'unit',
          limit: 1
        }]
      }, {
        id: 'vehicle_3',
        matrix_id: 'matrix_0',
        global_day_index: 2,
        capacities: [{
          unit_id: 'unit',
          limit: 1
        }]
      }, {
        id: 'vehicle_4',
        matrix_id: 'matrix_0',
        global_day_index: 1,
        capacities: [{
          unit_id: 'unit',
          limit: 1
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit',
          value: 1
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit',
          value: 1
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit',
          value: 1
        }]
      }],
      relations: [{
        id: 'maximum_lapse_1',
        type: "maximum_day_lapse",
        lapse: 1,
        linked_ids: ['service_1', 'service_2']
      },{
        id: 'maximum_lapse_2',
        type: "maximum_day_lapse",
        lapse: 1,
        linked_ids: ['service_1', 'service_3']
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 5, result[:routes].size
    assert_equal 1, result[:unassigned].size
    assert problem[:vehicles].find{ |vehicle| result[:routes].find{ |route|
      route[:activities].one?{ |activity| activity[:service_id] == ('service_2' || 'service_3') }
    }[:vehicle_id] == vehicle[:id] }[:global_day_index] - problem[:vehicles].find{ |vehicle| result[:routes].find{ |route|
      route[:activities].one?{ |activity| activity[:service_id]  == 'service_1' }
    }[:vehicle_id] == vehicle[:id] }[:global_day_index] == 1
  end

  def test_counting_quantities
    ortools = OptimizerWrapper::ORTOOLS
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
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1 - 1, result[:routes][0][:activities].size
    assert_equal 1, result[:unassigned].size
  end

  def test_shipments
    ortools = OptimizerWrapper::ORTOOLS
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
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_3',
          duration: 3,
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_shipments_quantities
    ortools = OptimizerWrapper::ORTOOLS
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
          unit_id: "unit_0",
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
          unit_id: "unit_0",
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} + 1 == result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} + 1 == result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_shipments_inroute_duration
    ortools = OptimizerWrapper::ORTOOLS
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
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        maximum_inroute_duration: 12,
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'shipment_1',
        maximum_inroute_duration: 12,
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_3',
          duration: 3,
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal result[:routes][0][:activities].find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } + 1, result[:routes][0][:activities].find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert_equal result[:routes][0][:activities].find_index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } + 1, result[:routes][0][:activities].find_index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_mixed_shipments_and_services
    ortools = OptimizerWrapper::ORTOOLS
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
  end

  def test_shipments_distance
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        distance: [
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
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_1',
          duration: 3,
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0'}
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_maximum_duration_lapse_shipments
    ortools = OptimizerWrapper::ORTOOLS
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
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
          timewindows: [{
            start: 0,
            end: 100
          }]
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
          timewindows: [{
            start: 300,
            end: 400
          }]
        }
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
          timewindows: [{
            start: 0,
            end: 100
          }]
        },
        delivery: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
          timewindows: [{
            start: 100,
            end: 200
          }]
        }
      }],
      relations: [{
        type: "maximum_duration_lapse",
        lapse: 100,
        linked_ids: ["shipment_0pickup", "shipment_0delivery"]
      },{
        type: "maximum_duration_lapse",
        lapse: 100,
        linked_ids: ["shipment_1pickup", "shipment_1delivery"]
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 4, result[:routes][0][:activities].size
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1'} < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1'}
    assert_equal 2, result[:unassigned].size
  end

  def test_pickup_timewindow_after_delivery_timewindow
    ortools = OptimizerWrapper::ORTOOLS
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
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_1',
        pickup: {
          point_id: 'point_1',
          duration: 1,
          late_multiplier: 0,
          timewindows: [{
            start: 6,
            end: 9
          }]
        },
        delivery: {
          point_id: 'point_2',
          duration: 1,
          late_multiplier: 0,
          timewindows: [{
            start: 1,
            end: 5
          }]
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
    vrp = Models::Vrp.create(problem)
    assert !ortools.assert_no_pickup_timewindows_after_delivery_timewindows(vrp)
    result = ortools.solve(vrp, 'test')
  end

  def test_value_matrix
    ortools = OptimizerWrapper::ORTOOLS
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
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 2, result[:routes][1][:activities].size
  end

  def test_sequence
    ortools = OptimizerWrapper::ORTOOLS
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
        type: "sequence",
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 5, result[:routes][1][:activities].size
  end

  def test_unreachable_destination
    ortools = OptimizerWrapper::ORTOOLS
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
          id: "point_0",
          location: {
              lat: 43.8,
              lon: 5.8
          }
      }, {
          id: "point_1",
          location: {
              lat: -43.8,
              lon: 5.8
          }
      }, {
          id: "point_2",
          location: {
              lat: 44.8,
              lon: 4.8
          }
      }, {
          id: "agent_home",
          location: {
              lat: 44.0,
              lon: 5.1
          }
      }],
      vehicles: [{
          id: "vehicle_1",
          cost_time_multiplier: 1.0,
          cost_waiting_time_multiplier: 1.0,
          cost_distance_multiplier: 1.0,
          router_mode: "car",
          router_dimension: "time",
          speed_multiplier: 1.0,
          start_point_id: "agent_home",
          end_point_id: "agent_home"
      }],
      services: [{
          id: "service_0",
          type: "service",
          activity: {
            duration: 100.0,
            point_id: "point_0"
          }
      }, {
          id: "service_1",
          type: "service",
          activity: {
              duration: 100.0,
              point_id: "point_1"
          }
      }, {
          id: "service_2",
          type: "service",
          activity: {
              duration: 100.0,
              point_id: "point_2"
          }
      }]
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    assert result
    assert_equal 4, result[:routes][0][:activities].size
    assert result[:cost] < 2 ** 32
  end

  def test_initial_load_output
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
      units: [{
        id: 'kg',
        label: 'Kg'
      }, {
        id: 'l',
        label: 'L'
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
          value: -5
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'kg',
          value: 4
        },{
          unit_id: 'l',
          value: -1
        }]
      }],
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal 5, result[:routes].first[:initial_loads].first[:value]
    assert_equal 1, result[:routes].first[:initial_loads][1][:value]
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
  end

  def test_force_first
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
        matrix_id: 'matrix_0',
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
      }, {
        id: 'vehicle_2',
        matrix_id: 'matrix_0',
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2'
        },
      }],
      relations: [{
        id: 'force_first',
        type: "force_first",
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 3, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    assert_equal 'service_1', result[:routes][0][:activities].first[:service_id]
    assert_equal 'service_3', result[:routes][1][:activities].first[:service_id]
  end

  def test_force_end
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
        matrix_id: 'matrix_0',
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_2'
        },
      }],
      relations: [{
        id: 'force_end',
        type: "force_end",
        linked_ids: ['service_1']
      }, {
        id: 'force_end2',
        type: "force_end",
        linked_ids: ['service_3']
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    assert_equal 'service_1', result[:routes][0][:activities].last[:service_id]
    assert_equal 'service_3', result[:routes][1][:activities].last[:service_id]
  end

  def test_never_first
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
        matrix_id: 'matrix_0',
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
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
          point_id: 'point_2'
        }
      }],
      relations: [{
        id: 'never_first',
        type: "never_first",
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal problem[:services].size, [result[:routes][0][:activities].size, result[:routes][1][:activities].size].max
    assert_equal 'service_2', result[:routes][0][:activities].first[:service_id] || result[:routes][1][:activities].first[:service_id]
  end

  def test_fill_quantities
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      units: [{
        id: 'kg',
        labal: 'kg'
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
        type: "never_first",
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
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal problem[:services].size, result[:routes][0][:activities].size
    assert 'service_2' == result[:routes][0][:activities].first[:service_id] || 'service_2' == result[:routes][0][:activities].last[:service_id]
    assert 'service_3' == result[:routes][0][:activities].first[:service_id] || 'service_3' == result[:routes][0][:activities].last[:service_id]
    assert_equal 'service_1', result[:routes][0][:activities][1][:service_id]
    assert_equal result[:routes][0][:initial_loads].first[:value], 5
  end

  def test_max_ride_time
    ortools = OptimizerWrapper::ORTOOLS
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
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size, result[:routes][0][:activities].size
    assert_equal 1 , result[:unassigned].size
  end

  def test_vehicle_max_distance
    ortools = OptimizerWrapper::ORTOOLS
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
      },{
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
      },{
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal problem[:services].size + 1 , result[:routes][1][:activities].size
    assert_equal 0 , result[:unassigned].size
  end

  def test_vehicle_max_distance_one_per_vehicle
    ortools = OptimizerWrapper::ORTOOLS
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
        cost_time_multiplier:0,
        cost_distance_multiplier: 1,
        distance: 11
      },{
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_time_multiplier:0,
        cost_distance_multiplier: 1,
        distance: 10
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        }
      },{
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert_equal result[:routes][0][:activities].size , result[:routes][1][:activities].size
  end

  def test_max_ride_time_never_from_or_to_depot
    ortools = OptimizerWrapper::ORTOOLS
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
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 52, result[:cost]
    assert_equal 3, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
    assert_equal 0 , result[:unassigned].size
  end

  def test_initial_routes
    ortools = OptimizerWrapper::ORTOOLS
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
      routes: [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1', 'service_3', 'service_2']
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    # Initial routes are soft assignment
    assert_equal 2, result[:routes].size
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 5, result[:routes][1][:activities].size
  end

  def test_alternative_service
    ortools = OptimizerWrapper::ORTOOLS
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1000],
          [1, 0, 1000],
          [1000, 1000, 0],
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
        cost_time_multiplier: 1,
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0'
      }],
      services: [{
        id: 'service_1',
        activities: [{
          point_id: 'point_1'
        },{
          point_id: 'point_2'
        }],
        skills: ['skill1']
      }],
      routes: [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1', 'service_3', 'service_2']
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal [], result[:unassigned]
    assert_equal 0, result[:routes][0][:activities][1][:alternative]
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
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 0, result[:unassigned].size
  end

  def test_rest_with_late_multiplier
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
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 0, result[:unassigned].size
  end

  def test_evaluate_only
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
      routes: [{
        mission_ids: ['service_1','service_2'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 0, result[:unassigned].size
    assert_equal 3, result[:routes][0][:activities].size
    assert_equal 2, result[:cost]
    assert_equal 1, result[:iterations]
  end

  def test_evaluate_only_not_every_service_has_route
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
      routes: [{
        mission_ids: ['service_1'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 1, result[:unassigned].size
    assert_equal 65, result[:cost]
    assert_equal 1, result[:iterations]
  end

  def test_evaluate_only_not_every_vehicle_has_route
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
      },{
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
        mission_ids: ['service_1','service_2'],
        vehicle_id: 'vehicle_0'
      }],
      configuration: {
        resolution: {
          evaluate_only: true,
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    assert ortools.inapplicable_solve?(vrp).empty?
    result = ortools.solve(vrp, 'test')
    assert result
    assert_equal 2, result[:routes].size
    assert_equal 0, result[:unassigned].size
    assert_equal 2, result[:cost]
    assert_equal 1, result[:iterations]
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
          duration: 10,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 2310, result[:cost]

    problem[:configuration][:resolution][:evaluate_only] = true
    problem[:routes] = [{
      mission_ids: ['service_2','service_1'],
      vehicle_id: 'vehicle_1'
    }]
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert_equal 2310, result[:cost]
    assert_equal 1, result[:iterations]
  end

  def test_try_several_heuristics_to_fix_solver_parameter
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
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:heuristic_synthesis].size
    assert result[:heuristic_synthesis].sort_by{ |heuristic| heuristic[:cost] || result[:heuristic_synthesis].collect{ |heur| heur[:cost] }.compact.max + 20 }[0][:used]
  end

  def test_self_selection_first_solution_strategy
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
        overall_duration: 10,
        timewindow: {
          start: 0
        },
        force_start: 6
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
          first_solution_strategy: ['self_selection']
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert_equal 3, result[:heuristic_synthesis].size
    assert result[:heuristic_synthesis].sort_by{ |heuristic| heuristic[:cost] || result[:heuristic_synthesis].collect{ |heur| heur[:cost] }.compact.max + 20 }[0][:used]
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
          duration: 10
        },
        preprocessing: {
          first_solution_strategy: ['first_unbound']
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(problem), nil)
    assert result
    assert result.key?(:cost)
  end

  def test_assemble_heuristic
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
        matrix_id: 'matrix_0',
        cost_late_multiplier: 0,
        shift_preference: 'force_start'
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_late_multiplier: 0,
        shift_preference: 'force_start'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          late_multiplier: 0,
          timewindows: [{
            start: 0,
            end: 2
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          late_multiplier: 0
        }
      }],
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    service_vrp = {
      service: ortools,
      vrp: vrp,
      fleet_id: [],
      problem_size: 2
    }
    assert Interpreters::Assemble.assemble_candidate([service_vrp])
  end
end
