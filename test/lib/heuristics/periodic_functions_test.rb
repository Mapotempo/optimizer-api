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
  def get_assignment_data(routes, vrp, services_data = {}, points_data = {})
    vrp.services.each{ |element|
      services_data[element.id] = { days: [], vehicles: [], missing_visits: element.visits_number, unassigned_reasons: [] }
    }
    vrp.points.each{ |element|
      points_data[element.id] = { days: [], vehicles: [] }
    }

    seen = []
    routes.each{ |vehicle_id, vehicle_routes|
      vehicle_routes.each{ |day, route|
        route[:stops].each{ |stop|
          services_data[stop[:id]][:vehicles] |= [vehicle_id]
          services_data[stop[:id]][:days] |= [day]
          services_data[stop[:id]][:missing_visits] -= 1

          points_data[stop[:point_id]][:vehicles] |= [vehicle_id]
          points_data[stop[:point_id]][:days] |= [day]

          seen << [stop[:point_id], stop[:id]]
        }
      }
    }

    [services_data, points_data]
  end

  if !ENV['SKIP_PERIODIC']
    def test_compute_best_common_tw_when_empty_tw
      vrp = VRP.periodic_seq_timewindows
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:services][1][:activity][:point_id] = 'point_1'
      vrp = TestHelper.create(vrp)

      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)
      # Ensure no visit is unassigned :
      assert(s.instance_variable_get(:@services_assignment).none?{ |_id, data| data[:unassigned_reasons].any? })
    end

    def test_compute_best_common_tw_when_conflict_tw
      vrp = VRP.periodic_seq_timewindows
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10 }]
      vrp[:services][1][:activity][:point_id] = 'point_1'
      vrp[:services][1][:activity][:timewindows] = [{ start: 11, end: 20 }]
      vrp = TestHelper.create(vrp)

      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)
      assert_equal 2, (s.instance_variable_get(:@services_assignment).count{ |_id, data| data[:unassigned_reasons].any? })
    end

    def test_compute_best_common_tw_when_no_conflict_tw
      vrp = VRP.periodic_seq_timewindows
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
      s = Wrappers::PeriodicHeuristic.new(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert(data_services['service_1'][:tws_sets].first.all?{ |tw| tw[:start] == 5 && tw[:end] == 10 })
      assert(s.instance_variable_get(:@services_assignment).none?{ |_id, data| data[:unassigned_reasons].any? })
    end

    def test_compute_period
      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      vrp.services = [vrp.services.first]
      s = Wrappers::PeriodicHeuristic.new(vrp)
      [[1, 10], [2, 7], [2, 10], [2, 6]].each{ |visits_number, minimum_lapse|
        vrp.services.first.visits_number = visits_number
        vrp.services.first.minimum_lapse = minimum_lapse

        if visits_number > 1
          assert_equal minimum_lapse, s.send(:compute_period, vrp.services.first, false)
        else
          assert_nil s.send(:compute_period, vrp.services.first, false)
        end
      }
    end

    def test_compute_period_when_work_day_split
      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      [[2, 6, 10, 7], [3, 5, 9, 7], [3, 2, 4, nil]].each{ |visits_number, minimum_lapse, maximum_lapse, expected|
        vrp.services.first.visits_number = visits_number
        vrp.services.first.minimum_lapse = minimum_lapse
        vrp.services.first.maximum_lapse = maximum_lapse

        if expected
          assert_equal expected, s.send(:compute_period, vrp.services.first, true)
        else
          assert_nil s.send(:compute_period, vrp.services.first, true)
          assert_equal ['Vehicles have only one working day, no lapse will allow to affect more than one visit.'],
                       s.instance_variable_get(:@services_assignment)[vrp.services.first.original_id][:unassigned_reasons]
        end
      }
    end

    def test_one_working_day_per_vehicle_properly_computed
      vrp = TestHelper.create(VRP.periodic)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      vrp.services = [vrp.services.first] # in order to call compute_period only once per loop
      values = []

      [[[0] * 4, true], [[0] * 2 + [1] * 2, false]].each{ |day_indices, expected|
        Wrappers::PeriodicHeuristic.stub_any_instance(:compute_period, lambda{ |_service, one_working_day_per_vehicle|
          values << one_working_day_per_vehicle
          expected
        }) do
          vrp.vehicles.each_with_index{ |v, v_i|
            v.global_day_index = day_indices[v_i]
          }
          Wrappers::PeriodicHeuristic.new(vrp)
        end
      }

      assert_equal [true, false], values
    end

    def test_clean_stops
      vrp = VRP.periodic_seq_timewindows
      vrp[:services][0][:visits_number] = 2
      vrp[:services][0][:minimum_lapse] = 7

      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 7, data_services['service_1'][:heuristic_period]

      [0, 7].each{ |day|
        s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:stops] =
          [{ id: 'service_1', point_id: 'point_0' }]
      }
      s_a, p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)
      s.send(:clean_stops, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops].first[:id])
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops].size
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][7][:stops].size
    end

    def test_clean_stops_small_lapses
      vrp = VRP.periodic_seq_timewindows
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
      s = Wrappers::PeriodicHeuristic.new(vrp)
      [0, 3, 7, 10].each{ |day|
        s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:stops] =
          [{ id: 'service_1', point_id: 'point_0' }]
      }

      s_a, p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)
      data_services = s.instance_variable_get(:@services_data)
      assert_equal 3, data_services['service_1'][:heuristic_period]
      s.send(:clean_stops, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops].first[:id])
      assert(s.instance_variable_get(:@candidate_routes).all?{ |_key, data| data.all?{ |_k, d| d[:stops].empty? } })
    end

    def test_add_missing_visits
      vrp = TestHelper.load_vrp(self, fixture_file: 'periodic_with_post_process')
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      add_missing_visits_candidate_routes = Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_routes.bindump')) # rubocop: disable Security/MarshalLoad
      add_missing_visits_candidate_routes.each_value{ |vehicle| vehicle.each_value{ |route| route[:matrix_id] = vrp.vehicles.first.matrix_id } }
      s.instance_variable_set(:@candidate_routes, add_missing_visits_candidate_routes)
      services_data = Marshal.load(File.binread('test/fixtures/add_missing_visits_services_data.bindump')) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@services_data, services_data)
      s.instance_variable_set(:@services_assignment, Marshal.load(File.binread('test/fixtures/add_missing_visits_services_assignment.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@points_assignment, Marshal.load(File.binread('test/fixtures/add_missing_visits_points_assignment.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@candidate_services_ids, Marshal.load(File.binread('test/fixtures/add_missing_visits_candidate_services_ids.bindump'))) # rubocop: disable Security/MarshalLoad
      starting_with = s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] }
      s.send(:add_missing_visits)

      candidate_routes = s.instance_variable_get(:@candidate_routes)
      uninserted_number = s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] }
      assert_equal vrp.visits, candidate_routes.sum{ |_v, d| d.sum{ |_day, route| route[:stops].size } } +
                               uninserted_number
      assert starting_with > uninserted_number
      assert_equal vrp.visits,
                   candidate_routes.sum{ |_v_id, v_routes| v_routes.sum{ |_day, day_route| day_route[:stops].size } } +
                   s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] }
    end

    def test_clean_stops_with_position_requirement_never_first
      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => { stops: [{ id: 'service_1', point_id: 'point_0', requirement: :neutral },
                         { id: 'service_2', point_id: 'point_0', requirement: :never_first }], capacity: [] }
        })
      s_a, p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)
      s.instance_variable_get(:@candidate_services_ids).delete('service_1')
      s.instance_variable_get(:@candidate_services_ids).delete('service_2')
      assert_equal vrp.services.size - 2, s.instance_variable_get(:@candidate_services_ids).size
      s.send(:clean_stops, 'service_1')
      assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops]
      # service 2 can be assigned again :
      assert_empty(s.instance_variable_get(:@services_assignment)['service_2'][:unassigned_reasons])
      assert_equal vrp.services.size - 1, s.instance_variable_get(:@candidate_services_ids).size
    end

    def test_clean_stops_with_position_requirement_never_last
      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => { stops: [{ id: 'service_1', point_id: 'point_0', requirement: :never_last },
                         { id: 'service_2', point_id: 'point_0', requirement: :neutral }], capacity: [] }
        })
      s_a, p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)
      s.instance_variable_get(:@candidate_services_ids).delete('service_1')
      s.instance_variable_get(:@candidate_services_ids).delete('service_2')
      s.send(:clean_stops, 'service_2')
      # service 1 can be assigned again :
      assert_equal 0, s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops].size
      assert_equal vrp.services.size - 1, s.instance_variable_get(:@candidate_services_ids).size
    end

    def test_check_validity
      vrp = VRP.periodic_seq_timewindows
      vrp[:services][0][:visits_number] = 2
      vrp[:services][0][:activity][:timewindows] = [{ start: 100, end: 300 }]
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)
      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => {
            stops: [{ id: 'service_1', start: 50, arrival: 100, end: 350, considered_setup_duration: 0, activity: 0 }],
            tw_start: 0, tw_end: 400
          }
      })
      s.check_solution_validity # this is not expected to raise

      s.instance_variable_set(:@duration_in_tw, true)
      assert_raises OptimizerWrapper::PeriodicHeuristicError do
        s.check_solution_validity
      end

      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => {
            stops: [{ id: 'service_1', start: 50, arrival: 60, end: 80, considered_setup_duration: 0, activity: 0 }],
            tw_start: 0, tw_end: 400
          }
      })
      assert_raises OptimizerWrapper::PeriodicHeuristicError do
        s.check_solution_validity
      end
    end

    def test_check_consistent_generated_ids
      vrp = VRP.periodic_seq_timewindows
      vrp[:services].first[:visits_number] = 2
      vrp[:services] = [vrp[:services].first]
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)

      possible_cases = [[[1, 2], [], 0],
                        [[1], [2], 1],
                        [[], [1, 2], 2]]
      possible_cases.each{ |assigned_indices, unassigned_indices, missing_visits|
        s.instance_variable_get(:@services_assignment)['service_1'][:assigned_indices] = assigned_indices
        s.instance_variable_get(:@services_assignment)['service_1'][:unassigned_indices] = unassigned_indices
        s.instance_variable_get(:@services_assignment)['service_1'][:missing_visits] = missing_visits
        s.check_consistent_generated_ids # this should not raise
      }

      prohibited_cases = [[[1], [2]],
                          [[], [1, 1]],
                          [[1], [2, 3]],
                          [[1], []],
                          [[], [1]],
                          [[1], [1]],
                          [[-1], [1]]]
      prohibited_cases.each{ |assigned_indices, unassigned_indices|
        s.instance_variable_get(:@services_assignment)['service_1'][:assigned_indices] = assigned_indices
        s.instance_variable_get(:@services_assignment)['service_1'][:unassigned_indices] = unassigned_indices
        assert_raises OptimizerWrapper::PeriodicHeuristicError do
          s.check_consistent_generated_ids
        end
      }
    end

    def test_insertion_cost_with_tw
      vrp = TestHelper.create(VRP.lat_lon_periodic_two_vehicles)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      route_data = {
        matrix_id: 'm1', start_point_id: 'point_0', tw_start: 0, tw_end: 50000,
        stops: [{ id: 'service_1', point_id: 'point_1', activity: 0, start: 0, arrival: 4046, end: 4046, considered_setup_duration: 0, tw: [] }]
      }
      assert_equal [0, true, 32640, 36686],
                   s.send(:insertion_cost_with_tw, { start_time: 32793, arrival_time: 36000, final_time: 36000 },
                          route_data, { service_id: 'service_4', point_id: 'point_4', duration: 0 }, 0)

      # this function can choose to edit next service activity if it is better :
      s.instance_variable_get(:@services_data)['service_1'][:point_ids] = ['point_1', 'point_2']
      s.instance_variable_get(:@services_data)['service_1'][:tws_sets] = [[], []]
      s.instance_variable_get(:@services_data)['service_1'][:nb_activities] = 2
      s.instance_variable_get(:@services_data)['service_1'][:durations] = [0, 0]
      assert_equal [1, true, 31954, 36000],
                   s.send(:insertion_cost_with_tw, { start_time: 32793, arrival_time: 36000, final_time: 36000 },
                          route_data, { service_id: 'service_4', point_id: 'point_4', duration: 0, start: 32793, arrival: 36000, end: 36000 }, 0)
    end

    def test_insertion_cost_with_tw_choses_best_value
      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(:@services_data, 'service_with_activities' => { nb_activities: 2,
                                                                              setup_durations: [0, 0],
                                                                              durations: [0, 0],
                                                                              points_ids: ['point_2', 'point_10'],
                                                                              tws_sets: [[], []] })

      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/chose_best_value_matrices.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@indices, Marshal.load(File.binread('test/fixtures/chose_best_value_indices.bindump'))) # rubocop: disable Security/MarshalLoad

      timewindow = { start_time: 0, arrival_time: 3807, final_time: 3807, setup_duration: 0 }
      route_data = { tw_end: 10000, start_point_id: 'point_0', end_point_id: 'point_0', matrix_id: 'm1',
                     stops: [{ id: 'service_with_activities', point_id: 'point_10', start: 0, arrival: 1990, end: 1990, considered_setup_duration: 0, activity: 1 }] }
      service = { id: 'service_3', point_id: 'point_3', duration: 0 }

      set = s.send(:insertion_cost_with_tw, timewindow, route_data, service, 0)
      assert set.last < 10086, "#{set.last} should be the best value among all activities' value"
    end

    def test_compute_shift
      vrp = TestHelper.create(VRP.periodic)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      route_data = {
        matrix_id: vrp.matrices.first.id,
        stops: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 4, end: 4, activity: 0, considered_setup_duration: 0 }]
      }
      assert_equal (-2), s.send(:compute_shift,
                                route_data, { id: 'service_2', point_id: 'point_2', activity: 0 }, 2,
                                { id: 'service_1', start: 0, arrival: 4, end: 4, activity: 0, point_id: 'point_2' })
      route_data[:stops] = [{ id: 'service_2', point_id: 'point_2', activity: 0, start: 0, arrival: 5, end: 5 },
                            { id: 'service_1', point_id: 'point_1', activity: 0, start: 5, arrival: 7, end: 7 }]
      assert_equal 8, s.send(:compute_shift,
                             route_data, { id: 'service_3', point_id: 'point_3', activity: 0 }, 10,
                             { id: 'service_1', start: 0, arrival: 5, end: 7, activity: 0, point_id: 'point_1' })
    end

    def test_compute_first_ones
      vrp = VRP.periodic_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      assert_equal [0], s.send(:compute_first_ones, [])
      assert_equal (0..3).to_a, s.send(:compute_first_ones, [:always_first, :never_middle, :always_first, :neutral])
      assert_equal (0..3).to_a, s.send(:compute_first_ones, [:always_first, :never_middle, :always_first, :always_middle, :neutral])
    end

    def test_compute_last_ones
      vrp = VRP.periodic_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      assert_equal [0], s.send(:compute_last_ones, [])
      assert_equal [4], s.send(:compute_last_ones, [:always_first, :never_middle, :always_first, :neutral])
      assert_equal [4], s.send(:compute_last_ones, [:always_first, :never_middle, :always_first, :always_middle])
      assert_equal [3, 4], s.send(:compute_last_ones, [:always_first, :never_middle, :always_first, :never_middle])
    end

    def test_positions_provided
      vrp = VRP.periodic_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      fct = lambda do |requirement, routes, point_id = ['unknow_point']|
        s.compute_consistent_positions_to_insert(requirement, point_id, routes)
      end

      assert_equal [0], fct.call(:always_first, [])
      assert_equal [0, 1], fct.call(:always_first, [{ requirement: :always_first, point_id: 'point' },
                                                    { requirement: :neutral, point_id: 'point' }])
      assert_equal [0], fct.call(:always_first, [{ requirement: :always_last, point_id: 'point' }])
      assert_equal [0, 1, 2, 3], fct.call(:always_first, [{ requirement: :always_first, point_id: 'point' },
                                                          { requirement: :never_middle, point_id: 'point' },
                                                          { requirement: :always_first, point_id: 'point' },
                                                          { requirement: :neutral, point_id: 'point' },
                                                          { requirement: :neutral, point_id: 'point' },
                                                          { requirement: :always_last, point_id: 'point' }])

      assert_equal [], fct.call(:always_middle, [])
      assert_equal [1], fct.call(:always_middle, [{ requirement: :always_first, point_id: 'point' },
                                                  { requirement: :always_last, point_id: 'point' }])
      assert_equal [1], fct.call(:always_middle, [{ requirement: :neutral, point_id: 'point' },
                                                  { requirement: :neutral, point_id: 'point' }])
      assert_equal [1, 2], fct.call(:always_middle, [{ requirement: :neutral, point_id: 'point' },
                                                     { requirement: :always_middle, point_id: 'point' },
                                                     { requirement: :neutral, point_id: 'point' }])

      assert_equal [0], fct.call(:always_last, [])
      assert_equal [1], fct.call(:always_last, [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [2, 3, 4, 5], fct.call(:always_last, [{ requirement: :neutral, point_id: 'point' },
                                                         { requirement: :neutral, point_id: 'point' },
                                                         { requirement: :always_last, point_id: 'point' },
                                                         { requirement: :always_last, point_id: 'point' },
                                                         { requirement: :always_last, point_id: 'point' }])

      assert_equal [], fct.call(:never_first, [])
      assert_equal [1], fct.call(:never_first, [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [1], fct.call(:never_first, [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [], fct.call(:never_first, [{ requirement: :always_last, point_id: 'point' }])
      assert_equal [1], fct.call(:never_first, [{ requirement: :neutral, point_id: 'point' },
                                                { requirement: :always_last, point_id: 'point' }])
      assert_equal [1, 2], fct.call(:never_first, [{ requirement: :always_first, point_id: 'point' },
                                                   { requirement: :neutral, point_id: 'point' },
                                                   { requirement: :always_last, point_id: 'point' }])

      assert_equal [0], fct.call(:never_middle, [])
      assert_equal [0, 1], fct.call(:never_middle, [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [0, 1, 3], fct.call(:never_middle, [{ requirement: :always_first, point_id: 'point' },
                                                       { requirement: :neutral, point_id: 'point' },
                                                       { requirement: :neutral, point_id: 'point' }])

      assert_equal [], fct.call(:never_last, [])
      assert_equal [], fct.call(:never_last, [{ requirement: :always_first, point_id: 'point' }])
      assert_equal [0], fct.call(:never_last, [{ requirement: :neutral, point_id: 'point' }])
      assert_equal [0], fct.call(:never_last, [{ requirement: :always_last, point_id: 'point' }])

      # with point at same location :
      assert_equal [2, 3], fct.call(:always_middle, [{ requirement: :always_first, point_id: 'point' },
                                                     { requirement: :neutral, point_id: 'point' },
                                                     { requirement: :neutral, point_id: 'same_point' },
                                                     { requirement: :neutral, point_id: 'point' }], ['same_point'])

    end

    def test_insertion_cost_with_tw_choses_best_value
      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(:@services_data, 'service_with_activities' => { nb_activities: 2,
                                                                              setup_durations: [0, 0],
                                                                              durations: [0, 0],
                                                                              points_ids: ['point_2', 'point_10'],
                                                                              tws_sets: [[], []] })

      s.instance_variable_set(:@matrices, Marshal.load(File.binread('test/fixtures/chose_best_value_matrices.bindump'))) # rubocop: disable Security/MarshalLoad
      s.instance_variable_set(:@indices, Marshal.load(File.binread('test/fixtures/chose_best_value_indices.bindump'))) # rubocop: disable Security/MarshalLoad

      timewindow = { start_time: 0, arrival_time: 3807, final_time: 3807, setup_duration: 0 }
      route_data = { tw_end: 10000, start_point_id: 'point_0', end_point_id: 'point_0', matrix_id: 'm1',
                     stops: [{ id: 'service_with_activities', point_id: 'point_10', start: 0, arrival: 1990, end: 1990, considered_setup_duration: 0, activity: 1 }] }
      service = { id: 'service_3', point_id: 'point_3', duration: 0 }

      set = s.send(:insertion_cost_with_tw, timewindow, route_data, service, 0)
      assert set.last < 10086, "#{set.last} should be the best value among all activities' value"
    end

    def test_remove_poorly_populated_routes
      vrp = VRP.lat_lon_periodic
      vrp[:vehicles].each{ |v| v[:cost_fixed] = 2 }
      vrp[:services].each{ |s| s[:exclusion_cost] = 1 }
      vrp_to_solve = TestHelper.create(vrp)
      vrp_to_solve.vehicles = TestHelper.expand_vehicles(vrp_to_solve)
      s = Wrappers::PeriodicHeuristic.new(vrp_to_solve)

      route_with_one = [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_two = route_with_one + [{ id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_three = route_with_two + [{ id: 'service_3', point_id: 'point_3', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      route_with_four = route_with_three + [{ id: 'service_4', point_id: 'point_4', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }]
      candidate_route = {
        'vehicle_0' => {
          0 => { stops: route_with_one, cost_fixed: 2, global_day_index: 0, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          1 => { stops: route_with_two, cost_fixed: 2, global_day_index: 1, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          2 => { stops: route_with_three, cost_fixed: 2, global_day_index: 2, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          3 => { stops: route_with_four, cost_fixed: 2, global_day_index: 3, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] }
        }
      }
      s_a, p_a = get_assignment_data(candidate_route, vrp_to_solve)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)

      # standard case :
      s.instance_variable_set(:@candidate_routes, candidate_route.deep_dup)
      s.instance_variable_set(:@still_removed, {})
      s.send(:remove_poorly_populated_routes)
      assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops]
      (1..3).each{ |day|
        refute_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:stops]
      }

      # partial assignment is false
      vrp[:configuration][:resolution][:allow_partial_assignment] = false
      vrp_to_solve = TestHelper.create(vrp)
      vrp_to_solve.vehicles = TestHelper.expand_vehicles(vrp_to_solve)
      s = Wrappers::PeriodicHeuristic.new(vrp_to_solve)
      s.instance_variable_set(:@candidate_routes, candidate_route)
      s_a, p_a = get_assignment_data(candidate_route, vrp_to_solve)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)
      s.instance_variable_set(:@still_removed, {})
      s.send(:remove_poorly_populated_routes)
      (0..3).each{ |day|
        assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:stops]
      }

      # partial assignment is false with routes sorted differently
      s.instance_variable_set(
        :@candidate_routes,
        'vehicle_0' => {
          0 => { stops: route_with_four, cost_fixed: 2, global_day_index: 3, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          1 => { stops: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_3', point_id: 'point_3', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 2, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          2 => { stops: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }, { id: 'service_2', point_id: 'point_2', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 1, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
          3 => { stops: [{ id: 'service_1', point_id: 'point_1', start: 0, arrival: 0, end: 0, setup_duration: 0, activity: 0 }], cost_fixed: 2, global_day_index: 0, tw_start: 0, tw_end: 10000, matrix_id: 'm1', capacity_left: {}, capacity: {}, available_ids: [vrp_to_solve.services.collect(&:id)] },
        }
      )
      s_a, p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp_to_solve)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@points_assignment, p_a)

      s.instance_variable_set(:@still_removed, {})
      s.send(:remove_poorly_populated_routes)
      (0..3).each{ |day|
        assert_empty s.instance_variable_get(:@candidate_routes)['vehicle_0'][day][:stops]
      }
    end

    def test_reaffecting_without_allow_partial_assignment
      vrp = VRP.lat_lon_periodic_two_vehicles
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
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(:@candidate_routes, Marshal.load(File.binread('test/fixtures/reaffecting_without_allow_partial_assignment_routes.bindump'))) # rubocop: disable Security/MarshalLoad

      sequences = s.send(:deduce_sequences, 'service_2', 3, [0, 1, 2, 4, 5, 6])
      assert_equal [[0, 2, 4], [0, 2, 5], [1, 4, 6], [2, 4, 6], []], sequences
      s.instance_variable_set(:@end_phase, true)
      s.instance_variable_set(:@still_removed, {'service_2' => 3})
      s.send(:reaffect_removed_visits)
      new_routes = s.instance_variable_get(:@candidate_routes)
      # [1, 4, 6] is the only combination such that every day is available for service_2,
      # and none of these day's route is empty
      [1, 4, 6].each{ |day|
        assert(new_routes['vehicle_0'][day][:stops].any?{ |stop| stop[:id]&.include?('service_2') })
      }

      sequences = s.send(:deduce_sequences, 'service_1', 7, [0, 1, 2, 3, 4, 5, 6])
      assert_equal [[0, 1, 2, 3, 4, 5, 6]], sequences
      s.instance_variable_set(:@still_removed, {'service_1' => 7})
      s.send(:reaffect_removed_visits)
      assert((0..6).all?{ |day| new_routes['vehicle_0'][day][:stops].any?{ |stop| stop[:id]&.include?('service_1') } })
      s.send(:remove_poorly_populated_routes)
      new_routes = s.instance_variable_get(:@candidate_routes)
      # this is room enough to assign every visit of service_1,
      # but that would violate minimum stop per route expected
      assert((0..6).none?{ |day| new_routes['vehicle_0'][day][:stops].any?{ |stop| stop[:id]&.include?('service_1') } })
    end

    def test_compute_latest_authorized_day
      [10, 14].each{ |visits_number|
        vrp = TestHelper.create(VRP.periodic)
        vrp.schedule_range_indices[:end] = 13

        if visits_number == 10
          vrp.vehicles.first.sequence_timewindows = (0..4).collect{ |day_index|
            Models::Timewindow.create(start: 0, end: 20, day_index: day_index)
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

    def test_compute_latest_authorized_day_2
      vrp = VRP.periodic
      vrp[:vehicles].first.delete(:timewindow)
      vrp[:vehicles].first[:sequence_timewindows] = [
        { start: 0, end: 20, day_index: 0 },
        { start: 0, end: 20, day_index: 1 },
        { start: 0, end: 20, day_index: 2 },
        { start: 0, end: 20, day_index: 3 },
        { start: 0, end: 20, day_index: 4 }
      ]
      vrp[:services].first[:visits_number] = 261
      vrp[:services].first[:minimum_lapse] = 1
      vrp[:configuration][:schedule][:range_indices][:end] = 364

      vrp = TestHelper.create(vrp)
      Interpreters::PeriodicVisits.new(vrp) # call to function compute_possible_days
      assert_equal 261, vrp.services.first.last_possible_days.size
      assert_equal 0, vrp.services.first.last_possible_days.first, 'There are 261 working days, hence a service with 261 visits can only start at day 0'
    end

    def test_compute_latest_authorized_day_with_partially_provided_data
      problem = VRP.periodic
      problem[:services][0][:visits_number] = 4
      problem[:services][0][:last_possible_day_indices] = [2, 4]
      problem[:configuration][:schedule][:range_indices][:end] = 40
      vrp = TestHelper.create(problem)
      Interpreters::PeriodicVisits.new(vrp) # call to function compute_possible_days
      assert_equal [2, 4, 39, 40], vrp.services.first.last_possible_days

      problem[:services][0][:first_possible_day_indices] = [2, 4]
      problem[:services][0][:minimum_lapse] = 3
      vrp = TestHelper.create(problem)
      Interpreters::PeriodicVisits.new(vrp) # call to function compute_possible_days
      assert_equal [2, 5, 8, 11], vrp.services.first.first_possible_days
    end

    def test_exist_possible_first_route_according_to_same_point_day
      vrp = TestHelper.create(VRP.lat_lon_periodic)
      vrp.resolution_same_point_day = true
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_set(:@points_assignment, { 'point_0' => { days: [0, 2, 4, 6] }})
      s.instance_variable_set(:@unlocked, { 'id' => nil })
      vrp.services.first.visits_number = 2
      s.instance_variable_set(:@services_data, { 'id' => { heuristic_period: 3, raw: vrp.services.first }})
      assert s.send(:exist_possible_first_route_according_to_same_point_day?, 'id', 'point_0') # can assign to 0 and 6

      vrp.services.first.visits_number = 3
      s.instance_variable_set(:@services_data, { 'id' => { heuristic_period: 3, raw: vrp.services.first }})
      refute s.send(:exist_possible_first_route_according_to_same_point_day?, 'id', 'point_0') # can assign to 0 and 6 and then nothing

      s.instance_variable_set(:@services_data, { 'id' => { heuristic_period: 2, raw: vrp.services.first }})
      assert s.send(:exist_possible_first_route_according_to_same_point_day?, 'id', 'point_0') # can assign to 0 and 2 and 4
    end

    def test_day_in_possible_interval
      vrp = TestHelper.create(VRP.periodic)
      vrp.services.first.visits_number = 4
      vrp.schedule_range_indices[:end] = 40
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      vrp.services.first.first_possible_days = [0, 1, 2, 3]
      vrp.services.first.last_possible_days = [4, 2, 3, 8]
      assert s.send(:day_in_possible_interval, 'service_1', 0)
      refute s.send(:day_in_possible_interval, 'service_1', 7),
             'Inserting fist visit at day 7 is not allowed, that would be too late to assign remaining visits after'
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0]
      refute s.send(:day_in_possible_interval, 'service_1', 0) # only one visit can be assigned to a given day / in a given set
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0, 1, 2]
      refute s.send(:day_in_possible_interval, 'service_1', 2)
      assert s.send(:day_in_possible_interval, 'service_1', 4)
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0, 1, 2, 4]
      refute s.send(:day_in_possible_interval, 'service_1', 7)

      vrp.services.first.first_possible_days = [0, 1, 2, 5]
      vrp.services.first.last_possible_days = [4, 3, 3, 8]
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = []
      assert s.send(:day_in_possible_interval, 'service_1', 1)
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [1]
      assert s.send(:day_in_possible_interval, 'service_1', 1) # this case will be avoided by compute days
      refute s.send(:compatible_days, 'service_1', 1)
    end

    def test_compute_visits_number
      vrp = VRP.periodic_seq_timewindows
      vrp[:services].first[:visits_number] = 5
      vrp[:services] = [vrp[:services].first]
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      s = Wrappers::PeriodicHeuristic.new(vrp)

      test_set = [[nil, [], [], [1, 2, 3, 4, 5]],
                  [nil, [0, 1, 2, 3, 4], [1, 2, 3, 4, 5], []],
                  [nil, [0, 1, 2], [1, 2, 3], [4, 5]],
                  [nil, [0, 2, 4], [1, 2, 3], [4, 5]],
                  # [1, [0, 2, 4], [1, 3, 5], [2, 4]], # TODO : function should do this properly
                  [2, [0, 2, 4], [1, 2, 3], [4, 5]],
                  # [2, [0, 6], [1, 4], [2, 3, 5]] # TODO : function should do this properly
                ]
      test_set.each{ |max_lapse, used_days, assigned, unassigned|
        s.instance_variable_get(:@services_data)['service_1'][:raw].maximum_lapse = max_lapse
        s.instance_variable_get(:@services_assignment)['service_1'][:days] = used_days
        s.instance_variable_get(:@services_assignment)['service_1'][:missing_visits] = 5 - used_days.size
        services_assignment = s.send(:compute_visits_number)
        assert_equal assigned, services_assignment['service_1'][:assigned_indices]
        assert_equal unassigned, services_assignment['service_1'][:unassigned_indices]
      }
    end

    def test_initialize_routes
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = [Models::Route.create(vehicle: vrp.vehicles[0], mission_ids: %w[1810 1623 2434 8508], day_index: 2)]
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      s.send(:initialize_routes, vrp.routes)

      assert_empty %w[1810 1623 2434 8508] -
                   s.instance_variable_get(:@candidate_routes)['ANDALUCIA 1'][2][:stops].map{ |stop| stop[:id] },
                   'All these visits should have been assigned to this route'
      services_assignment = s.instance_variable_get(:@services_assignment)
      assert %w[1810 1623 2434 8508].all?{ |id| services_assignment[id][:missing_visits] == 0 },
             'All these services\'s visits should have been assigned'
    end

    def test_initialize_routes_vehicle_not_available_at_provided_day
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      s.send(:initialize_routes,
             [Models::Route.create(vehicle_id: vrp.vehicles.first.original_id,
                                   mission_ids: %w[5482 0833 8595 0352 0799 2047 5446 0726 0708],
                                   day_index: 300)]) # not available in schedule

      assert_equal 9, s.instance_variable_get(:@services_assignment).count{ |_id, data| data[:unassigned_reasons].any? },
                   'At least one visit of these 9 services should be rejected because it can not be planned at day 300'
      assert %w[5482 0833 8595 0352 0799 2047 5446 0726 0708].none?{ |id_in_route|
        s.instance_variable_get(:@services_assignment)[id_in_route][:days].any?
      }, 'None of those services\' visit should be assign to avoid unconsisitency with provided routes'
    end

    def test_plan_visits_missing_in_routes
      problem = VRP.periodic
      problem[:services].first[:visits_number] = 3
      problem[:configuration][:schedule][:range_indices][:end] = 8
      vrp = TestHelper.create(problem)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      # assume first visit was assigned at day one :
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0]
      s.instance_variable_get(:@services_assignment)['service_1'][:missing_visits] -= 1
      s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops] << { id: 'service_1' }

      s.send(:plan_visits_missing_in_routes, 'vehicle_0', 0, ['service_1'])
      assert_equal [0, 1, 2], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'First visit was correctly assigned, other visits were not considered, hence we can assign all visits'

      # back to initial case but with bigger lapse :
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0]
      s.instance_variable_get(:@services_data)['service_1'][:heuristic_period] = 2
      s.send(:plan_visits_missing_in_routes, 'vehicle_0', 0, ['service_1'])
      assert_equal [0, 2, 4], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'First visit was correctly assigned, other visits were not considered, hence we can assign all visits while respecting minimum lapse'

      # back to initial case but with bigger lapse :
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0]
      s.send(:plan_visits_missing_in_routes, 'vehicle_0', 0, ['service_1', 'service_1'])
      assert_equal [0], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'Two visits were considered, but only one assigned to a day. We can not insert more visits without risking to generate unconsistency'
    end

    def test_adjust_services_data
      vrp = TestHelper.load_vrps(self, fixture_file: 'performance_13vl')[0]
      vrp.resolution_same_point_day = false
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      p_h = Wrappers::PeriodicHeuristic.new(vrp)

      assert_equal 181, p_h.instance_variable_get(:@candidate_services_ids).size
      assert_equal 181, p_h.instance_variable_get(:@to_plan_service_ids).size

      p_h.instance_variable_set(:@same_point_day, true)
      p_h.send(:adapt_services_data)
      assert_equal 181, p_h.instance_variable_get(:@candidate_services_ids).size
      assert_equal vrp.services.map{ |s| s.activity.point_id }.uniq.size,
                   p_h.instance_variable_get(:@to_plan_service_ids).size,
                   'At the beginning of algorithm, there should be one service to plan per location'

      p_h.instance_variable_get(:@services_unlocked_by).each{ |id, other_ids|
        next if other_ids.empty?

        leader = vrp.services.find{ |s| s.id == id }
        other_visits = other_ids.collect{ |other_id| vrp.services.find{ |s| s.id == other_id } }
        assert_operator leader.visits_number, :>=, other_visits.map(&:visits_number).max,
                        'Leader should have more visits than services it represents'
        assert_equal 1, ([leader.activity.point_id] + other_visits.map{ |other| other.activity.point_id }).uniq.size
      }
    end

    def test_plan_next_visits
      problem = VRP.periodic
      problem[:services].first[:visits_number] = 3
      vrp = TestHelper.create(problem)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      # simulate assigning at first day
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [0]
      s.send(:plan_next_visits, 'vehicle_0', 'service_1', 2)
      assert_equal [0, 1, 2], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'All missing visits should have been assigned because it is possible too'

      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [2]
      s.send(:plan_next_visits, 'vehicle_0', 'service_1', 2)
      assert_equal [2, 3], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'For now, this function does not allow to assign any visit before already inserted one(s)'
      assert_equal 1, (s.instance_variable_get(:@services_assignment).count{ |_id, data| data[:unassigned_reasons].any? })

      s.instance_variable_set(:@allow_partial_assignment, false)
      s.instance_variable_get(:@services_assignment)['service_1'][:days] = [2]
      s.send(:plan_next_visits, 'vehicle_0', 'service_1', 2)
      assert_equal [], s.instance_variable_get(:@services_assignment)['service_1'][:days],
                   'We can only assign 2 out of 3 visits and allow_partial_assignme is off so every visit should be unassigned'
      assert_equal 1, (s.instance_variable_get(:@services_assignment).count{ |_id, data| data[:unassigned_reasons].any? })
    end

    def test_adjust_candidate_routes
      problem = VRP.periodic
      vrp = TestHelper.create(problem)
      vrp.services = vrp.services[0..1]
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops] =
        [{ id: 'service_1', point_id: 'point_1' }, { id: 'service_2', point_id: 'point_2' }]
      s_a, _p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)

      s.send(:adjust_candidate_routes, 'vehicle_0', 0)
      assert_equal 2, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:days].size })
      assert_equal 0, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] })

      s.instance_variable_get(:@services_data)['service_1'][:raw].visits_number = 3
      s.instance_variable_get(:@services_data)['service_1'][:heuristic_period] = 1
      s.instance_variable_get(:@services_data)['service_1'][:raw].first_possible_days = [0, 1, 2]
      s.instance_variable_get(:@services_data)['service_1'][:raw].last_possible_days = [1, 2, 3]
      s.instance_variable_get(:@candidate_routes)['vehicle_0'][0][:stops] =
        [{ id: 'service_1', point_id: 'point_1' }, { id: 'service_2', point_id: 'point_2' }]
      s_a, _p_a = get_assignment_data(s.instance_variable_get(:@candidate_routes), vrp)
      s.instance_variable_set(:@services_assignment, s_a)
      s.instance_variable_set(:@used_to_adjust, [])
      assert_equal 2, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:days].size })
      assert_equal 2, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] })

      s.send(:adjust_candidate_routes, 'vehicle_0', 0)
      assert_equal 4, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:days].size })
      assert_equal 0, (s.instance_variable_get(:@services_assignment).sum{ |_id, data| data[:missing_visits] })
    end

    def test_update_route
      problem = VRP.lat_lon_periodic_two_vehicles
      problem[:matrices].each{ |m|
        [:time, :distance].each{ |dimension|
          m[dimension] = m[dimension].collect.with_index{ |line, l|
                           line.collect.with_index{ |_, i| i == l ? 0 : 1 } }
        }
      }

      vrp = TestHelper.create(problem)
      vrp.services.each{ |s| s.activity.duration = 1 }
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)

      route_data = { day: 0, tw_start: 0, tw_end: 50, start_point_id: vrp.vehicles.first.start_point_id, matrix_id: 'm1',
                     stops: vrp.services.collect{ |service|
                      { id: service.id, start: 0, arrival: 0, end: 0, activity: 0, point_id: service.activity.point_id } } }
      s.send(:update_route, route_data, 5)
      assert_equal 5 * 3 + 1, route_data[:stops].flat_map{ |stop| [stop[:start], stop[:arrival], stop[:end]] }.count(0)
      s.send(:update_route, route_data, 0)
      assert_equal (0..26).to_a, route_data[:stops].flat_map{ |stop| [stop[:start], stop[:arrival], stop[:end]] }.uniq

      # check setup durations properly computed
      s.instance_variable_get(:@services_data).each{ |_id, data| data[:setup_durations] = [1] }
      s.send(:update_route, route_data, 0)
      assert_equal 13, (route_data[:stops].sum{ |stop| stop[:considered_setup_duration] })

      route_data[:stops][-1][:point_id] = route_data[:stops][-2][:point_id]
      s.send(:update_route, route_data, 0)
      assert_equal 12, (route_data[:stops].sum{ |stop| stop[:considered_setup_duration] })
    end

    def test_update_route_can_ignore_timewindow
      problem = VRP.lat_lon_periodic_two_vehicles
      problem[:matrices].each{ |m|
        [:time, :distance].each{ |dimension|
          m[dimension] = m[dimension].collect.with_index{ |line, l|
                           line.collect.with_index{ |_, i| i == l ? 0 : 1 } }
        }
      }

      vrp = TestHelper.create(problem)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      vrp.services.last.activity.timewindows = [Models::Timewindow.create(start: 5, end: 7)]
      s = Wrappers::PeriodicHeuristic.new(vrp)
      route_data = { day: 0, tw_start: 0, tw_end: 50, start_point_id: vrp.vehicles.first.start_point_id, matrix_id: 'm1',
                     stops: vrp.services.collect{ |service|
                      { id: service.id, start: 0, arrival: 0, end: 0, activity: 0, point_id: service.activity.point_id } }}
      # service can not start before 25 which is outside service timewindows
      assert_raises do
        s.send(:update_route, route_data, 0)
      end

      # this is ignored when point at same location is right before and same_point_day is on
      vrp.services[-1].activity.point_id = vrp.services[-2].activity.point_id
      route_data[:stops][-1][:point_id] = route_data[:stops][-2][:point_id]
      s = Wrappers::PeriodicHeuristic.new(vrp)
      s.instance_variable_set(:@same_point_day, true)
      s.send(:update_route, route_data, 0)
      assert_equal (0..12).to_a, route_data[:stops].flat_map{ |stop| [stop[:start], stop[:arrival], stop[:end]] }.uniq
    end

    def test_same_point_compatibility
      problem = VRP.periodic
      problem[:services] = [problem[:services][0]]
      problem[:services][0][:visits_number] = 3
      point_id = problem[:services][0][:activity][:point_id]

      vrp = TestHelper.create(problem)
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      s.instance_variable_set(:@relaxed_same_point_day, true) # same as same_point_day but would require to insert id in @unlocked
      assert s.send(:same_point_compatibility, 'service_1', 0)

      s.instance_variable_get(:@services_data)['service_1'][:heuristic_period] = 1
      s.instance_variable_get(:@points_assignment)[point_id][:days] = [0, 1, 2, 3]
      assert s.send(:same_point_compatibility, 'service_1', 0)
      s.instance_variable_get(:@points_assignment)[point_id][:days] = [0, 2, 4, 6]
      refute s.send(:same_point_compatibility, 'service_1', 0)

      s.instance_variable_get(:@points_assignment)[point_id][:days] = [0, 2]
      assert s.send(:same_point_compatibility, 'service_1', 0)
      s.instance_variable_get(:@points_assignment)[point_id][:days] = [0, 4]
      refute s.send(:same_point_compatibility, 'service_1', 0)
    end
  end
end
