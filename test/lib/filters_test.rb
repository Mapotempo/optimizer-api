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
    vrp = Models::Vrp.create(problem)
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
    OptimizerWrapper.config[:solve_synchronously] = true
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
      :run_ortools, #(problem, vrp, services, points, matrix_indices, thread_proc = nil, &block)
      lambda { |problem, vrp, services, _, _, _|
        # Check if precision coefficient turns the values to integer (i.e., (float.round - float).abs < dalta ).
        Models::Capacity.all.each{ |cap|
          integer_capacity = (cap.unit.precision_coef * cap.limit).round

          assert_in_delta integer_capacity, cap.unit.precision_coef * cap.limit, 1e-10

          assert_equal integer_capacity, true_capacities[cap.unit_id]
        }

        Models::Quantity.all.each{ |qan|
          integer_quantity = (qan.unit.precision_coef * qan.value).round

          assert_in_delta integer_quantity, qan.unit.precision_coef * qan.value, 1e-10

          assert_equal integer_quantity, true_quantities[qan.unit_id]
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
          #assert_equal (true_quantities[vrp.units[index].id].nil? ? 0 : true_quantities[vrp.units[index].id]), qan_value
        }

        "Job killed" # Return "Job killed" to stop gracefully
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, Models::Vrp.create(prob), nil)
    end
  end
end
