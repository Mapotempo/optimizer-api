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

      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)
      assert_empty s.instance_variable_get(:@uninserted)
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

      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)
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

      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)
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
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
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
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 7, data_services['service_1'][:heuristic_period]

      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => {
            current_route: [{ id: 'service_1' }], vehicle_id: vrp.vehicles.first.id
          },
          7 => {
            current_route: [{ id: 'service_1' }], vehicle_id: vrp.vehicles.first.id
          }
        }
      )
      s.send(:clean_routes, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].first[:id], 'vehicle_0')
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
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
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
      s.send(:clean_routes, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].first[:id], 'vehicle_0')
      assert(s.instance_variable_get(:@candidate_routes).all?{ |_key, data| data.all?{ |_k, d| d[:current_route].empty? } })
    end

    def test_add_missing_visits
      vrp = TestHelper.load_vrp(self, fixture_file: 'scheduling_with_post_process')
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
      s.instance_variable_set(:@candidate_routes, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_routes.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@uninserted, Marshal.load(File.binread('test/fixtures/add_missing_visits_uninserted.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@missing_visits, Marshal.load(File.binread('test/fixtures/add_missing_visits_missing_visits.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@candidate_services_ids, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_services_ids.bindump'))) # rubocop: disable Security/MarshalLoad
      starting_with = s.instance_variable_get(:@uninserted).size
      s.add_missing_visits

      candidate_routes = s.instance_variable_get(:@candidate_routes)
      uninserted = s.instance_variable_get(:@uninserted)
      candidate_services_ids = s.instance_variable_get(:@candidate_services_ids)
      assert_equal vrp.visits, candidate_routes.collect{ |_v, d| d.collect{ |_day, route| route[:current_route].size } }.flatten.sum +
                               uninserted.size +
                               candidate_services_ids.collect{ |id| s.instance_variable_get(:@services_data)[id][:nb_visits] }.sum
      assert starting_with >= s.instance_variable_get(:@uninserted).size
    end

    def test_clean_routes_with_position_requirement_never_first
      vrp = TestHelper.create(VRP.scheduling_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)

      vehicule = { matrix_id: vrp.vehicles.first.start_point.matrix_index }
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1', requirement: :neutral }, { id: 'service_2', requirement: :never_first }], vehicle: vehicule
                                }
                              })
      assert_equal vrp.services.size, s.instance_variable_get(:@candidate_services_ids).size
      s.instance_variable_get(:@candidate_services_ids).delete('service_1')
      s.instance_variable_get(:@candidate_services_ids).delete('service_2')
      assert_equal vrp.services.size - 2, s.instance_variable_get(:@candidate_services_ids).size
      s.send(:clean_routes, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].first[:id], 'vehicle_0')
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].size
      assert(s.instance_variable_get(:@uninserted).none?{ |id, _info| id.include?('service_2') })
      assert_equal vrp.services.size - 1, s.instance_variable_get(:@candidate_services_ids).size # service 2 can be assigned again
    end

    def test_clean_routes_with_position_requirement_never_last
      vrp = TestHelper.create(VRP.scheduling_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)

      vehicule = { matrix_id: vrp.vehicles.first[:start_point][:matrix_index] }
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1', requirement: :never_last }, { id: 'service_2', requirement: :neutral }], vehicle: vehicule
                                }
                              })
      s.instance_variable_get(:@candidate_services_ids).delete('service_1')
      s.instance_variable_get(:@candidate_services_ids).delete('service_2')
      s.send(:clean_routes, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route][1][:id], 'vehicle_0')
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route].size
      assert_equal vrp.services.size - 1, s.instance_variable_get(:@candidate_services_ids).size # service 1 can be assigned again
    end

    def test_check_validity
      vrp = VRP.scheduling_seq_timewindows
      vrp[:services][0][:activity][:timewindows] = [{ start: 100, end: 300 }]
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)
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
                                  tw_start: 0,
                                  tw_end: 400
                                }
                            })
      assert_raises OptimizerWrapper::SchedulingHeuristicError do
        s.check_solution_validity
      end
    end

    def test_compute_next_insertion_cost_when_activities
      vrp = TestHelper.create(VRP.basic)
      vrp.schedule_range_indices = { start: 0, end: 365 }
      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)

      service = { id: 'service_2', point_id: 'point_2', duration: 0 }
      timewindow = { start_time: 47517.6, arrival_time: 48559.4, final_time: 48559.4, setup_duration: 0 }
      route_data = { current_route: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 47517.6, end: 47517.6, considered_setup_duration: 0, activity: 0, duration: 0 },
                                     { id: 'service_with_activities', point_id: 'point_1', start: 47517.6, arrival: 47517.6, end: 47517.6, considered_setup_duration: 0, activity: 0, duration: 0 }],
                     tw_end: 100000, router_dimension: :time, matrix_id: 'm1' }
      s.instance_variable_set(:@services_data, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_services_data.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_matrices.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@indices, Marshal.load(File.binread('test/fixtures/compute_next_insertion_cost_when_activities_indices.bindump'))) # rubocop: disable Security/MarshalLoad

      s.send(:insertion_cost_with_tw, timewindow, route_data, service, 1)

      assert_equal 0, route_data[:current_route].find{ |stop| stop[:id].include?('with_activities') }[:activity]
      assert_equal 'point_1', route_data[:current_route].find{ |stop| stop[:id].include?('with_activities') }[:point_id]
    end

    def test_compute_shift_two_potential_tws
      vrp = VRP.scheduling
      s = Heuristics::Scheduling.new(TestHelper.create(vrp))
      s.instance_variable_set(:@services_data, Marshal.load(File.binread('test/fixtures/compute_shift_services_data.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/compute_shift_matrices.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@indices, '1028167' => 0, 'endvehicule8' => 270)
      s.instance_variable_set(:@same_point_day, true)
      route_data = Marshal.load(File.binread('test/fixtures/compute_shift_route_data.bindump')) # rubocop: disable Security/MarshalLoad
      potential_tws = Marshal.load(File.binread('test/fixtures/compute_shift_potential_tws.bindump')) # rubocop: disable Security/MarshalLoad

      service_to_plan = '1028167_CLI_84_1AB'
      service_data = s.instance_variable_get(:@services_data)[service_to_plan]
      route_data[:current_route] = [
        { id: '1028167_INI_84_1AB', point_id: '1028167', start: 21600, arrival: 21700, end: 22000, considered_setup_duration: 120, activity: 0 }
      ]
      route_data[:current_route][0][:point_id] = service_data[:points_ids][0]
      times_back_to_depot = potential_tws.collect{ |tw|
        _next_a, _accepted, _shift, back_depot = s.send(:insertion_cost_with_tw, tw, route_data, { id: service_to_plan, point_id: service_data[:points_ids][0], duration: 876 }, 0)
        back_depot
      }
      assert_operator times_back_to_depot[0], :!=, times_back_to_depot[1]
    end

    def test_positions_provided
      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)

      assert_equal [0], s.compute_consistent_positions_to_insert(:always_first, 'unknown_point', [])
      assert_equal [0, 1], s.compute_consistent_positions_to_insert(:always_first, 'unknown_point', [{ requirement: :always_first, point_id: 'point' },
                                                                                                     { requirement: :neutral, point_id: 'point' }])
      assert_equal [0], s.compute_consistent_positions_to_insert(:always_first, 'unknown_point', [{ requirement: :always_last, point_id: 'point' }])
      assert_equal [0, 1, 2, 3], s.compute_consistent_positions_to_insert(:always_first, 'unknown_point', [{ requirement: :always_first, point_id: 'point' },
                                                                                                           { requirement: :never_middle, point_id: 'point' },
                                                                                                           { requirement: :always_first, point_id: 'point' },
                                                                                                           { requirement: :neutral, point_id: 'point' },
                                                                                                           { requirement: :neutral, point_id: 'point' },
                                                                                                           { requirement: :always_last, point_id: 'point' }])

      assert_equal [], s.compute_consistent_positions_to_insert(:always_middle, 'unknown_point', [])
      assert_equal [1], s.compute_consistent_positions_to_insert(:always_middle, 'unknown_point', [{ requirement: :always_first, point_id: 'point' },
                                                                                                   { requirement: :always_last, point_id: 'point' }])
      assert_equal [1], s.compute_consistent_positions_to_insert(:always_middle, 'unknown_point', [{ requirement: :neutral, point_id: 'point' },
                                                                                                   { requirement: :neutral, point_id: 'point' }])
      assert_equal [1, 2], s.compute_consistent_positions_to_insert(:always_middle, 'unknown_point', [{ requirement: :neutral, point_id: 'point' },
                                                                                                      { requirement: :always_middle, point_id: 'point' },
                                                                                                      { requirement: :neutral, point_id: 'point' }])

      assert_equal [0], s.compute_consistent_positions_to_insert(:always_last, 'unknown_point', [])
      assert_equal [1], s.compute_consistent_positions_to_insert(:always_last, 'unknown_point', [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [2, 3, 4, 5], s.compute_consistent_positions_to_insert(:always_last, 'unknown_point', [{ requirement: :neutral, point_id: 'point' },
                                                                                                          { requirement: :neutral, point_id: 'point' },
                                                                                                          { requirement: :always_last, point_id: 'point' },
                                                                                                          { requirement: :always_last, point_id: 'point' },
                                                                                                          { requirement: :always_last, point_id: 'point' }])

      assert_equal [], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [])
      assert_equal [1], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [1], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [{ requirement: :always_last, point_id: 'point' }])
      assert_equal [1], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [{ requirement: :neutral, point_id: 'point' },
                                                                                                 { requirement: :always_last, point_id: 'point' }])
      assert_equal [1, 2], s.compute_consistent_positions_to_insert(:never_first, 'unknown_point', [{ requirement: :always_first, point_id: 'point' },
                                                                                                    { requirement: :neutral, point_id: 'point' },
                                                                                                    { requirement: :always_last, point_id: 'point' }])

      assert_equal [0], s.compute_consistent_positions_to_insert(:never_middle, 'unknown_point', [])
      assert_equal [0, 1], s.compute_consistent_positions_to_insert(:never_middle, 'unknown_point', [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [0, 1, 3], s.compute_consistent_positions_to_insert(:never_middle, 'unknown_point', [{ requirement: :always_first, point_id: 'point' },
                                                                                                        { requirement: :neutral, point_id: 'point' },
                                                                                                        { requirement: :neutral, point_id: 'point' }])

      assert_equal [], s.compute_consistent_positions_to_insert(:never_last, 'unknown_point', [])
      assert_equal [], s.compute_consistent_positions_to_insert(:never_last, 'unknown_point', [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [0], s.compute_consistent_positions_to_insert(:never_last, 'unknown_point', [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [0], s.compute_consistent_positions_to_insert(:never_last, 'unknown_point', [{ requirement: :always_last, point_id: 'point' }])

      # with point at same location :
      assert_equal [2, 3], s.compute_consistent_positions_to_insert(:always_middle, ['same_point'], [{ requirement: :always_first, point_id: 'point' },
                                                                                                     { requirement: :neutral, point_id: 'point' },
                                                                                                     { requirement: :neutral, point_id: 'same_point' },
                                                                                                     { requirement: :neutral, point_id: 'point' }])
    end

    def test_insertion_cost_with_tw_choses_best_value
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Heuristics::Scheduling.new(vrp)

      s.instance_variable_set(:@services_data, 'service_with_activities' => { nb_activities: 2,
                                                                              setup_durations: [0, 0],
                                                                              durations: [0, 0],
                                                                              points_ids: ['point_2', 'point_10'],
                                                                              tws_sets: [[], []] })

      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/chose_best_value_matrices.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@indices, Marshal.load(File.binread('test/fixtures/chose_best_value_indices.bindump'))) # rubocop: disable Security/MarshalLoad

      timewindow = { start_time: 0, arrival_time: 3807, final_time: 3807, setup_duration: 0 }
      route_data = { tw_end: 10000, start_point_id: 'point_0', end_point_id: 'point_0', matrix_id: 'm1',
                     current_route: [{ id: 'service_with_activities', point_id: 'point_10', start: 0, arrival: 1990, end: 1990, considered_setup_duration: 0, activity: 1 }] }
      service = { id: 'service_3', point_id: 'point_3', duration: 0 }

      set = s.send(:insertion_cost_with_tw, timewindow, route_data, service, 0)
      assert set.last < 10086, "#{set.last} should be the best value among all activities' value"
    end
  end
end
