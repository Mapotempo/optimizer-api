# Copyright © Mapotempo, 2018
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
    def test_empty_services
      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.services = []

      periodic = Interpreters::PeriodicVisits.new(vrp)
      periodic.expand(vrp, nil)
      assert vrp.preprocessing_heuristic_result
    end

    def test_not_allowing_partial_affectation
      vrp = VRP.scheduling_seq_timewindows
      vrp[:vehicles].first[:sequence_timewindows] = [
        { start: 28800, end: 54000, day_index: 0 },
        { start: 28800, end: 54000, day_index: 1 },
        { start: 28800, end: 54000, day_index: 3 }
      ]
      vrp[:services] = [vrp[:services].first]
      vrp[:services].first[:visits_number] = 4
      vrp[:configuration][:resolution][:allow_partial_assignment] = false
      vrp[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 3
        }
      }
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

      assert_equal 4, result[:unassigned].size
      assert(result[:unassigned].all?{ |unassigned| unassigned[:reason].include?('Partial assignment only') || unassigned[:reason].include?('Unconsistency between visit number and minimum lapse') })
    end

    def test_max_ride_time
      vrp = VRP.scheduling
      vrp[:matrices] = [{
        id: 'matrix_0',
        time: [
          [0, 2, 5, 1],
          [1, 0, 5, 3],
          [5, 5, 0, 5],
          [1, 2, 5, 0]
        ]
      }]
      vrp[:vehicles].first[:maximum_ride_time] = 4

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert result
      assert_equal 2, result[:routes].find{ |route| route[:activities].collect{ |stop| stop[:point_id] }.include?('point_2') }[:activities].size
    end

    def test_max_ride_distance
      vrp = VRP.scheduling
      vrp[:matrices] = [{
        id: 'matrix_0',
        time: [
          [0, 2, 1, 5],
          [1, 0, 3, 5],
          [1, 2, 0, 5],
          [5, 5, 5, 0]
        ],
        distance: [
          [0, 1, 5, 1],
          [1, 0, 5, 1],
          [5, 5, 0, 5],
          [1, 1, 5, 0]
        ]
      }]
      vrp[:vehicles].first[:maximum_ride_distance] = 4

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert result
      assert_equal 2, result[:routes].find{ |route| route[:activities].collect{ |stop| stop[:point_id] }.include?('point_2') }[:activities].size
    end

    def test_duration_with_heuristic
      vrp = VRP.scheduling
      vrp[:vehicles].first[:duration] = 6

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert result
      assert(result[:routes].none?{ |route| route[:activities].sum{ |stop| stop[:departure_time].to_i - stop[:begin_time].to_i + stop[:travel_time].to_i } > 6 })
    end

    def test_heuristic_called_with_first_sol_param
      vrp = VRP.scheduling
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert_includes result[:solvers], 'heuristic'
    end

    def test_visit_every_day
      problem = VRP.scheduling
      problem[:services].first[:visits_number] = 10
      problem[:services].first[:minimum_lapse] = 1
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 10
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      result[:routes].each{ |r|
        assert_nil r[:activities].collect{ |a| a[:point_id] }.uniq!, 'activities should not contain any duplicates'
      }

      problem[:configuration][:resolution][:allow_partial_assignment] = false
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 5
        }
      }
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal 10, result[:unassigned].size
    end

    def test_visit_every_day_2
      problem = VRP.scheduling
      problem[:services].first[:visits_number] = 1
      problem[:services].first[:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 100, day_index: 2 }]
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 2
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal 'service_1_1_1', result[:unassigned].first[:service_id]
    end

    def test_same_cycle
      problem = VRP.lat_lon_scheduling
      problem[:services][0][:visits_number] = 3
      problem[:services][0][:minimum_lapse] = 28
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][1][:visits_number] = 1
      problem[:services][1][:minimum_lapse] = 84
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][2][:visits_number] = 3
      problem[:services][2][:minimum_lapse] = 28
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][3][:visits_number] = 1
      problem[:services][3][:minimum_lapse] = 84
      problem[:services][3][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][4][:visits_number] = 3
      problem[:services][4][:minimum_lapse] = 28
      problem[:services][4][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][5][:visits_number] = 1
      problem[:services][5][:minimum_lapse] = 84
      problem[:services][5][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][1][:activity][:point_id] = problem[:services][0][:activity][:point_id]
      problem[:services][3][:activity][:point_id] = problem[:services][2][:activity][:point_id]
      problem[:services][5][:activity][:point_id] = problem[:services][4][:activity][:point_id]
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: false
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 83
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, problem: problem), nil)
      assert_includes result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_3_1_3' } }[:activities].collect{ |activity| activity[:service_id] }, 'service_4_1_1'
      assert_includes result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_5_1_3' } }[:activities].collect{ |activity| activity[:service_id] }, 'service_6_1_1'
      assert_includes result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_1_1_3' } }[:activities].collect{ |activity| activity[:service_id] }, 'service_2_1_1'
    end

    def test_same_cycle_more_difficult
      problem = VRP.lat_lon_scheduling
      problem[:services][0][:visits_number] = 3
      problem[:services][0][:minimum_lapse] = 28
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][1][:visits_number] = 1
      problem[:services][1][:minimum_lapse] = 84
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][2][:visits_number] = 3
      problem[:services][2][:minimum_lapse] = 28
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][3][:visits_number] = 2
      problem[:services][3][:minimum_lapse] = 14
      problem[:services][3][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][4][:visits_number] = 3
      problem[:services][4][:minimum_lapse] = 28
      problem[:services][4][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][5][:visits_number] = 1
      problem[:services][5][:minimum_lapse] = 84
      problem[:services][5][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][1][:activity][:point_id] = problem[:services][0][:activity][:point_id]
      problem[:services][3][:activity][:point_id] = problem[:services][2][:activity][:point_id]
      problem[:services][5][:activity][:point_id] = problem[:services][4][:activity][:point_id]
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: false
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 83
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal(3, result[:routes].count{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_1' } })
      assert_equal(4, result[:routes].count{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_3' } })
      assert_equal(3, result[:routes].count{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_5' } })
    end

    def test_two_stage_cluster
      problem = VRP.lat_lon_scheduling
      problem[:services][0][:visits_number] = 1
      problem[:services][0][:minimum_lapse] = 84
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:services][1][:visits_number] = 1
      problem[:services][1][:minimum_lapse] = 84
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:services][2][:visits_number] = 1
      problem[:services][2][:minimum_lapse] = 84
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:services][3][:visits_number] = 1
      problem[:services][3][:minimum_lapse] = 84
      problem[:services][3][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:services][4][:visits_number] = 1
      problem[:services][4][:minimum_lapse] = 84
      problem[:services][4][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:services][5][:visits_number] = 1
      problem[:services][5][:minimum_lapse] = 84
      problem[:services][5][:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      problem[:vehicles] = [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_dimension: 'distance',
        sequence_timewindows: [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_dimension: 'distance',
        sequence_timewindows: [{ start: 0, end: 500000, day_index: 0 }, { start: 0, end: 500000, day_index: 1 }]
      }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: false
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 83
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, problem: problem), nil)
      assert result
      route_vehicle_ids = result[:routes].collect{ |route| route[:vehicle_id] }
      route_uniq_vehicle_ids = route_vehicle_ids.uniq
      assert_includes route_uniq_vehicle_ids, 'vehicle_0_0'
      assert_includes route_uniq_vehicle_ids, 'vehicle_1_0'
      assert_equal route_uniq_vehicle_ids.size, route_vehicle_ids.size
    end

    def test_multiple_reason
      problem = VRP.lat_lon_scheduling
      problem[:services][0][:visits_number] = 1
      problem[:services][0][:minimum_lapse] = 84
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][1][:visits_number] = 1
      problem[:services][1][:minimum_lapse] = 84
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][2][:visits_number] = 1
      problem[:services][2][:minimum_lapse] = 84
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][3][:visits_number] = 1
      problem[:services][3][:minimum_lapse] = 84
      problem[:services][3][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][4][:visits_number] = 1
      problem[:services][4][:minimum_lapse] = 84
      problem[:services][4][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][5][:visits_number] = 1
      problem[:services][5][:minimum_lapse] = 84
      problem[:services][5][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][5][:activity][:duration] = 28000
      problem[:services][5][:quantities] = [{ unit_id: 'kg', value: 5000 }]
      problem[:vehicles] = [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_mode: 'car',
        router_dimension: 'distance',
        sequence_timewindows: [{ start: 0, end: 24500, day_index: 1 }],
        duration: 24500,
        capacities: [{ unit_id: 'kg', limit: 1100 }],
      }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: false
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 83
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, problem: problem), nil)
      unassigned_original_service_ids = result[:unassigned].collect{ |una| una[:original_service_id] }
      unassigned_original_service_ids.compact!
      assert_nil unassigned_original_service_ids.uniq!, 'unassigned_original_service_ids should not contain any duplicates'

      unassigned_service_ids = result[:unassigned].collect{ |una| una[:service_id] }
      unassigned_service_ids.compact!
      assert_nil unassigned_service_ids.uniq!, 'unassigned_service_ids should not contain any duplicates'
    end

    def test_day_closed_on_work_day
      problem = VRP.lat_lon_scheduling
      problem[:services][0][:visits_number] = 3
      problem[:services][0][:minimum_lapse] = 7
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 0 }]
      problem[:services][1][:visits_number] = 2
      problem[:services][1][:minimum_lapse] = 12
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 0 }]
      problem[:services][2][:visits_number] = 2
      problem[:services][2][:minimum_lapse] = 12
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 0 }]
      problem[:services][3][:visits_number] = 3
      problem[:services][3][:minimum_lapse] = 7
      problem[:services][3][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 0 }]
      problem[:services][4][:visits_number] = 3
      problem[:services][4][:minimum_lapse] = 7
      problem[:services][4][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:services][5][:visits_number] = 2
      problem[:services][5][:minimum_lapse] = 12
      problem[:services][5][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:vehicles] = [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_dimension: 'time',
        sequence_timewindows: [{ start: 0, end: 7000, day_index: 0 }, { start: 0, end: 7000, day_index: 1 }],
        duration: 50000,
        capacities: [{ unit_id: 'kg', limit: 1100 }],
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_dimension: 'time',
        sequence_timewindows: [{ start: 0, end: 7000, day_index: 0 }, { start: 0, end: 7000, day_index: 1 }],
        duration: 50000,
        capacities: [{ unit_id: 'kg', limit: 1100 }],
      }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: true
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 27
        }
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, problem: problem), nil)
      refute_includes result[:unassigned].collect{ |una| una[:reason] }, 'No vehicle with compatible timewindow'
    end

    def test_no_duplicated_skills
      problem = VRP.lat_lon_scheduling
      problem[:services] = [problem[:services][0], problem[:services][1]]
      problem[:services].first[:visits_number] = 4
      problem[:vehicles] = [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'm1',
        router_dimension: 'time',
        sequence_timewindows: [{ start: 0, end: 70000, day_index: 0 }, { start: 0, end: 70000, day_index: 1 }],
        capacities: [{ unit_id: 'kg', limit: 1100 }],
      }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 10,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: true
      }
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 27
        }
      }

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, problem: problem), nil)
      assert_empty result[:unassigned]
      assert(result[:routes].all?{ |route| route[:activities].all?{ |activity| activity[:detail][:skills].nil? || activity[:detail][:skills].size == 2 } })
    end

    def test_callage_freq
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      result[:routes].each{ |r| assert_equal 15, r[:activities].size }
      assert_empty result[:unassigned]
    end

    def test_same_point_day_relaxation
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)

      assert_equal vrp.visits, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size,
                   "Found #{result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size} instead of #{vrp.visits} expected"

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].collect{ |r| r[:activities].count{ |stop| stop[:point_id] == point_id } }.count(&:positive?)
        assert days_used <= expected_number_of_days, "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }
    end

    def test_total_distance_and_travel_time
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      assert(result[:routes].all?{ |route| route[:total_travel_time] && route[:total_distance] })
    end

    def test_provide_initial_solution
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      routes = Marshal.load(File.binread('test/fixtures/formatted_route.bindump')) # rubocop: disable Security/MarshalLoad
      routes.first.vehicle.id = 'ANDALUCIA 1'
      routes.first.mission_ids = ['1810', '1623', '2434', '8508']
      routes.first.day_index = 2
      vrp.routes = routes

      expecting = vrp.routes.first.mission_ids
      expected_nb_visits = vrp.visits

      # check generated routes
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Heuristics::Scheduling.new(vrp)
      candidate_routes = s.instance_variable_get(:@candidate_routes)
      assert(candidate_routes.any?{ |_vehicle, vehicle_data| vehicle_data.any?{ |_day, data| data[:stops].size == expecting.size } })

      # providing uncomplete solution (compared to solution without initial routes)
      OptimizerLogger.log "On vehicle ANDALUCIA 1_2, expecting #{expecting}"
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = routes
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 0, result[:unassigned].size
      assert_equal expected_nb_visits, result[:routes].sum{ |r| r[:activities].size - 2 } + result[:unassigned].size
      assert_equal expecting.size, (result[:routes].find{ |r| r[:vehicle_id] == 'ANDALUCIA 1_2' }[:activities].collect{ |a| a[:service_id].to_s.split('_')[0..-3].join('_') } & expecting).size

      # providing different solution (compared to solution without initial routes)
      vehicle_id, day = vrp.routes.first.vehicle.id.split('_')
      OptimizerLogger.log "On vehicle #{vehicle_id}_#{day}, expecting #{expecting}"
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = routes
      vrp.routes.first.vehicle.id = vehicle_id
      vrp.routes.first.day_index = day

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal expected_nb_visits, result[:routes].sum{ |r| r[:activities].size - 2 } + result[:unassigned].size
      assert_equal expecting.size, (result[:routes].find{ |r| r[:vehicle_id] == "#{vehicle_id}_#{day}" }[:activities].collect{ |a| a[:service_id].to_s.split('_')[0..-3].join('_') } & expecting).size
    end

    def test_fix_unfeasible_initial_solution
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = Marshal.load(File.binread('test/fixtures/formatted_route.bindump')) # rubocop: disable Security/MarshalLoad

      vrp.services.find{ |s| s[:id] == vrp.routes.first.mission_ids[0] }[:activity][:timewindows] = [Models::Timewindow.new(start: 43500, end: 55500)]
      vrp.services.find{ |s| s[:id] == vrp.routes.first.mission_ids[1] }[:activity][:timewindows] = [Models::Timewindow.new(start: 31500, end: 43500)]
      vehicle_id, day = vrp.routes.first.vehicle.id.split('_')
      vrp.routes.first.vehicle.id = vehicle_id
      vrp.routes.first.day_index = day.to_i

      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      scheduling = Heuristics::Scheduling.new(vrp)
      generated_starting_routes = scheduling.instance_variable_get(:@candidate_routes)

      # scheduling initialization uses best order to initialize routes
      assert(generated_starting_routes['BALEARES'][0][:stops].find_index{ |stop| stop[:id] == '5482' } >
             generated_starting_routes['BALEARES'][0][:stops].find_index{ |stop| stop[:id] == '0833' })
    end

    def test_unassign_if_vehicle_not_available_at_provided_day
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = Marshal.load(File.binread('test/fixtures/formatted_route.bindump')) # rubocop: disable Security/MarshalLoad
      vrp.routes.first.vehicle.id = 'BALEARES'
      vrp.routes.first.day_index = 300

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 36, result[:unassigned].size
    end

    def test_sticky_in_scheduling
      vrp = VRP.lat_lon_scheduling_two_vehicles
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_includes result[:routes].find{ |r| r[:activities].any?{ |stop| stop[:service_id] == 'service_6_1_1' } }[:vehicle_id], 'vehicle_0_' # default result

      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:services].find{ |s| s[:id] == 'service_6' }[:sticky_vehicle_ids] = ['vehicle_1']
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      refute_includes result[:routes].find{ |r| r[:activities].any?{ |stop| stop[:service_id] == 'service_6_1_1' } }[:vehicle_id], 'vehicle_0_'
    end

    def test_with_activities
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:resolution][:minimize_days_worked] = true
      vrp[:vehicles].each{ |v|
        v[:sequence_timewindows].each{ |tw|
          tw[:end] = 10000
        }
      }
      vrp[:services] << {
        id: 'service_with_activities',
        visits_number: 4,
        minimum_lapse: 1,
        priority: 0,
        activities: [{
          duration: 0,
          point_id: 'point_2'
        }, {
          duration: 0,
          point_id: 'point_10'
        }]
      }

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      routes_with_activities = result[:routes].select{ |r| r[:activities].collect{ |a| a[:service_id] }.any?{ |id| id&.include?('service_with_activities') } }
      assert_equal 4, routes_with_activities.size # all activities scheduled (high priority)
      assert_equal 1, routes_with_activities.collect{ |r| r[:vehicle_id].split('_').slice(0, 2) }.uniq!&.size # every activity on same vehicle
      assert_equal 2, result[:routes].collect{ |r| r[:activities].collect{ |a| a[:service_id]&.include?('service_with_activities') ? a[:point_id] : nil }.compact! }.flatten!&.uniq!&.size
    end

    def test_unavailability_in_schedule
      vrp = VRP.scheduling
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 4, result[:routes].size

      vrp[:configuration][:schedule][:unavailable_indices] = [2]
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 3, result[:routes].size
      assert(result[:routes].collect{ |r| r[:vehicle_id] }.none?{ |id| id.split.last == 2 })

      # with date :
      vrp = VRP.scheduling
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2017, 1, 2),
          end: Date.new(2017, 1, 5)
        }
      }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 4, result[:routes].size

      vrp = VRP.scheduling
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2017, 1, 2),
          end: Date.new(2017, 1, 5)
        }
      }
      vrp[:configuration][:schedule][:unavailable_date] = [Date.new(2017, 1, 4)]
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 3, result[:routes].size
      assert(result[:routes].collect{ |r| r[:vehicle_id] }.none?{ |id| id.split.last == 3 })
    end

    def test_make_start_tuesday
      problem = VRP.scheduling
      problem[:vehicles].first[:id] = 'vehicle'
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] = [{
        start: 0,
        end: 100,
        day_index: 0
      }, {
        start: 0,
        end: 200,
        day_index: 1
      }, {
        start: 0,
        end: 300,
        day_index: 2
      }, {
        start: 0,
        end: 400,
        day_index: 3
      }, {
        start: 0,
        end: 500,
        day_index: 4
      }]
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 2 }]
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 3 }]
      problem[:configuration][:schedule][:range_indices] = { start: 1, end: 3 }

      vrp = TestHelper.create(problem)

      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      assert_equal(['vehicle_1', 'vehicle_2', 'vehicle_3'], vrp.vehicles.collect{ |v| v[:id] })
      assert_equal([1, 2, 3], vrp.vehicles.collect{ |v| v[:global_day_index] })

      s = Heuristics::Scheduling.new(vrp)
      generated_starting_routes = s.instance_variable_get(:@candidate_routes)
      assert_equal([1, 2, 3], generated_starting_routes['vehicle'].keys)
      assert_equal([200, 300, 400], generated_starting_routes['vehicle'].collect{ |_day, route_data| route_data[:tw_end] }) # correct timewindow was provided

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal(['vehicle_1', 'vehicle_2', 'vehicle_3'], result[:routes].collect{ |r| r[:vehicle_id] })
      result[:routes].each{ |route|
        assert_equal 2, route[:activities].size
      }
      assert_equal(['tue_1', 'wed_1', 'thu_1'], result[:routes].collect{ |r| r[:activities][1][:day_week] })
    end

    def test_authorized_lapse_with_work_day
      vrp = VRP.scheduling
      vrp[:services].first[:visits_number] = 2
      vrp[:services].first[:minimum_lapse] = 1
      vrp[:services].first[:maximum_lapse] = 2
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      correct_lapses = true
      vrp[:services].first[:maximum_lapse] = 8
      vrp[:configuration][:preprocessing][:partitions] = nil
      vrp[:vehicles].first[:timewindow] = { start: 0, end: 10000, day_index: 0 }
      vrp[:configuration][:schedule][:range_indices][:end] = 8
      Heuristics::Scheduling.stub_any_instance(
        :compute_initial_solution,
        lambda { |vrp_in|
          @starting_time = Time.now
          correct_lapses &&= @services_data.collect{ |_id, data| data[:heuristic_period] }.all?{ |lapse| lapse.nil? || (lapse % 7).zero? }
          prepare_output_and_collect_routes(vrp_in)
        }
      ) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      end

      assert correct_lapses
    end

    def test_ensure_total_time_and_travel_info
      vrp = VRP.scheduling
      vrp[:matrices].first[:distance] = vrp[:matrices].first[:time]
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_time] }, 'At least one route total_time was not provided'
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_time].positive? }, 'At least one route total_time is lower or equal to zero'
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_travel_time] }, 'At least one route total_travel_time was not provided'
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_travel_time].positive? }, 'At least one route total_travel_time is lower or equal to zero'
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_distance] }, 'At least one route total_travel_distance was not provided'
      assert result[:routes].all?{ |route| route[:activities].none?{ |r| r[:service_id] } || route[:total_distance].positive? }, 'At least one route total_distance is lower or equal to zero'
    end

    def test_global_formula_to_find_original_id_back
      vrp = VRP.lat_lon_scheduling
      vrp[:services][0][:id] = 'service1'
      vrp[:services][1][:id] = 'service2_d'
      vrp[:services][2][:id] = 'service_3_'
      vrp[:services][3][:id] = 'service__4'

      vrp = TestHelper.create(vrp)
      original_ids = vrp.services.collect(&:id)
      periodic = Interpreters::PeriodicVisits.new(vrp)
      periodic.expand(vrp, nil)

      assert_empty vrp.services.collect{ |s| s[:id].split('_').slice(0..-3).join('_') } - original_ids, 'Scheduling IDs structure has changed. We can not find original ID from expanded ID with current formula (used in scheduling heuristic mainly)'
    end

    def test_correct_detailed_costs_merge_with_empty_subproblem
      vrp = VRP.scheduling
      vrp[:vehicles] << {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        timewindow: {
          start: 0,
          end: 20
        }
      }
      vrp[:services].each{ |s| s[:sticky_vehicle_ids] = ['vehicle_0'] }
      vrp[:matrices].first[:distance] = vrp[:matrices].first[:time]
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert result[:cost_details] # TODO: Verify costs content whenever it is correctly returned by scheduling heuristic
    end

    def test_same_point_day_option_used_with_uncompatible_lapses
      vrp = VRP.lat_lon_scheduling
      vrp[:configuration][:schedule][:range_indices][:end] = 5 # 6 days
      vrp[:services].each_with_index{ |s, s_i|
        s[:activity][:point_id] = 'point_1'
        s[:activity][:duration] = 1 # to try to spread
        s[:visits_number] = s_i + 1
        s[:minimum_lapse], s[:maximum_lapse] =
          case s_i + 1
          when 1
            [nil, nil]
          when 2
            [5, 5]
          when 3
            [2, 3]
          when 4
            [1, 2]
          when 5
            [1, 2]
          when 6
            [1, 1]
          end
      }

      vrp[:configuration][:resolution][:same_point_day] = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert result # this problem should not be rejected
      assert_empty result[:unassigned] # there is one service that happens every day so there is no conflict between visits assignment

      # TODO : repartition of visits could be improved
      # current repartition : (all shifted at sooner days)
      # for service with 4 visits it would be nicer to have visit 3 at day 3 and visit 4 at day 5
      # ["vehicle_0_0", ["service_2_1_2", "service_3_1_3", "service_4_1_4", "service_5_1_5", "service_6_1_6"]]
      # ["vehicle_0_1", ["service_4_2_4", "service_5_2_5", "service_6_2_6"]]
      # ["vehicle_0_2", ["service_3_2_3", "service_4_3_4", "service_5_3_5", "service_6_3_6"]]
      # ["vehicle_0_3", ["service_4_4_4", "service_5_4_5", "service_6_4_6"]]
      # ["vehicle_0_4", ["service_3_3_3", "service_5_5_5", "service_6_5_6"]]
      # ["vehicle_0_5", ["service_1_1_1", "service_2_2_2", "service_6_6_6"]]

      vrp[:services].delete_if{ |s| s[:visits_number] == 6 }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, result[:unassigned].size
      # TODO : this message should be improved
      # in fact service with 5 visits goes from day 0 to day 4
      # therefore service 2 can not be assigned because it will be assigned after service with 5 visits
      # and service with 5 visits implies that no visit should be assigned at day 5
      assert_equal [2, 2], (result[:unassigned].collect{ |un| un[:service_id].split('_').last.to_i })
      reasons = result[:unassigned].collect{ |un| un[:reason] }
      assert_equal ["All this service's visits can not be assigned with other services at same location"], reasons.uniq
    end

    def test_empty_scheduling_result_when_no_vehicle
      vrp = TestHelper.create(VRP.scheduling)
      vrp.services.first.visits_number = 10
      vrp.vehicles = []
      expected = vrp.visits
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_equal expected, result[:unassigned].size # automatically checked within define_process call

      vrp = TestHelper.create(VRP.pud)
      vrp.shipments.first.visits_number = 10
      vrp.vehicles = []
      vrp.schedule_range_indices = { start: 0, end: 4 }
      expected = vrp.visits
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_equal expected, result[:unassigned].size # automatically checked within define_process call

      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:services] = []
      vrp[:rests] = [{
        id: 'rest_v1'
      }, {
        id: 'rest_v2'
      }]
      vrp[:vehicles][0][:rest_ids] = 'rest_v1'
      vrp[:vehicles][1][:rest_ids] = 'rest_v2'
      # vehicles are available every day
      expected = (vrp[:configuration][:schedule][:range_indices][:end] - vrp[:configuration][:schedule][:range_indices][:start] + 1) * 2
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal expected, result[:unassigned].size

      vrp[:vehicles][0][:rest_ids] = ['rest_v1', 'rest_v2']
      vrp[:vehicles][1][:rest_ids] = []
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal expected, result[:unassigned].size

      vrp[:vehicles][0][:rest_ids] = 'rest_v1'
      vrp[:vehicles][1][:rest_ids] = 'rest_v2'
      vrp[:vehicles][0][:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal expected - 1, result[:unassigned].size
    end

    def test_empty_scheduling_result_when_no_mission
      vrp = TestHelper.create(VRP.scheduling)
      # 1 vehicle, 4 days
      vrp.services = []
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 4, result[:routes].size

      vrp = TestHelper.create(VRP.scheduling)
      # 1 vehicle, 4 days
      vrp.services = []
      vrp.vehicles.first.unavailable_work_day_indices = [0]
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 3, result[:routes].size

      vrp = TestHelper.create(VRP.scheduling_seq_timewindows)
      vrp.vehicles.first.sequence_timewindows.delete_if{ |tw| tw.day_index < 2 }
      vrp.schedule_range_indices[:end] = 3
      # 1 vehicle, 2 days available / 4 days in schedule
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 2, result[:routes].size

      # testing behaviour within scheduling_heuristic
      vrp = TestHelper.create(VRP.scheduling)
      result = Heuristics::Scheduling.stub_any_instance(
        :compute_initial_solution,
        lambda { |vrp_in|
          vrp.preprocessing_heuristic_result = Wrappers::Wrapper.new.empty_result('heuristic', vrp_in)
          return []
        }
      ) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      end
      assert_equal 1 * 4, result[:routes].size
    end
  end
end
