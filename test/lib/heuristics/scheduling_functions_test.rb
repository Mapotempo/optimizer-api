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

class HeuristicTest < Minitest::Test
  if !ENV['SKIP_SCHEDULING']
    def test_compute_best_common_tw_when_empty_tw
      vrp = VRP.scheduling_seq_timewindows
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:services][1][:activity][:point_id] = 'point_1'
      vrp = TestHelper.create(vrp)

      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      s.collect_services_data(vrp)
      assert s.instance_variable_get(:@uninserted).empty?
    end

    def test_compute_best_common_tw_when_conflict_tw
      vrp = VRP.scheduling_seq_timewindows
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:services][0][:activity][:timewindows] = [{
        start: 0,
        end: 10
      }]
      vrp[:services][1][:activity][:point_id] = 'point_1'
      vrp[:services][1][:activity][:timewindows] = [{
        start: 11,
        end: 20
      }]
      vrp = TestHelper.create(vrp)

      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      s.collect_services_data(vrp)
      assert_equal 2, s.instance_variable_get(:@uninserted).size
    end

    def test_compute_best_common_tw_when_no_conflict_tw
      vrp = VRP.scheduling_seq_timewindows
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:services][0][:activity][:timewindows] = [{
        start: 0,
        end: 10
      }]
      vrp[:services][1][:activity][:point_id] = 'point_1'
      vrp[:services][1][:activity][:timewindows] = [{
        start: 5,
        end: 20
      }]
      vrp = TestHelper.create(vrp)

      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      s.collect_services_data(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert(data_services['service_1'][:tw].all?{ |tw| tw[:start] == 5 && tw[:end] == 10 })
      assert_equal 0, s.instance_variable_get(:@uninserted).size
    end

    def test_solve_tsp_with_one_point
      vrp = VRP.scheduling
      vrp[:points] = [vrp[:points].first]
      vrp[:services] = [vrp[:services].first]
      vrp[:services].first[:activity][:point_id] = vrp[:points].first[:id]

      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      assert_equal 1, s.solve_tsp(vrp).size
    end

    def test_compute_service_lapse
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:visits_number] = 1
      vrp[:services][0][:minimum_lapse] = 10

      vrp[:services][1][:visits_number] = 2
      vrp[:services][1][:minimum_lapse] = 7

      vrp[:services][2][:visits_number] = 2
      vrp[:services][2][:minimum_lapse] = 10

      vrp[:services][3][:visits_number] = 2
      vrp[:services][3][:minimum_lapse] = 6
      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      s.collect_services_data(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 6, data_services.size
      assert_nil data_services['service_1'][:heuristic_period]
      assert_equal 7, data_services['service_2'][:heuristic_period]
      assert_equal 14, data_services['service_3'][:heuristic_period]
      assert_equal 7, data_services['service_4'][:heuristic_period]
    end

    def test_clean_routes
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:visits_number] = 2
      vrp[:services][0][:minimum_lapse] = 7

      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 10, shift: 0 })
      s.collect_services_data(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 7, data_services['service_1'][:heuristic_period]

      vehicule = { matrix_id: vrp.vehicles.first[:start_point][:matrix_index] }
      s.instance_variable_set(:@planning,
        'vehicle_0' => {
          0 => {
            services: [{ id: 'service_1' }], vehicle: vehicule
          },
          7 => {
            services: [{ id: 'service_1' }], vehicle: vehicule
          }
      })
      s.clean_routes(s.instance_variable_get(:@planning)['vehicle_0'][0][:services].first, 'vehicle_0')
      assert_equal 0, s.instance_variable_get(:@planning)['vehicle_0'][0][:services].size
      assert_equal 0, s.instance_variable_get(:@planning)['vehicle_0'][7][:services].size
    end

    def test_clean_routes_small_lapses
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:visits_number] = 4
      vrp[:services][0][:minimum_lapse] = 3
      vrp[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 14
        }
      }

      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 14, shift: 0 })
      s.collect_services_data(vrp)
      vehicule = { matrix_id: vrp.vehicles.first[:start_point][:matrix_index] }
      s.instance_variable_set(:@planning,
                              'vehicle_0' => {
                                0 => {
                                  services: [{ id: 'service_1' }], vehicle: vehicule
                                },
                                3 => {
                                  services: [{ id: 'service_1' }], vehicle: vehicule
                                },
                                7 => {
                                  services: [{ id: 'service_1' }], vehicle: vehicule
                                },
                                10 => {
                                  services: [{ id: 'service_1' }], vehicle: vehicule
                                }
                            })
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 3, data_services['service_1'][:heuristic_period]
      s.clean_routes(s.instance_variable_get(:@planning)['vehicle_0'][0][:services].first, 'vehicle_0')
      assert(s.instance_variable_get(:@planning).all?{ |_key, data| data.all?{ |_k, d| d[:services].empty? } })
    end

    def test_check_validity
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:activity][:timewindows] = [{ start: 100, end: 300 }]
      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], { start: 0, end: 14, shift: 0 })
      s.collect_services_data(vrp)
      vehicule = { matrix_id: vrp.vehicles.first[:start_point][:matrix_index], tw_start: 0, tw_end: 400 }
      s.instance_variable_set(:@planning,
                              'vehicle_0' => {
                                0 => {
                                  services: [{
                                    id: 'service_1',
                                    start: 50,
                                    arrival: 100,
                                    end: 350,
                                    considered_setup_duration: 0
                                  }],
                                  vehicle: vehicule
                                }
                            })
      assert s.check_solution_validity

      s.instance_variable_set(:@duration_in_tw, true)
      assert_raises OptimizerWrapper::SchedulingHeuristicError do
        s.check_solution_validity
      end

      s.instance_variable_set(:@planning,
                              'vehicle_0' => {
                                0 => {
                                  services: [{
                                    id: 'service_1',
                                    start: 50,
                                    arrival: 60,
                                    end: 80,
                                    considered_setup_duration: 0
                                  }],
                                  vehicle: vehicule
                                }
                            })
      assert_raises OptimizerWrapper::SchedulingHeuristicError do
        s.check_solution_validity
      end
    end
  end
end
