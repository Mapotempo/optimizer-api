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
  if !ENV['SKIP_SCHEDULING']
    def test_reject_if_no_heuristic_neither_first_sol_strategy
      problem = VRP.scheduling
      problem[:configuration][:preprocessing][:first_solution_strategy] = []
      problem[:configuration][:resolution][:solver_parameter] = -1

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_solver_if_not_periodic
    end

    def test_reject_if_partial_assignement
      problem = VRP.scheduling
      problem[:configuration][:resolution][:allow_partial_assignment] = false
      problem[:configuration][:preprocessing][:first_solution_strategy] = nil

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_allow_partial_if_no_heuristic
    end

    def test_reject_if_same_point_day
      problem = VRP.scheduling
      problem[:configuration][:resolution][:same_point_day] = true
      problem[:configuration][:preprocessing][:first_solution_strategy] = nil

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_same_point_day_if_no_heuristic
    end

    def test_reject_if_vehicle_shift_preference
      problem = VRP.scheduling
      problem[:vehicles].first[:shift_preference] = 'force_start'

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_wrong_vehicle_shift_preference_with_heuristic
    end

    def test_reject_if_vehicle_overall_duration
      problem = VRP.scheduling
      problem[:vehicles].first[:overall_duration] = 10

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_vehicle_overall_duration_if_heuristic
    end

    def test_reject_if_vehicle_distance
      problem = VRP.scheduling
      problem[:vehicles].first[:distance] = 10

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_vehicle_distance_if_heuristic
    end

    def test_reject_if_vehicle_skills
      problem = VRP.scheduling
      problem[:vehicles].first[:skills] = [['skill']]
      problem[:services].first[:skills] = ['skill']

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_skills_if_heuristic
    end

    def test_reject_if_vehicle_free_approach_return
      problem = VRP.scheduling
      problem[:vehicles].first[:free_approach] = true

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_vehicle_free_approach_or_return_if_heuristic
    end

    def test_reject_if_vehicle_limit
      problem = VRP.scheduling
      problem[:configuration][:resolution][:vehicle_limit] = 1

      assert_empty OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem))

      problem[:vehicles] *= 3

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_vehicle_limit_if_heuristic
    end

    def test_reject_if_no_vehicle_tw_but_heuristic
      problem = VRP.scheduling
      problem[:vehicles].first[:timewindow] = nil

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_vehicle_tw_if_schedule
    end

    def test_reject_if_periodic_heuristic_without_schedule
      problem = VRP.scheduling
      problem[:configuration][:schedule] = nil

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_if_periodic_heuristic_then_schedule
    end

    def test_no_solution_evaluation
      problem = VRP.scheduling
      problem[:configuration][:resolution][:evaluate_only] = true

      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_scheduling_if_evaluation
    end

    def test_assert_route_date_or_indice_if_periodic
      problem = VRP.scheduling
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1', 'service_3']
      }]
      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_route_date_or_indice_if_periodic

      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1', 'service_3']
      }]
      refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_route_date_or_indice_if_periodic
    end

    def test_assert_missions_in_route_exist
      problem = VRP.scheduling
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1', 'service_3']
      }]
      refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_missions_in_routes_do_exist

      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_111', 'service_3']
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(problem)
      end
    end

    def test_not_too_many_visits_provided_in_route
      problem = VRP.scheduling
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1']
      }]
      refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_not_too_many_visits_in_route

      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1', 'service_1']
      }]
      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_not_too_many_visits_in_route
    end

    def test_reject_if_periodic_route_without_periodic_heuristic
      problem = VRP.scheduling
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1']
      }]
      refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_route_if_schedule_without_periodic_heuristic

      problem[:configuration][:preprocessing][:first_solution_strategy] = []
      assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_no_route_if_schedule_without_periodic_heuristic
    end

    def test_same_point_day_authorized
      vrp = VRP.scheduling
      reference_point = vrp[:services].first[:activity][:point_id]
      vrp[:services].first[:visits_number] = 3
      vrp[:services].first[:minimum_lapse] = 3
      vrp[:services].first[:maximum_lapse] = 3
      vrp[:services] << {
        id: 'last_service',
        visits_number: 2,
        minimum_lapse: 6,
        maximum_lapse: 6,
        activity: {
          point_id: reference_point
        }
      }
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:configuration][:schedule][:range_indices][:end] = 10
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert result # there exist a common_divisor

      vrp[:services].last[:minimum_lapse] = vrp[:services].last[:maximum_lapse] = 7
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      end
    end
  end
end
