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
    def test_not_allowing_partial_affectation
      vrp = VRP.scheduling_seq_timewindows
      vrp[:vehicles].first[:sequence_timewindows] = [{
        start: 28800,
        end: 54000,
        day_index: 0
      }, {
        start: 28800,
        end: 54000,
        day_index: 1
      }, {
        start: 28800,
        end: 54000,
        day_index: 3
      }]
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
      assert(result[:routes].none?{ |route| route[:activities].collect{ |stop| stop[:departure_time].to_i - stop[:begin_time].to_i + stop[:travel_time].to_i }.sum > 6 })
    end

    def test_heuristic_called_with_first_sol_param
      vrp = VRP.scheduling
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert result[:solvers].include?('heuristic')
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
      assert(result[:routes].none?{ |r| r[:activities].collect{ |a| a[:point_id] }.size > r[:activities].collect{ |a| a[:point_id] }.uniq.size })

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
      assert result[:unassigned].first[:service_id] == 'service_1_1_1'
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
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_3_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_4_1_1')
      assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_5_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_6_1_1')
      assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_1_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_2_1_1')
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
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      assert result[:routes].collect{ |route| route[:vehicle_id] }.uniq.include?('vehicle_0_0')
      assert result[:routes].collect{ |route| route[:vehicle_id] }.uniq.include?('vehicle_1_0')
      assert result[:routes].collect{ |route| route[:vehicle_id] }.size == result[:routes].collect{ |route| route[:vehicle_id] }.uniq.size
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
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      assert result[:unassigned].collect{ |una| una[:original_service_id] }.compact.size == result[:unassigned].collect{ |una| una[:original_service_id] }.compact.uniq.size
      assert result[:unassigned].collect{ |una| una[:service_id] }.compact.size == result[:unassigned].collect{ |una| una[:service_id] }.compact.uniq.size
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
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      assert !result[:unassigned].collect{ |una| una[:reason] }.uniq.include?('No vehicle with compatible timewindow')
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
        sequence_timewindows: [{ start: 0, end: 7000, day_index: 0 }, { start: 0, end: 7000, day_index: 1 }],
        duration: 50000,
        capacities: [{ unit_id: 'kg', limit: 1100 }],
      }]
      problem[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
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
      assert(result[:routes].all?{ |route| route[:activities].all?{ |activity| activity[:detail][:skills].nil? || activity[:detail][:skills].size == 2 } })
    end

    def test_callage_freq
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      assert result[:routes].collect{ |r| r[:activities].size }.uniq.size == 1
      assert result[:unassigned].empty?
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
      routes.first.day = 2
      vrp.routes = routes

      expecting = vrp.routes.first.mission_ids
      expected_nb_visits = vrp.visits

      # check generated routes
      periodic = Interpreters::PeriodicVisits.new(vrp)
      s = Heuristics::Scheduling.new(vrp, periodic.generate_vehicles(vrp), start: 0, end: 10, shift: 0)
      candidate_routes = s.instance_variable_get(:@candidate_routes)
      assert(candidate_routes.any?{ |_vehicle, vehicle_data| vehicle_data.any?{ |_day, data| data[:current_route].size == expecting.size } })

      # providing uncomplete solution (compared to solution without initial routes)
      puts "On vehicle ANDALUCIA 1_2, expecting #{expecting}"
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal(10, result[:unassigned].count{ |un| un[:reason] == 'Some visits assigned manually (1 visits preassigned in routes)' })
      assert_equal expected_nb_visits, result[:routes].collect{ |r| r[:activities].size - 2 }.flatten.sum + result[:unassigned].size
      assert_equal expecting.size, (result[:routes].find{ |r| r[:vehicle_id] == 'ANDALUCIA 1_2' }[:activities].collect{ |a| a[:service_id].to_s.split('_')[0..-3].join('_') } & expecting).size

      # providing different solution (compared to solution without initial routes)
      vehicle_id, day = vrp.routes.first.vehicle.id.split('_')
      puts "On vehicle #{vehicle_id}_#{day}, expecting #{expecting}"
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = routes
      vrp.routes.first.vehicle.id = vehicle_id
      vrp.routes.first.day = day

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal expected_nb_visits, result[:routes].collect{ |r| r[:activities].size - 2 }.flatten.sum + result[:unassigned].size
      assert_equal expecting.size, (result[:routes].find{ |r| r[:vehicle_id] == "#{vehicle_id}_#{day}" }[:activities].collect{ |a| a[:service_id].to_s.split('_')[0..-3].join('_') } & expecting).size
    end

    def test_reject_unfeasible_initial_solution
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = Marshal.load(File.binread('test/fixtures/formatted_route.bindump')) # rubocop: disable Security/MarshalLoad

      vrp.services.find{ |s| s[:id] == vrp.routes.first.mission_ids[0] }[:activity][:timewindows] = [{ start: 43500, end: 55500 }]
      vrp.services.find{ |s| s[:id] == vrp.routes.first.mission_ids[1] }[:activity][:timewindows] = [{ start: 31500, end: 43500 }]
      vehicle_id, day = vrp.routes.first.vehicle.id.split('_')
      vrp.routes.first.vehicle.id = vehicle_id
      vrp.routes.first.day = day

      assert_raises OptimizerWrapper::UnsupportedProblemError do
        periodic = Interpreters::PeriodicVisits.new(vrp)
        Heuristics::Scheduling.new(vrp, periodic.generate_vehicles(vrp), start: 0, end: 10, shift: 0)
      end
    end

    def test_unassign_if_vehicle_not_available_at_provided_day
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = Marshal.load(File.binread('test/fixtures/formatted_route.bindump')) # rubocop: disable Security/MarshalLoad
      vrp.routes.first.vehicle.id = 'BALEARES'
      vrp.routes.first.day = 300

      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 36, result[:unassigned].size
      assert_equal(9, result[:unassigned].count{ |un| un[:reason] == 'Unfeasible route (vehicle BALEARES not available at day 300)' })
    end

    def test_sticky_in_scheduling
      vrp = VRP.lat_lon_scheduling_two_vehicles
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      result[:routes].find{ |r| r[:activities].any?{ |stop| stop[:service_id] == 'service_6_1_1' } }[:vehicle_id].include?('vehicle_0_') # default result

      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:services].find{ |s| s[:id] == 'service_6' }[:sticky_vehicle_ids] = ['vehicle_1']
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert !result[:routes].find{ |r| r[:activities].any?{ |stop| stop[:service_id] == 'service_6_1_1' } }[:vehicle_id].include?('vehicle_0_')
    end

    def test_with_activities
      vrp = VRP.lat_lon_scheduling_two_vehicles
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
      assert_equal 1, routes_with_activities.collect{ |r| r[:vehicle_id] }.collect{ |id| id.split('_').slice(0, 2) }.uniq.size # every activity on same vehicle
      assert_equal 2, result[:routes].collect{ |r| r[:activities].select{ |a| a[:service_id]&.include?('service_with_activities') } }.flatten.collect{ |a| a[:point_id] }.uniq.size
    end
  end
end
