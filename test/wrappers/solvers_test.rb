# Copyright © Mapotempo, 2021
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

class Wrappers::SolversTest < Minitest::Test
  def test_reject_if_no_heuristic_neither_first_sol_strategy
    problem = VRP.periodic
    problem[:configuration][:preprocessing][:first_solution_strategy] = []
    problem[:configuration][:resolution][:solver] = false

    assert_includes OptimizerWrapper::VROOM.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_solver_if_not_periodic
    assert_includes OptimizerWrapper::ORTOOLS.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_solver_if_not_periodic
  end

  def test_reject_if_partial_assignement
    problem = VRP.periodic
    problem[:configuration][:resolution][:allow_partial_assignment] = false
    problem[:configuration][:preprocessing][:first_solution_strategy] = nil

    assert_includes OptimizerWrapper::VROOM.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_allow_partial_if_no_heuristic
    assert_includes OptimizerWrapper::ORTOOLS.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_allow_partial_if_no_heuristic
  end

  def test_reject_if_same_point_day
    problem = VRP.periodic
    problem[:configuration][:resolution][:same_point_day] = true
    problem[:configuration][:preprocessing][:first_solution_strategy] = nil

    assert_includes OptimizerWrapper::VROOM.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_same_point_day_if_no_heuristic
    assert_includes OptimizerWrapper::ORTOOLS.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_same_point_day_if_no_heuristic
  end

  def test_reject_if_periodic_route_without_periodic_heuristic
    problem = VRP.periodic
    problem[:routes] = [{
      vehicle_id: 'vehicle_0',
      indice: 0,
      mission_ids: ['service_1']
    }]
    problem[:configuration][:preprocessing] = nil

    assert_includes OptimizerWrapper::VROOM.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_route_if_schedule_without_periodic_heuristic
    assert_includes OptimizerWrapper::ORTOOLS.inapplicable_solve?(TestHelper.create(problem)),
                    :assert_no_route_if_schedule_without_periodic_heuristic
  end
end
