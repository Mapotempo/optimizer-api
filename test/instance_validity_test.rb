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
    problem[:points] << {id: 'point_4', matrix_index: 4}

    vrp = FCT.create(problem)
    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_correctness_provided_matrix_indices)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_correctness_provided_matrix_indices)
    assert OptimizerWrapper::JSPRIT.inapplicable_solve?(vrp).include?(:assert_correctness_provided_matrix_indices)
  end

  def test_first_solution_acceptance_with_solvers
    problem = VRP.basic
    problem[:configuration][:preprocessing][:first_solution_strategy] = [1]

    vrp = FCT.create(problem)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_not_testing_several_heuristics)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_not_testing_several_heuristics)
  end

  def test_solver_needed
    problem = VRP.basic
    problem[:configuration][:resolution][:solver] = false

    vrp = FCT.create(problem)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(FCT.create(problem)).include? :assert_solver
    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_solver_if_not_periodic
  end

  def test_second_stage_allowed
    problem = VRP.basic
    problem[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'vehicle'
    },{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'work_day'
    }]

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_work_day_partitions_only_schedule
  end

  def test_second_stage_allowed_small_lapses
    problem = VRP.basic
    problem[:services].first[:visits_number] = 3
    problem[:services].first[:minimum_lapse] = 1
    problem[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'vehicle'
    },{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'work_day'
    }]

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_work_day_partitions_only_schedule
  end

  def test_assert_inapplicable_relations_with_vroom
    problem = VRP.basic
    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: [],
      linked_vehicle_ids: [],
      lapse: nil
    }]

    vrp = FCT.create(problem)
    assert !OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_no_relations)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_no_relations)

    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: ['vehicle_0'],
      linked_vehicle_ids: [],
      lapse: nil
    }]

    vrp = FCT.create(problem)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_no_relations)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_no_relations)
  end

  def test_assert_inapplicable_vroom_with_periodic_heuristic
    problem = VRP.basic
    problem[:configuration][:preprocessing][:use_periodic_heuristic] = true

    assert OptimizerWrapper::VROOM.inapplicable_solve?(FCT.create(problem)).include? :assert_no_planning_heuristic
  end

  def test_assert_inapplicable_routes_whith_vroom
    problem = VRP.basic
    problem[:routes] = [{
      mission_ids: []
    }]

    vrp = FCT.create(problem)
    assert !OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_no_routes)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_no_routes)

    problem[:routes] = [{
      mission_ids: ['service_1']
    }]
    vrp = FCT.create(problem)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_no_routes)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_no_routes)
  end

  def test_assert_inapplicable_for_vroom_if_vehicle_distance
    problem = VRP.basic
    problem[:vehicles].first[:distance] = 10

    vrp = FCT.create(problem)
    assert OptimizerWrapper::VROOM.inapplicable_solve?(vrp).include?(:assert_no_distance_limitation)
    assert !OptimizerWrapper::ORTOOLS.inapplicable_solve?(vrp).include?(:assert_no_distance_limitation)
  end
end
