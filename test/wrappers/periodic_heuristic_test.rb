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
  if !ENV['SKIP_PERIODIC']
    def test_reject_if_vehicle_shift_preference
      problem = VRP.periodic
      problem[:vehicles].first[:shift_preference] = 'force_start'

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_shift_preference_compatible_with_heuristic
    end

    def test_reject_if_vehicle_overall_duration
      problem = VRP.periodic
      problem[:vehicles].first[:overall_duration] = 10

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_vehicle_overall_duration
    end

    def test_reject_if_vehicle_distance
      problem = VRP.periodic
      problem[:vehicles].first[:distance] = 10

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_vehicle_distance
    end

    def test_reject_if_vehicle_skills
      problem = VRP.periodic
      problem[:vehicles].first[:skills] = [['skill']]
      problem[:services].first[:skills] = ['skill']

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_skills
    end

    def test_reject_if_vehicle_free_approach_return
      problem = VRP.periodic
      problem[:vehicles].first[:free_approach] = true

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_vehicle_free_approach_or_return
    end

    def test_reject_if_vehicle_limit
      problem = VRP.periodic
      problem[:configuration][:resolution][:vehicle_limit] = 1

      assert_empty OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem))

      problem[:vehicles] += [{
        id: 'vehicle_1',
        matrix_id: 'matrix_0'
      }]

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_vehicle_limit
    end

    def test_reject_if_no_vehicle_tw_but_heuristic
      problem = VRP.periodic
      problem[:vehicles].first[:timewindow] = nil

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_vehicle_tw
    end

    def test_no_solution_evaluation
      problem = VRP.periodic
      problem[:configuration][:resolution][:evaluate_only] = true

      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_no_evaluation
    end

    def test_assert_route_date_or_indice_if_periodic
      problem = VRP.periodic
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1', 'service_3']
      }]
      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_route_date_or_indice

      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1', 'service_3']
      }]
      refute_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_route_date_or_indice
    end

    def test_not_too_many_visits_provided_in_route
      problem = VRP.periodic
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_1']
      }]
      refute_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_not_too_many_visits_in_route

      problem[:routes].first[:mission_ids] << 'service_1'
      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(problem)),
                      :assert_not_too_many_visits_in_route
    end

    def test_reject_if_periodic_and_zones
      vrp = VRP.periodic
      vrp[:zones] = [{ id: 'zone', polygon: { type: 'Polygon', coordinates: [[[0.5, 48.5], [1.5, 48.5]]] }}]
      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(vrp)),
                      :assert_no_zones
    end

    def test_reject_if_periodic_and_empty_or_fills
      vrp = VRP.periodic
      assert_empty OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(vrp))

      vrp[:units] = [{ id: :unit, label: :kg }]
      vrp[:vehicles].first[:capacities] = [{ unit_id: :unit }]
      vrp[:services].first[:quantities] = [{ fill: true, unit_id: :unit }]
      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(vrp)),
                      :assert_no_empty_nor_fill_quantities

      vrp[:services].first[:quantities] = [{ empty: true, unit_id: :unit }]
      assert_includes OptimizerWrapper::PERIODIC_HEURISTIC.inapplicable_solve?(TestHelper.create(vrp)),
                      :assert_no_empty_nor_fill_quantities
    end
  end
end
