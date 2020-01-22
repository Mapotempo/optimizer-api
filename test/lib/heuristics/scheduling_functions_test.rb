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

      s = Heuristics::Scheduling.new(vrp, [], start: 0, end: 10, shift: 0)
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

      s = Heuristics::Scheduling.new(vrp, [], start: 0, end: 10, shift: 0)
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

      s = Heuristics::Scheduling.new(vrp, [], start: 0, end: 10, shift: 0)
      data_services = s.instance_variable_get(:@services_data)
      assert(data_services['service_1'][:tws_sets].first.all?{ |tw| tw[:start] == 5 && tw[:end] == 10 })
      assert_equal 0, s.instance_variable_get(:@uninserted).size
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
      expanded_vehicles = TestHelper.easy_vehicle_expand(vrp.vehicles, vrp.schedule_indices)
      s = Heuristics::Scheduling.new(vrp, expanded_vehicles, start: 0, end: 10, shift: 0)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 6, data_services.size
      assert_nil data_services['service_1'][:heuristic_period]
      assert_equal 7, data_services['service_2'][:heuristic_period]
      assert_equal 10, data_services['service_3'][:heuristic_period]
      assert_equal 6, data_services['service_4'][:heuristic_period]
    end

    def test_clean_routes
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:visits_number] = 2
      vrp[:services][0][:minimum_lapse] = 7

      vrp = TestHelper.create(vrp)
      expanded_vehicles = TestHelper.easy_vehicle_expand(vrp.vehicles, vrp.schedule_indices)
      s = Heuristics::Scheduling.new(vrp, expanded_vehicles, start: 0, end: 10, shift: 0)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 7, data_services['service_1'][:heuristic_period]

      s.instance_variable_set(:@candidate_routes,
        'vehicle_0' => {
          0 => {
            current_route: [{ id: 'service_1' }], vehicle_id: vrp.vehicles.first.id
          },
          7 => {
            current_route: [{ id: 'service_1' }], vehicle_id: vrp.vehicles.first.id
          }
      })
      s.clean_routes(s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].first, 'vehicle_0')
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].size
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][7][:current_route].size
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
      expanded_vehicles = TestHelper.easy_vehicle_expand(vrp.vehicles, vrp.schedule_indices)
      s = Heuristics::Scheduling.new(vrp, expanded_vehicles, start: 0, end: 14, shift: 0)
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1' }], vehicle: vrp.vehicles.first.id
                                },
                                3 => {
                                  current_route: [{ id: 'service_1' }], vehicle: vrp.vehicles.first.id
                                },
                                7 => {
                                  current_route: [{ id: 'service_1' }], vehicle: vrp.vehicles.first.id
                                },
                                10 => {
                                  current_route: [{ id: 'service_1' }], vehicle: vrp.vehicles.first.id
                                }
                            })
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 3, data_services['service_1'][:heuristic_period]
      s.clean_routes(s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].first, 'vehicle_0')
      assert(s.instance_variable_get(:@candidate_routes).all?{ |_key, data| data.all?{ |_k, d| d[:current_route].empty? } })
    end

    def test_add_missing_visits
      vrp = TestHelper.load_vrp(self, fixture_file: 'scheduling_with_post_process')
      expanded = TestHelper.easy_vehicle_expand(vrp.vehicles, vrp.schedule_indices)
      s = Heuristics::Scheduling.new(vrp, expanded, start: 0, end: 365, shift: 0)
      s.instance_variable_set(:@candidate_routes, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_routes.dump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@uninserted, Marshal.load(File.binread('test/fixtures/add_missing_visits_uninserted.dump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@missing_visits, Marshal.load(File.binread('test/fixtures/add_missing_visits_missing_visits.dump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@candidate_services_ids, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_services_ids.dump'))) # rubocop: disable Security/MarshalLoad
      starting_with = s.instance_variable_get(:@uninserted).size
      s.add_missing_visits

      candidate_routes = s.instance_variable_get(:@candidate_routes)
      uninserted = s.instance_variable_get(:@uninserted)
      candidate_services_ids = s.instance_variable_get(:@candidate_services_ids)
      assert_equal vrp.visits, candidate_routes.collect{ |v, d| d.collect{ |_day, route| route[:current_route].size } }.flatten.sum +
                               uninserted.size +
                               candidate_services_ids.collect{ |id| s.instance_variable_get(:@services_data)[id][:nb_visits] }.sum
      assert starting_with >= s.instance_variable_get(:@uninserted).size
    end

    def test_check_validity
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:activity][:timewindows] = [{ start: 100, end: 300 }]
      vrp = TestHelper.create(vrp)
      s = Heuristics::Scheduling.new(vrp, [], start: 0, end: 14, shift: 0)
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{
                                    id: 'service_1',
                                    start: 50,
                                    arrival: 100,
                                    end: 350,
                                    considered_setup_duration: 0,
                                    activity: 0
                                  }],
                                  vehicle_id: vrp.vehicles.first.id,
                                  tw_start: 0,
                                  tw_end: 400
                                }
                            })
      assert s.check_solution_validity

      s.instance_variable_set(:@duration_in_tw, true)
      assert_raises OptimizerWrapper::SchedulingHeuristicError do
        s.check_solution_validity
      end

      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{
                                    id: 'service_1',
                                    start: 50,
                                    arrival: 60,
                                    end: 80,
                                    considered_setup_duration: 0,
                                    activity: 0
                                  }],
                                  vehicle_id: vrp.vehicles.first.id,
                                  tw_start: 0,
                                  tw_end: 400
                                }
                            })
      assert_raises OptimizerWrapper::SchedulingHeuristicError do
        s.check_solution_validity
      end
    end

    def test_compute_next_insertion_cost_when_activities
      s = Heuristics::Scheduling.new(TestHelper.create(VRP.basic), [], start: 0, end: 365, shift: 0)

      service = { id: 'service_2', point_id: 'point_2', duration: 0 }
      timewindow = { start_time: 47517.6, arrival_time: 48559.4, final_time: 48559.4, setup_duration: 0 }
      route_data = { current_route: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 47517.6, end: 47517.6, considered_setup_duration: 0, activity: 0, duration: 0 },
                                     { id: 'service_with_activities', point_id: 'point_1', start: 47517.6, arrival: 47517.6, end: 47517.6, considered_setup_duration: 0, activity: 0, duration: 0 }],
                     tw_end: 100000, router_dimension: :time, matrix_id: 'm1' }
      s.instance_variable_set(:@services_data, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_services_data.dump')))
      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_matrices.dump')))
      s.instance_variable_set(:@indices, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_indices.dump')))

      s.send(:insertion_cost_with_tw, timewindow, route_data, service, 1)

      assert_equal 0, route_data[:current_route].find{ |stop| stop[:id].include?('with_activities') }[:activity]
      assert_equal 'point_1', route_data[:current_route].find{ |stop| stop[:id].include?('with_activities') }[:point_id]
    end
  end
end
