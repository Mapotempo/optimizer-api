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

      p_v_d = {}
      vrp.points.each{ |pt| p_v_d[pt[:id]] = { days: [], vehicles: [] } }
      s.instance_variable_set(:@points_vehicles_and_days, p_v_d)
      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => {
            current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle_id: vrp.vehicles.first.id
          },
          7 => {
            current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle_id: vrp.vehicles.first.id
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
      p_v_d = {}
      vrp.points.each{ |pt| p_v_d[pt[:id]] = { days: [], vehicles: [] } }
      s.instance_variable_set(:@points_vehicles_and_days, p_v_d)
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle: vrp.vehicles.first.id
                                },
                                3 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle: vrp.vehicles.first.id
                                },
                                7 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle: vrp.vehicles.first.id
                                },
                                10 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0' }], vehicle: vrp.vehicles.first.id
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
      services_data = Marshal.load(File.binread('test/fixtures/add_missing_visits_services_data.bindump')) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@services_data, services_data)
      s.instance_variable_set(:@missing_visits, Marshal.load(File.binread('test/fixtures/add_missing_visits_missing_visits.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@candidate_services_ids, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_services_ids.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@ids_to_renumber, [])
      starting_with = s.instance_variable_get(:@uninserted).size
      s.send(:add_missing_visits)

      candidate_routes = s.instance_variable_get(:@candidate_routes)
      uninserted = s.instance_variable_get(:@uninserted)
      candidate_services_ids = s.instance_variable_get(:@candidate_services_ids)
      assert_equal vrp.visits, candidate_routes.sum{ |_v, d| d.sum{ |_day, route| route[:current_route].size } } +
                               uninserted.size +
                               candidate_services_ids.sum{ |id| s.instance_variable_get(:@services_data)[id][:visits_number] }
      assert starting_with >= s.instance_variable_get(:@uninserted).size

      all_ids = (uninserted.keys +
                 candidate_routes.collect{ |_v, d| d.collect{ |_day, route_day| route_day[:current_route].collect{ |stop| "#{stop[:id]}_#{stop[:number_in_sequence]}_#{services_data[stop[:id]][:visits_number]}" } } } +
                 candidate_services_ids.collect{ |id| (1..services_data[id][:visits_number]).collect{ |visit_index| "#{id}_#{visit_index}_#{services_data[id][:visits_number]}" } }).flatten
      assert_equal vrp.visits, all_ids.size
      assert_equal vrp.visits, all_ids.uniq.size
    end

    def test_clean_routes_with_position_requirement_never_first
      vrp = TestHelper.create(VRP.scheduling_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)

      vehicule = { matrix_id: vrp.vehicles.first.start_point.matrix_index }
      p_v_d = {}
      vrp.points.each{ |pt| p_v_d[pt[:id]] = { days: [], vehicles: [] } }
      s.instance_variable_set(:@points_vehicles_and_days, p_v_d)
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0', requirement: :neutral }, { id: 'service_2', point_id: 'point_0', requirement: :never_first }], vehicle: vehicule
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
      p_v_d = {}
      vrp.points.each{ |pt| p_v_d[pt[:id]] = { days: [], vehicles: [] } }
      s.instance_variable_set(:@points_vehicles_and_days, p_v_d)
      s.instance_variable_set(:@candidate_routes,
                              'vehicle_0' => {
                                0 => {
                                  current_route: [{ id: 'service_1', point_id: 'point_0', requirement: :never_last }, { id: 'service_2', point_id: 'point_0', requirement: :neutral }], vehicle: vehicule
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
      vrp = TestHelper.create(VRP.scheduling)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
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

    def test_empty_underfilled_routes
      vrp = VRP.lat_lon_scheduling
      vrp[:vehicles].each{ |v| v[:cost_fixed] = 2 }
      vrp[:services].each{ |s| s[:exclusion_cost] = 1 }
      vrp_to_solve = TestHelper.create(vrp)
      vrp_to_solve.vehicles = TestHelper.expand_vehicles(vrp_to_solve)
      s = Heuristics::Scheduling.new(vrp_to_solve)

      route_with_one = [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_two = route_with_one + [{ id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_three = route_with_two + [{ id: 'service_3', point_id: 'point_3', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_four = route_with_three + [{ id: 'service_4', point_id: 'point_4', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      candidate_route = {
        'vehicle_0' => {
          0 => { current_route: route_with_one, cost_fixed: 2, global_day_index: 0, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          1 => { current_route: route_with_two, cost_fixed: 2, global_day_index: 1, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          2 => { current_route: route_with_three, cost_fixed: 2, global_day_index: 2, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          3 => { current_route: route_with_four, cost_fixed: 2, global_day_index: 3, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] }
        }
      }

      # standard case :
      s.instance_variable_set(:@candidate_routes, candidate_route.deep_dup)
      s.send(:empty_underfilled)
      assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:current_route]
      (1..3).each{ |day|
        refute_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:current_route]
      }

      # partial assignment is false
      vrp[:configuration][:resolution][:allow_partial_assignment] = false
      vrp_to_solve = TestHelper.create(vrp)
      vrp_to_solve.vehicles = TestHelper.expand_vehicles(vrp_to_solve)
      s = Heuristics::Scheduling.new(vrp_to_solve)
      s.instance_variable_set(:@candidate_routes, candidate_route)
      s.send(:empty_underfilled)
      (0..3).each{ |day|
        assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:current_route]
      }

      # partial assignment is false with routes sorted differently
      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => { current_route: route_with_four, cost_fixed: 2, global_day_index: 3, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          1 => { current_route: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_3', point_id: 'point_3', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 2, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          2 => { current_route: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 1, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          3 => { current_route: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 0, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
        }
      )

      s.send(:empty_underfilled)
      (0..3).each{ |day|
        assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:current_route]
      }
    end

    def test_reaffecting_without_allow_partial_assignment
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:vehicles] = [vrp[:vehicles].first]
      vrp[:vehicles].first[:sequence_timewindows] = nil
      vrp[:vehicles].first[:timewindow] = { start: 28800, end: 54000 }
      vrp[:vehicles].first[:cost_fixed] = 3
      vrp[:services][0][:visits_number] = 7
      vrp[:services][0][:minimum_lapse] = 1
      vrp[:services][0][:maximum_lapse] = 1
      vrp[:services][1][:visits_number] = 3
      vrp[:services][1][:minimum_lapse] = 2
      vrp[:services][1][:maximum_lapse] = 3
      vrp[:services][1][:unavailable_visit_day_indices] = [3]
      vrp[:services].each{ |s| s[:exclusion_cost] = 1 }
      vrp[:configuration][:schedule][:range_indices] = { start: 0, end: 6 }
      vrp[:configuration][:resolution][:allow_partial_assignment] = false
      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)

      s.instance_variable_set(:@candidate_routes, Marshal.load(File.binread('test/fixtures/reaffecting_without_allow_partial_assignment_routes.bindump'))) # rubocop: disable Security/MarshalLoad

      sequences = s.send(:deduce_sequences, 'service_2', 3, [0, 1, 2, 4, 5, 6])
      assert_equal [[0, 2, 4], [0, 2, 5], [1, 4, 6], [2, 4, 6], []], sequences
      s.send(:reaffect, [['service_2', 3]])
      new_routes = s.instance_variable_get(:@candidate_routes)
      # [1, 4, 6] is the only combination such that every day is available for service_2,
      # and none of these day's route is empty
      [1, 4, 6].each{ |day|
        assert(new_routes['vehicle_0'][day][:current_route].any?{ |stop| stop[:id]&.include?('service_2') })
      }

      sequences = s.send(:deduce_sequences, 'service_1', 7, [0, 1, 2, 3, 4, 5, 6])
      assert_equal [[0, 1, 2, 3, 4, 5, 6]], sequences
      s.send(:reaffect, [['service_1', 7]])
      assert((0..6).all?{ |day| new_routes['vehicle_0'][day][:current_route].any?{ |stop| stop[:id]&.include?('service_1') } })
      s.send(:empty_underfilled)
      new_routes = s.instance_variable_get(:@candidate_routes)
      # this is room enough to assign every visit of service_1,
      # but that would violate minimum stop per route expected
      assert((0..6).none?{ |day| new_routes['vehicle_0'][day][:current_route].any?{ |stop| stop[:id]&.include?('service_1') } })
    end

    def test_compute_latest_authorized_day
      [10, 14].each{ |visits_number|
        vrp = TestHelper.create(VRP.scheduling)
        vrp.schedule_range_indices[:end] = 13

        if visits_number == 10
          vrp.vehicles.first.sequence_timewindows = (0..4).collect{ |day_index|
            Models::Timewindow.new(start: 0, end: 20, day_index: day_index)
          }
          vrp.vehicles.first.timewindow = nil
        end
        vrp.services.first.visits_number = visits_number
        vrp.services.first.minimum_lapse = 1

        periodic = Interpreters::PeriodicVisits.new(vrp)
        periodic.send(:compute_possible_days, vrp)
        assert_equal 0, vrp.services.first.last_possible_days.first, "There are #{visits_number} working days, hence a service with #{visits_number} visits can only start at day 0"
      }
    end
  end
end
