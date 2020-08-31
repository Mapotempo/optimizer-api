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

class InstanceValidityTest < Minitest::Test
  def test_incorrect_matrix_indices
    problem = VRP.basic
    problem[:points] << { id: 'point_4', matrix_index: 4 }

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_correctness_provided_matrix_indices
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_correctness_provided_matrix_indices
    assert_includes OptimizerWrapper.config[:services][:jsprit].inapplicable_solve?(vrp), :assert_correctness_provided_matrix_indices
  end

  def test_first_solution_acceptance_with_solvers
    problem = VRP.basic
    problem[:configuration][:preprocessing][:first_solution_strategy] = [1]

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_first_solution_strategy
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_first_solution_strategy
  end

  def test_solver_needed
    problem = VRP.basic
    problem[:configuration][:resolution][:solver] = false

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_solver
    assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_solver_if_not_periodic
  end

  def test_assert_inapplicable_relations_with_vroom
    problem = VRP.basic
    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: [],
      linked_vehicle_ids: [],
      lapse: nil
    }]

    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_relations
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_relations

    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: ['vehicle_0'],
      linked_vehicle_ids: [],
      lapse: nil
    }]

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_relations
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_relations
  end

  def test_assert_inapplicable_vroom_with_periodic_heuristic
    problem = VRP.scheduling

    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(TestHelper.create(problem)), :assert_no_planning_heuristic
  end

  def test_assert_applicable_for_vroom_if_initial_routes
    problem = VRP.basic
    problem[:routes] = [{
      mission_ids: ['service_1']
    }]
    vrp = TestHelper.create(problem)
    assert_empty OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp)
  end

  def test_assert_inapplicable_for_vroom_if_vehicle_distance
    problem = VRP.basic
    problem[:vehicles].first[:distance] = 10

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_distance_limitation
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_distance_limitation
  end
end
