# Copyright © Mapotempo, 2019
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

class FiltersTest < Minitest::Test
  def test_integer_too_big_to_convert_to_int32
    ortools = OptimizerWrapper.config[:services][:ortools]
    problem = {
      matrices: [
        {
          id: 'matrix_0',
          time: [
            [0, 1, 1],
            [1, 0, 1],
            [1, 1, 0]
          ]
        }
      ],
      points: [
        {
          id: 'point_0',
          matrix_index: 0
        }
      ],
      units: [
        {
          id: 'unit_0',
        }
      ],
      vehicles: [
        {
          id: 'vehicle_0',
          start_point_id: 'point_0',
          matrix_id: 'matrix_0',
          capacities: [
            {
              unit_id: 'unit_0',
              limit: 10000000000,
              overload_multiplier: 0,
            }
          ]
        }
      ],
    }
    vrp = TestHelper.create(problem)
    assert ortools.solve(vrp, 'test')
  end

  # calculate_unit_precision function is called in OptimizerWrapper.wrapper_vrp
  # before calling ortools.solve which calls run_ortools which only accepts integer values.
  #
  # FIXME: Currently we multiply such float values by 1000 inside ortools.solve before calling
  # run_ortools. That is, unit.precision_coef is calculated but not used yet.
  # Therefore this test checks if the calculated unit.precision_coef is correct but it can
  # check the actual capacity and quantity values after precision_coef is put upto use.
  def test_if_ortools_recieves_correct_capacity_quantity_balancing_precision_coef
    skip "precision_coeffision calculation is disactivated. The test should be
          corrected and activated when precision coefficion implementaion is corrected.
          Model::X.all's needs to be corrected in the test as well."
    prob = {
      matrices: [
        {
          id: 'matrix_0',
          time: [
            [0, 1, 1],
            [1, 0, 1],
            [1, 1, 0]
          ]
        }
      ],
      points: [
        {
          id: 'point_0',
          matrix_index: 0
        }
      ],
      units: [
        {
          id: 'unit_0',
        },
        {
          id: 'unit_1',
        },
        {
          id: 'unit_2',
        },
        {
          id: 'unit_3',
        },
        {
          id: 'unit_4',
        },
        {
          id: 'unit_counting',
          counting: true
        }
      ],
      vehicles: [
        {
          id: 'vehicle_0',
          start_point_id: 'point_0',
          matrix_id: 'matrix_0',
          capacities: [
            {
              unit_id: 'unit_0',
              limit: 253.0,
              overload_multiplier: 0,
            },
            {
              unit_id: 'unit_1',
              limit: 1000.0,
              overload_multiplier: 0,
            },
            {
              unit_id: 'unit_2',
              limit: 10.5,
              overload_multiplier: 0,
            },
            {
              unit_id: 'unit_counting',
              limit: 5.0
            }
          ]
        }
      ],
      services: [
        {
          id: 'service_0',
          type: 'service',
          activity: {
            point_id: 'point_0'
          },
          quantities: [
            {
              unit_id: 'unit_0',
              value: 10.12
            },
            {
              unit_id: 'unit_1',
              value: 100.0
            },
            {
              unit_id: 'unit_3',
              value: 10.5
            },
            {
              unit_id: 'unit_counting',
              value: 2.5,
              setup_value: 0
            }
          ]
        }
      ],
      configuration: {
        resolution: {
          duration: 1
        }
      },
    }

    true_capacities = {'unit_0' => 25, 'unit_1' => 30, 'unit_2' => 1, 'unit_counting' => 2}
    true_quantities = {'unit_0' => 1, 'unit_1' => 3, 'unit_3' => 1, 'unit_counting' => 1}

    OptimizerWrapper.config[:services][:ortools].stub(
      :run_ortools, # (problem, vrp, services, points, matrix_indices, thread_proc = nil, &block)
      lambda { |problem, vrp, services, _, _, _|
        # Check if precision coefficient turns the values to integer (i.e., (float.round - float).abs < dalta ).
        Models::Capacity.all.each{ |cap|
          integer_capacity = (cap.unit.precision_coef * cap.limit).round

          assert_in_delta integer_capacity, cap.unit.precision_coef * cap.limit, 1e-10

          assert_equal true_capacities[cap.unit_id], integer_capacity
        }

        Models::Quantity.all.each{ |qan|
          integer_quantity = (qan.unit.precision_coef * qan.value).round

          assert_in_delta integer_quantity, qan.unit.precision_coef * qan.value, 1e-10

          assert_equal true_quantities[qan.unit_id], integer_quantity
        }

        # FIXME: Currently we continue to multiply the quantity and capacity values with 1000
        # before calling run_ortools in ortools::solve. The asserts below are there to ensure
        # that we fix this test when we start using the correct precision_coef by replacing
        # the assert with the commented-out one.
        problem.vehicles[0].capacities.each_with_index{ |cap, index|
          assert_equal (true_capacities[vrp.units[index].id].nil? ? -2147483648 : (true_capacities[vrp.units[index].id] / vrp.units[index].precision_coef * (vrp.units[index].counting ? 1 : 1000.0)).round), cap.limit
          # assert_equal (true_capacities[vrp.units[index].id].nil? ? -2147483648 : true_capacities[vrp.units[index].id]), cap.limit
        }
        services[0].quantities.each_with_index{ |qan_value, index|
          assert_equal (true_quantities[vrp.units[index].id].nil? ? 0 : (true_quantities[vrp.units[index].id] / vrp.units[index].precision_coef * (vrp.units[index].counting ? 1 : 1000.0)).round), qan_value
          # assert_equal (true_quantities[vrp.units[index].id].nil? ? 0 : true_quantities[vrp.units[index].id]), qan_value
        }

        'Job killed' # Return "Job killed" to stop gracefully
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, TestHelper.create(prob), nil)
    end
  end

  def test_do_not_filter_limit_cases
    vrp = VRP.basic
    vrp[:units] = [{ id: 'kg' }]
    vrp[:vehicles][0][:timewindow] = { start: 5, end: 25 }
    vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 3 }]
    # vrp[:services][0][:activity][:late_multiplier] = 0.3

    vrp[:vehicles][0][:capacities] = [{ unit_id: 'kg', limit: 5, overload_multiplier: 0 }]
    vrp[:services][1][:quantities] = [{ unit_id: 'kg', value: 10 }]

    vrp[:matrices].first[:time].map!{ |l| l << 50 }
    vrp[:matrices].first[:time] << [50, 50, 50, 50, 0]
    vrp[:vehicles][0][:cost_late_multiplier] = 0

    vrp[:services][2][:activity][:duration] = 30

    OptimizerWrapper.config[:services][:ortools].stub(
      :solve, # (cluster_vrp, job, proc)
      lambda { |cluster_vrp, _, _,|
        assert_equal 0, cluster_vrp.services.size
        'Job killed'
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    end

    vrp[:services][0][:activity][:late_multiplier] = 0.3
    vrp[:vehicles][0][:capacities] = [{ unit_id: 'kg', limit: 5, overload_multiplier: 1 }]
    vrp[:vehicles][0][:cost_late_multiplier] = 0.3

    OptimizerWrapper.config[:services][:ortools].stub(
      :solve, # (cluster_vrp, job, proc)
      lambda { |cluster_vrp, _, _,|
        assert_equal 3, cluster_vrp.services.size
        'Job killed'
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    end
  end

  def test_do_not_filter_nil_capacities
    vrp = VRP.basic
    vrp[:units] = [{ id: 'kg' }, { id: 'kg1' }, { id: 'kg2' }, { id: 'kg3' }, { id: 'kg4' }, { id: 'kg5' }]
    vrp[:vehicles] << { id: 'vehicle_1', matrix_id: 'matrix_0', start_point_id: 'point_0' }
    vrp[:vehicles][0][:capacities] = [
      { unit_id: 'kg1', limit: 10 }, { unit_id: 'kg2', limit: 10 }, { unit_id: 'kg3', limit: nil },
      { unit_id: 'kg5', limit: 10, overload_multiplier: 1 }
    ]
    vrp[:vehicles][1][:capacities] = [
      { unit_id: 'kg2', limit: nil }, { unit_id: 'kg3', limit: 10 }, { unit_id: 'kg4', limit: 10 },
      { unit_id: 'kg5', limit: 10, overload_multiplier: 1 }
    ]

    vrp[:services][0][:quantities] = [{ unit_id: 'kg', value: 11 }, { unit_id: 'kg1', value: 11 }]
    vrp[:services][1][:quantities] = [{ unit_id: 'kg2', value: 11 }, { unit_id: 'kg2', value: 11 }]
    vrp[:services][2][:quantities] = [{ unit_id: 'kg3', value: 11 }, { unit_id: 'kg5', value: 11 }]

    OptimizerWrapper.config[:services][:ortools].stub(
      :solve, # (cluster_vrp, job, proc)
      lambda { |cluster_vrp, _, _,|
        assert_equal 3, cluster_vrp.services.size
        'Job killed'
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    end
  end

  def test_independent_filter
    vrp = VRP.independent
    vrp[:vehicles][1][:timewindow] = { start: 20, end: 60 }
    # Have one service filtered for each independent problem
    vrp[:services][0][:activity][:duration] = 21
    vrp[:services][4][:activity][:timewindows] = [{ start: 0, end: 10 }]

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

    assert_equal 2, result[:unassigned].size
    result[:routes].each{ |route|
      assert_equal 2, route[:activities].select{ |activity| activity[:service_id] }.size
    }
  end
end
