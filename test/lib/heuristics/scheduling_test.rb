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
  def setup
    @regularity_restarts = ENV['INTENSIVE_TEST'] ? 50 : 5
  end

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
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, FCT.create(vrp), nil)

    assert_equal 4, result[:unassigned].size
    assert result[:unassigned].all?{ |unassigned| unassigned[:reason].include?('Only partial assignment') }
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

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools]}}, FCT.create(vrp), nil)
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

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools]}}, FCT.create(vrp), nil)
    assert result
    assert_equal 2, result[:routes].find{ |route| route[:activities].collect{ |stop| stop[:point_id] }.include?('point_2') }[:activities].size
  end

  def test_duration_with_heuristic
    vrp = VRP.scheduling
    vrp[:vehicles].first[:duration] = 6

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(vrp), nil)
    assert result
    assert result[:routes].none?{ |route| route[:activities].collect{ |stop| stop[:departure_time].to_i - stop[:begin_time].to_i + stop[:travel_time].to_i }.sum > 6 }
  end

  def test_heuristic_called_with_first_sol_param
    vrp = VRP.scheduling
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(vrp), nil)
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

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert result[:routes].none?{ |r| r[:activities].collect{ |a| a[:point_id] }.size > r[:activities].collect{ |a| a[:point_id] }.uniq.size }

    problem[:configuration][:resolution][:allow_partial_assignment] = false
    problem[:configuration][:schedule] = {
      range_indices: {
        start: 0,
        end: 5
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert_equal 10, result[:unassigned].size
  end

  def test_visits_number_0
    problem = VRP.scheduling
    problem[:services].first[:visits_number] = 0

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert result[:unassigned].first[:service_id] == 'service_1_0_0'
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.create(problem), nil)
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.load_vrp(self, { problem: problem }), nil)
    assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_3_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_4_1_1')
    assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_5_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_6_1_1')
    assert result[:routes].find{ |route| route[:activities].find{ |activity| activity[:service_id] == 'service_1_1_3' } }[:activities].collect{ |activity| activity[:service_id] }.include?('service_2_1_1')
  end

  def test_same_cycle_more_difficult
    problem = VRP.lat_lon_scheduling
    problem[:services][0][:visits_number] = 3
    problem[:services][0][:minimum_lapse] = 28
    problem[:services][0][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][1][:visits_number] = 1
    problem[:services][1][:minimum_lapse] = 84
    problem[:services][1][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][2][:visits_number] = 3
    problem[:services][2][:minimum_lapse] = 28
    problem[:services][2][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][3][:visits_number] = 2
    problem[:services][3][:minimum_lapse] = 14
    problem[:services][3][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][4][:visits_number] = 3
    problem[:services][4][:minimum_lapse] = 28
    problem[:services][4][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][5][:visits_number] = 1
    problem[:services][5][:minimum_lapse] = 84
    problem[:services][5][:activity][:timewindows] = [{start: 0, end: 500000, day_index: 1}]
    problem[:services][1][:activity][:point_id] = problem[:services][0][:activity][:point_id]
    problem[:services][3][:activity][:point_id] = problem[:services][2][:activity][:point_id]
    problem[:services][5][:activity][:point_id] = problem[:services][4][:activity][:point_id]
    problem[:vehicles].first[:timewindow] = nil
    problem[:vehicles].first[:sequence_timewindows] = [{start: 0, end: 500000, day_index: 1}]
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

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert_equal 3, result[:routes].select{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_1' } }.size
    assert_equal 4, result[:routes].select{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_3' } }.size
    assert_equal 3, result[:routes].select{ |route| route[:activities].any?{ |stop| stop[:point_id] == 'point_5' } }.size
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
      router_mode: 'car',
      router_dimension: 'distance',
      sequence_timewindows: [{ start: 0, end: 50000, day_index: 0 }, { start: 0, end: 50000, day_index: 1 }]
    }, {
      id: 'vehicle_1',
      start_point_id: 'point_0',
      end_point_id: 'point_0',
      router_mode: 'car',
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.load_vrp(self, { problem: problem }), nil)
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.load_vrp(self, { problem: problem }), nil)
    assert result[:unassigned].collect{ |una| una[:original_service_id] }.compact.size == result[:unassigned].collect{ |una| una[:original_service_id] }.compact.uniq.size
    assert result[:unassigned].collect{ |una| una[:service_id] }.compact.size == result[:unassigned].collect{ |una| una[:service_id] }.compact.uniq.size
  end

  def test_day_closed_on_work_day
    skip 'Requires modifications in clustering : No vehicle found related'
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
    problem[:services][1][:activity][:duration] = 1000
    problem[:vehicles] = [{
      id: 'vehicle_0',
      start_point_id: 'point_0',
      end_point_id: 'point_0',
      router_mode: 'car',
      router_dimension: 'time',
      sequence_timewindows: [{ start: 0, end: 7000, day_index: 0 }, { start: 0, end: 7000, day_index: 1 }],
      duration: 50000,
      capacities: [{ unit_id: 'kg', limit: 1100 }],
    }, {
      id: 'vehicle_1',
      start_point_id: 'point_0',
      end_point_id: 'point_0',
      router_mode: 'car',
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.load_vrp(self, { problem: problem }), nil)
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
      router_mode: 'car',
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, FCT.load_vrp(self, { problem: problem }), nil)
    assert(result[:routes].all?{ |route| route[:activities].all?{ |activity| activity[:detail][:skills].nil? || activity[:detail][:skills].size == 1 } })
  end

  def test_results_regularity
    visits_unassigned = []
    services_unassigned = []
    reason_unassigned = []
    (1..@regularity_restarts).each{ |_tentative|
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] } }, vrp, nil)
      visits_unassigned << result[:unassigned].size
      services_unassigned << result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }.uniq.size
      reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.map{ |k, v| [k, v.length] }.to_h
    }

    if services_unassigned.max / services_unassigned.min.to_f >= 2 || visits_unassigned.max >= 14
      reason_unassigned.each_with_index{ |reason, index|
        puts "unassigned visits ##{index} reason:\n#{reason}"
      }
      puts "unassigned services #{services_unassigned}"
      puts "unassigned visits #{visits_unassigned}"
    end

    assert services_unassigned.max / services_unassigned.min.to_f < 2, "unassigned services (#{services_unassigned}) should be more regular" # easier to achieve
    # TODO: visits_unassigned is often 2, but in the worst case 13
    assert visits_unassigned.max < 14, "unassigned visits (#{visits_unassigned}) should be more regular"
  end

  def test_results_regularity_2
    visits_unassigned = []
    services_unassigned = []
    reason_unassigned = []
    (1..@regularity_restarts).each{ |_tentative|
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      visits_unassigned << result[:unassigned].size
      services_unassigned << result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }.uniq.size
      reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.map{ |k, v| [k, v.length] }.to_h
    }

    if services_unassigned.max / services_unassigned.min.to_f >= 2 || visits_unassigned.max / visits_unassigned.min.to_f >= 3
      reason_unassigned.each_with_index{ |reason, index|
        puts "unassigned visits ##{index} reason:\n#{reason}"
      }
      puts "unassigned services #{services_unassigned}"
      puts "unassigned visits #{visits_unassigned}"
    end

    assert services_unassigned.max / services_unassigned.min.to_f < 2, "unassigned services (#{services_unassigned}) should be more regular" # easier to achieve
    # TODO: best visits_unassigned is 8
    assert visits_unassigned.max / visits_unassigned.min.to_f < 3, "unassigned visits (#{visits_unassigned}) should be more regular"
  end

  def test_callage_freq
    vrp = FCT.load_vrp(self)
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] } }, vrp, nil)
    assert result[:routes].collect{ |r| r[:activities].size }.uniq.size == 1
    assert result[:unassigned].empty?
  end
end
