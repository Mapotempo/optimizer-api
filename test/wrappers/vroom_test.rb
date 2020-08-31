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
    vrp = TestHelper.create(problem)

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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort!
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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, result[:routes][0][:activities][1..-1].collect{ |a| a[:service_id] }.sort!
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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }.sort!
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
    vrp = TestHelper.create(problem)
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
        rest_ids: ['rest_a']
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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    activities = result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }
    activities.compact!
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, activities.sort!
    assert_equal(3, result[:routes][0][:activities].index{ |a| a[:rest_id] })
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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    activities = result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }
    activities.compact!
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, activities.sort!
    assert_equal(5, result[:routes][0][:activities].index{ |a| a[:rest_id] })
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
    vrp = TestHelper.create(problem)
    result = vroom.solve(vrp)
    assert result
    assert_equal 1, result[:routes].size
    assert_equal problem[:services].size + 2 + problem[:vehicles][0][:rest_ids].size, result[:routes][0][:activities].size
    activities = result[:routes][0][:activities][1..-2].collect{ |a| a[:service_id] }
    activities.compact!
    assert_equal problem[:services].collect{ |s| s[:id] }.sort!, activities.sort!
    assert_equal(1, result[:routes][0][:activities].index{ |a| a[:rest_id] })
  end

  def test_vroom_with_self_selection
    vrp = VRP.basic
    vrp[:configuration][:preprocessing][:first_solution_strategy] = ['self_selection']

    vroom_counter = 0
    OptimizerWrapper.config[:services][:vroom].stub(
      :solve,
      lambda { |vrp_in, _job, _thread_prod|
        vroom_counter += 1
        # Return empty result to make sure the code continues regularly
        {
          cost: 0,
          solvers: ['vroom'],
          routes: [],
          unassigned: (vrp_in.services.collect{ |service|
            {
              service_id: service.id,
              type: service.type.to_s,
              point_id: service.activity.point_id
            }
          })
        }
      }
    ) do
      OptimizerWrapper.wrapper_vrp('vroom', { services: { vrp: [:vroom] }}, TestHelper.create(vrp), nil)
    end

    assert_equal 1, vroom_counter
  end

  def test_ensure_total_time_and_travel_info_with_vroom
    vrp = VRP.basic
    vrp[:matrices].first[:distance] = vrp[:matrices].first[:time]
    result = OptimizerWrapper.wrapper_vrp('vroom', { services: { vrp: [:vroom] }}, TestHelper.create(vrp), nil)
    assert result[:routes].all?{ |route| route[:activities].empty? || route[:total_time] }, 'At least one route total_time was not provided'
    assert result[:routes].all?{ |route| route[:activities].empty? || route[:total_travel_time] }, 'At least one route total_travel_time was not provided'
    assert result[:routes].all?{ |route| route[:activities].empty? || route[:total_distance] }, 'At least one route total_travel_distance was not provided'
  end

  def test_shipments
    vroom = OptimizerWrapper.config[:services][:ortools]
    vrp = TestHelper.create(VRP.pud)
    result = vroom.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' }
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_shipments_quantities
    vroom = OptimizerWrapper.config[:services][:vroom]
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
    result = vroom.solve(vrp, 'test')
    assert result
    assert_equal(result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_0' } + 1, result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_0' })
    assert_equal(result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } + 1, result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' })
    assert_equal 0, result[:unassigned].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_mixed_shipments_and_services
    vroom = OptimizerWrapper.config[:services][:ortools]
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
    result = vroom.solve(vrp, 'test')
    assert result
    assert result[:routes][0][:activities].index{ |activity| activity[:pickup_shipment_id] == 'shipment_1' } < result[:routes][0][:activities].index{ |activity| activity[:delivery_shipment_id] == 'shipment_1' }
    assert_equal 0, result[:unassigned].size
    assert_equal 5, result[:routes][0][:activities].size
  end
end
