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
  def test_reject_if_relation
    problem = VRP.scheduling
    problem[:relations] = {
      type: 'vehicle_group_duration_on_weeks',
      lapse: '2',
      linked_vehicle_ids: ['vehicle_0']
    }

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_relation_with_scheduling_heuristic
  end

  def test_reject_if_vehicle_shift_preference
    problem = VRP.scheduling
    problem[:vehicles].first[:shift_preference] = 'force_start'

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_wrong_vehicle_shift_preference_with_heuristic
  end

  def test_reject_if_vehicle_overall_duration
    problem = VRP.scheduling
    problem[:vehicles].first[:overall_duration] = 10

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_vehicle_overall_duration_if_heuristic
  end

  def test_reject_if_vehicle_distance
    problem = VRP.scheduling
    problem[:vehicles].first[:distance] = 10

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_vehicle_distance_if_heuristic
  end

  def test_reject_if_vehicle_skills
    problem = VRP.scheduling
    problem[:vehicles].first[:skills] = ['skill']
    problem[:services].first[:skills] = ['skill']

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_skills_if_heuristic
  end

  def test_reject_if_vehicle_free_approach_return
    problem = VRP.scheduling
    problem[:vehicles].first[:free_approach] = true

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_vehicle_free_approach_or_return_if_heuristic
  end

  def test_reject_if_service_exclusion_cost
    problem = VRP.scheduling
    problem[:services].first[:exclusion_cost] = 1

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_service_exclusion_cost_if_heuristic
  end

  def test_reject_if_vehicle_limit
    problem = VRP.scheduling
    problem[:configuration][:resolution][:vehicle_limit] = 1

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).empty?

    problem[:vehicles] *= 3

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_vehicle_limit_if_heuristic
  end

  def test_reject_if_no_vehicle_tw_but_heuristic
    problem = VRP.scheduling
    problem[:vehicles].first[:timewindow] = nil

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_vehicle_tw_if_schedule
  end

  def test_reject_if_periodic_heuristic_without_schedule
    problem = VRP.scheduling
    problem[:configuration][:schedule] = nil

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_if_periodic_heuristic_then_schedule
  end

  def test_no_solution_evaluation
    problem = VRP.scheduling
    problem[:configuration][:resolution][:evaluate_only] = true

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_no_scheduling_if_evaluation
  end

  def test_no_activities
    problem = VRP.scheduling
    problem[:services].first[:activity] = nil
    problem[:services].first[:activities] = [{
      point_id: 'point_1'
    }, {
      point_id: 'point_2'
    }]

    assert OptimizerWrapper::ORTOOLS.inapplicable_solve?(FCT.create(problem)).include? :assert_only_one_activity_with_scheduling_heuristic
  end
end
