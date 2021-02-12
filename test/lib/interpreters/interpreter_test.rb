# Copyright © Mapotempo, 2016
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
require 'date'

class InterpreterTest < Minitest::Test
  def periodic_expand(problem)
    vrp = TestHelper.create(problem)
    periodic = Interpreters::PeriodicVisits.new(vrp)
    periodic.send(:expand, vrp, nil)
  end

  def test_global_periodic_expand
    problem = VRP.scheduling
    problem[:services].each{ |service|
      service[:visits_number] = 2
    }
    number_of_days = problem[:configuration][:schedule][:range_indices][:end] - problem[:configuration][:schedule][:range_indices][:start] + 1

    expanded_vrp = periodic_expand(problem)
    assert_equal number_of_days, expanded_vrp[:vehicles].size
    assert_equal problem[:services].collect{ |s| s[:visits_number] }.sum, expanded_vrp[:services].size
    assert_equal ['1_f_2'], expanded_vrp[:services][0].skills
    assert_equal ['2_f_2'], expanded_vrp[:services][1].skills
  end

  def test_expand_vrp_schedule_range_date
    problem = VRP.scheduling
    problem[:services].each{ |service|
      service[:visits_number] = 2
    }
    number_of_days = 2
    problem[:configuration][:schedule] = { range_date: { start: Date.new(2017, 1, 27), end: Date.new(2017, 1, 28) }}

    expanded_vrp = periodic_expand(problem)
    assert_equal number_of_days, expanded_vrp[:vehicles].size
    assert_equal problem[:services].collect{ |s| s[:visits_number] }.sum, expanded_vrp[:services].size
    assert_equal ['1_f_2'], expanded_vrp[:services][0].skills
    assert_equal ['2_f_2'], expanded_vrp[:services][1].skills
  end

  def test_generated_service_timewindows_after_periodic_expand
    problem = VRP.scheduling
    problem[:services].each{ |s| s[:activity][:timewindows] = [{ start: 0, end: 200 }] }

    expanded_vrp = periodic_expand(problem)
    assert expanded_vrp.services.all?{ |s| s.activity.timewindows.size == 1 }, 'There are no day index so we can keep original service timewindows'

    problem = VRP.scheduling
    problem[:services].each{ |s| s[:activity][:timewindows] = [{ start: 0, end: 200, day_index: 0 }] }
    problem[:configuration][:schedule][:range_indices][:end] = 10

    expanded_vrp = periodic_expand(problem)
    assert expanded_vrp.services.all?{ |s| s.activity.timewindows.size == 2 }, 'There are two mondays and service is only available on mondays so there should be two timewindows'

    problem = VRP.scheduling
    problem[:configuration][:schedule][:range_indices][:end] = 10
    problem[:vehicles].each{ |v| v[:timewindow] = { start: 0, end: 10, day_index: 3 } }
    problem[:services].each{ |s| s[:activity][:timewindows] = [{ start: 0, end: 200 }] }

    expanded_vrp = periodic_expand(problem)
    assert expanded_vrp.services.all?{ |s| s.activity.timewindows.uniq.size == 11 }, 'There should be one timewindow per day because vehicle has day_indices'
  end

  def test_generated_vehicle_timewindow_after_periodic_expand
    problem = VRP.scheduling
    problem[:vehicles].first[:timewindow] = { start: 0, end: 10 }
    expanded_vrp = periodic_expand(problem)
    assert_equal 4, expanded_vrp.vehicles.size, 'There should be as many vehicles as days in schedule'
    assert_equal 1, expanded_vrp.vehicles.uniq{ |v| [v.timewindow.start, v.timewindow.end] }.size, 'No need to expand timewindows when no day_index are provided'

    problem = VRP.scheduling
    problem[:vehicles].first[:timewindow] = { start: 0, end: 10 }
    problem[:services].first[:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
    expanded_vrp = periodic_expand(problem)
    assert_equal 4, expanded_vrp.vehicles.size, 'There should be as many vehicles as days in schedule'
    assert_equal 4, expanded_vrp.vehicles.uniq{ |v| [v.timewindow.start, v.timewindow.end] }.size, 'There should be as many vehicles as days in schedule because at least one day_index has been specified'

    problem = VRP.scheduling
    problem[:vehicles].first[:timewindow] = { start: 0, end: 10, day_index: 1 }
    expanded_vrp = periodic_expand(problem)
    assert_equal 1, expanded_vrp.vehicles.size, 'There should be only one vehicle because there is only one tuesday and this vehicle is not available other days'
    assert_equal 86400, expanded_vrp.vehicles.first.timewindow.start, 'Timewindows should be properly expanded, according to day_index'
  end

  def test_expand_vrp_unavailable_visits
    problem = VRP.scheduling
    problem[:services].each{ |s| s[:visits_number] = 2 }
    expanded_vrp = periodic_expand(problem)

    assert_equal 2 * problem[:services].size, expanded_vrp.services.size

    problem[:services].first[:unavailable_visit_indices] = [1]
    expanded_vrp = periodic_expand(problem)
    assert_equal 2 * problem[:services].size - 1, expanded_vrp.services.size
  end

  def test_date_and_unavailable_date
    vrp = VRP.scheduling
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 15) }}
    expanded_vrp = periodic_expand(vrp)
    assert_equal 15, expanded_vrp.vehicles.size

    vrp = VRP.scheduling
    vrp[:vehicles][0][:unavailable_work_date] = [Date.new(2020, 1, 6)]
    vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 15) }}
    vrp = TestHelper.create(vrp)
    assert_equal Set[7], vrp.vehicles.first.unavailable_days

    periodic = Interpreters::PeriodicVisits.new(vrp)
    expanded_vehicles = periodic.send(:expand, vrp, nil).vehicles
    assert_equal 14, expanded_vehicles.size
    assert_nil expanded_vehicles.find{ |v| v.id == 'vehicle_0_7' }, 'There should be no vehicle generated for day index 7'
  end

  def test_indices_and_unavailable_indices
    vrp = VRP.scheduling
    vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 16 }}
    expanded_vrp = periodic_expand(vrp)
    assert_equal 17, expanded_vrp.vehicles.size

    vrp = VRP.scheduling
    vrp[:configuration][:schedule] = {
      range_indices: { start: 0, end: 16 },
      unavailable_indices: [7]
    }
    vrp[:vehicles][0][:unavailable_work_day_indices] = [2]
    expanded_vrp = periodic_expand(vrp)
    assert_equal 15, expanded_vrp.vehicles.size
    assert_nil expanded_vrp.vehicles.find{ |v| v.id == 'vehicle_0_2' }, 'There should be no vehicle generated for day index 2'
    assert_nil expanded_vrp.vehicles.find{ |v| v.id == 'vehicle_0_7' }, 'There should be no vehicle generated for day index 7'
  end

  def test_multiple_reference_to_same_rests
    skip 'Should rework this test with new rests and maybe move to the new scheduling heuristic'
    problem = {
      matrices: [{
        id: 'm1',
        time: [
          [0,  0,  24, 0,  34, 50, 46],
          [0,  0,  24, 0,  34, 50, 46],
          [24, 24, 0,  24, 33, 61, 33],
          [0,  0,  24, 0,  34, 50, 46],
          [33, 33, 32, 33, 0,  81, 54],
          [50, 50, 61, 50, 81, 0,  86],
          [46, 46, 33, 46, 55, 87, 0]
        ],
        distance: [
          [0,   0,   57,  0,   63,  81,  108],
          [0,   0,   57,  0,   53,  81,  108],
          [57,  57,  0,   57,  48,  105, 60],
          [0,   0,   57,  0,   63,  81,  108],
          [62,  62,  46,  62,  0,   134, 97],
          [80,  80,  104, 80,  136, 0,   160],
          [108, 108, 60,  108, 98,  162, 0]
        ]
      }],
      points: [{
        id: 'point_1',
        matrix_index: 0,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'point_2',
        matrix_index: 1,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'point_3',
        matrix_index: 2,
        location: {
          lat: 44.2,
          lon: 5.9
        }
      }, {
        id: 'point_4',
        matrix_index: 3,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'point5',
        matrix_index: 4,
        location: {
          lat: 44.1,
          lon: 6.2
        }
      }, {
        id: 'agent_home',
        matrix_index: 5,
        location: {
          lat: 44.0,
          lon: 5.1
        }
      }, {
        id: 'agent_interm',
        matrix_index: 6,
        location: {
          lat: 44.6,
          lon: 6.1
        }
      }],
      rests: [{
        id: 'break-1',
        duration: 3600.0,
        timewindows: [
          { start: 45000, end: 48600, day_index: 0 },
          { start: 45000, end: 48600, day_index: 1 },
          { start: 45000, end: 48600, day_index: 2 },
          { start: 45000, end: 48600, day_index: 3 },
          { start: 45000, end: 48600, day_index: 4 }
        ]
      }],
      vehicles: [{
        id: 'car_1',
        matrix_id: 'm1',
        cost_fixed: 0.0,
        cost_distance_multiplier: 1.0,
        cost_time_multiplier: 1.0,
        start_point_id: 'agent_home',
        end_point_id: 'agent_home',
        rest_ids: [
          'break-1'
        ],
        sequence_timewindows: [
          { start: 28800, end: 61200, day_index: 0 },
          { start: 28800, end: 61200, day_index: 1 },
          { start: 28800, end: 61200, day_index: 2 },
          { start: 28800, end: 61200, day_index: 3 },
          { start: 28800, end: 61200, day_index: 4 }
        ]
      }, {
        id: 'car_2',
        matrix_id: 'm1',
        cost_fixed: 0.0,
        cost_distance_multiplier: 1.0,
        cost_time_multiplier: 1.0,
        start_point_id: 'agent_home',
        end_point_id: 'agent_interm',
        rest_ids: [
          'break-1'
        ],
        sequence_timewindows: [
          { start: 28800, end: 61200, day_index: 0 },
          { start: 28800, end: 61200, day_index: 1 },
          { start: 28800, end: 61200, day_index: 2 },
          { start: 28800, end: 61200, day_index: 3 },
          { start: 28800, end: 61200, day_index: 4 }
        ]
      }, {
        id: 'car_3',
        matrix_id: 'm1',
        cost_fixed: 0.0,
        cost_distance_multiplier: 1.0,
        cost_time_multiplier: 1.0,
        start_point_id: 'agent_interm',
        end_point_id: 'agent_home',
        rest_ids: [
          'break-1'
        ],
        sequence_timewindows: [
          { start: 28800, end: 61200, day_index: 0 },
          { start: 28800, end: 61200, day_index: 1 },
          { start: 28800, end: 61200, day_index: 2 },
          { start: 28800, end: 61200, day_index: 3 },
          { start: 28800, end: 61200, day_index: 4 }
        ]
      }],
      services: [{
        id: 'point_1',
        priority: 2,
        visits_number: 2,
        minimum_lapse: 14,
        type: 'service',
        activity: {
          duration: 5400.0,
          point_id: 'point_1',
          timewindows: [
            { start: 30600, end: 41400, day_index: 1 },
            { start: 30600, end: 41400, day_index: 2 },
            { start: 30600, end: 41400, day_index: 3 }
          ]
        }
      }, {
        id: 'point_2',
        priority: 2,
        visits_number: 2,
        minimum_lapse: 10,
        type: 'service',
        activity: {
          duration: 5400.0,
          point_id: 'point_2',
          timewindows: [
            { start: 30600, end: 41400, day_index: 1 },
            { start: 30600, end: 41400, day_index: 2 },
            { start: 30600, end: 41400, day_index: 3 }
          ]
        }
      }, {
        id: 'point_3',
        priority: 2,
        visits_number: 1,
        minimum_lapse: 18,
        type: 'service',
        activity: {
          duration: 2700.0,
          point_id: 'point_3',
          timewindows: [
            { start: 30600, end: 42300, day_index: 0 },
            { start: 30600, end: 42300, day_index: 1 },
            { start: 30600, end: 42300, day_index: 2 },
            { start: 30600, end: 42300, day_index: 3 },
            { start: 30600, end: 42300, day_index: 4 }
          ]
        }
      }, {
        id: 'point_4',
        priority: 2,
        visits_number: 1,
        minimum_lapse: 23,
        type: 'service',
        activity: {
          duration: 1200.0,
          point_id: 'point_4',
          timewindows: [
            { start: 28800, end: 45000, day_index: 0 },
            { start: 54000, end: 63000, day_index: 0 },
            { start: 28800, end: 45000, day_index: 1 },
            { start: 54000, end: 63000, day_index: 1 },
            { start: 28800, end: 45000, day_index: 2 },
            { start: 54000, end: 63000, day_index: 2 },
            { start: 28800, end: 45000, day_index: 3 },
            { start: 54000, end: 63000, day_index: 3 },
            { start: 28800, end: 45000, day_index: 4 },
            { start: 54000, end: 63000, day_index: 4 }
          ]
        }
      }, {
        id: 'point5',
        priority: 2,
        visits_number: 1,
        minimum_lapse: 23,
        type: 'service',
        activity: {
          duration: 1800.0,
          point_id: 'point5',
          timewindows: [
            { start: 30600, end: 45000, day_index: 0 },
            { start: 50400, end: 57600, day_index: 0 },
            { start: 30600, end: 45000, day_index: 1 },
            { start: 50400, end: 57600, day_index: 1 },
            { start: 30600, end: 45000, day_index: 2 },
            { start: 50400, end: 57600, day_index: 2 },
            { start: 30600, end: 45000, day_index: 3 },
            { start: 50400, end: 57600, day_index: 3 },
            { start: 30600, end: 45000, day_index: 4 },
            { start: 50400, end: 57600, day_index: 4 }
          ]
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 60000,
          initial_time_out: 5000,
          time_out_multiplier: 2
        },
        schedule: {
          range_date: {
            start: '2017-09-01',
            end: '2017-09-30'
          }
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 1, result[:routes].collect{ |route| route[:activities].count{ |activity| activity[:rest_id] } }.min
    assert_equal 1, result[:routes].collect{ |route| route[:activities].count{ |activity| activity[:rest_id] } }.max
  end

  def test_minimum_lapse_3_visits
    problem = {
      matrices: [{
        id: 'm1',
        time: [
          [0,  0,  24, 0,  34, 50, 46],
          [0,  0,  24, 0,  34, 50, 46],
          [24, 24, 0,  24, 33, 61, 33],
          [0,  0,  24, 0,  34, 50, 46],
          [33, 33, 32, 33, 0,  81, 54],
          [50, 50, 61, 50, 81, 0,  86],
          [46, 46, 33, 46, 55, 87, 0]
        ],
        distance: [
          [0,   0,   57,  0,   63,  81,  108],
          [0,   0,   57,  0,   53,  81,  108],
          [57,  57,  0,   57,  48,  105, 60],
          [0,   0,   57,  0,   63,  81,  108],
          [62,  62,  46,  62,  0,   134, 97],
          [80,  80,  104, 80,  136, 0,   160],
          [108, 108, 60,  108, 98,  162, 0]
        ]
      }],
      points: [{
        id: 'point_1',
        matrix_index: 0,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'agent_home',
        matrix_index: 5,
        location: {
          lat: 44.0,
          lon: 5.1
        }
      }],
      vehicles: [{
        id: 'car_1',
        matrix_id: 'm1',
        cost_fixed: 0.0,
        cost_time_multiplier: 1.0,
        start_point_id: 'agent_home',
        end_point_id: 'agent_home',
        timewindow: {
          start: 0
        }
      }],
      services: [{
        id: 'point_1',
        priority: 2,
        visits_number: 3,
        minimum_lapse: 10,
        type: 'service',
        activity: {
          duration: 100.0,
          point_id: 'point_1'
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 60000,
          iterations: 50,
          iterations_without_improvment: 30,
          initial_time_out: 2160000,
          time_out_multiplier: 1
        },
        schedule: {
          range_date: {
            start: '2017-09-01',
            end: '2017-09-21'
          }
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 3, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][10][:activities].size
    assert_equal 3, result[:routes][20][:activities].size
  end

  def test_minimum_and_maximum_lapse
    problem = {
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 600
        },
        schedule: {
          range_date: {
            start: '2017-09-01', # friday
            end: '2017-09-30' # saturday
          }
        }
      },
      matrices: [{
        id: 'm1',
        time: [
          [0,  0,  24, 0,  34, 50, 46],
          [0,  0,  24, 0,  34, 50, 46],
          [24, 24, 0,  24, 33, 61, 33],
          [0,  0,  24, 0,  34, 50, 46],
          [33, 33, 32, 33, 0,  81, 54],
          [50, 50, 61, 50, 81, 0,  86],
          [46, 46, 33, 46, 55, 87, 0]
        ],
        distance: [
          [0,   0,   57,  0,   63,  81,  108],
          [0,   0,   57,  0,   53,  81,  108],
          [57,  57,  0,   57,  48,  105, 60],
          [0,   0,   57,  0,   63,  81,  108],
          [62,  62,  46,  62,  0,   134, 97],
          [80,  80,  104, 80,  136, 0,   160],
          [108, 108, 60,  108, 98,  162, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 43.8,
          lon: 5.8
        }
      }, {
        id: 'agent_home',
        matrix_index: 5,
        location: {
          lat: 44.0,
          lon: 5.1
        }
      }],
      vehicles: [{
        id: 'vehicle_1',
        matrix_id: 'm1',
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0,
        router_mode: 'car',
        router_dimension: 'time',
        speed_multiplier: 1.0,
        start_point_id: 'agent_home',
        end_point_id: 'agent_home',
        sequence_timewindows: [
          { start: 0, end: 30000, day_index: 0 },
          { start: 0, end: 30000, day_index: 1 },
          { start: 0, end: 30000, day_index: 2 },
          { start: 0, end: 30000, day_index: 3 },
          { start: 0, end: 30000, day_index: 4 }
        ]
      }],
      services: [{
        id: 'service_0',
        priority: 2,
        visits_number: 2,
        minimum_lapse: 15,
        maximum_lapse: 32,
        type: 'service',
        activity: {
          duration: 5400.0,
          point_id: 'point_0',
          timewindows: [
            { start: 0, end: 5400, day_index: 1 },
            { start: 0, end: 5400, day_index: 2 },
            { start: 0, end: 5400, day_index: 3 }
          ]
        }
      }, {
        id: 'service_1',
        priority: 2,
        visits_number: 2,
        minimum_lapse: 11,
        maximum_lapse: 22,
        type: 'service',
        activity: {
          duration: 5400.0,
          point_id: 'point_1',
          timewindows: [
            { start: 0, end: 5400, day_index: 1 },
            { start: 0, end: 5400, day_index: 2 },
            { start: 0, end: 5400, day_index: 3 }
          ]
        }
      }]
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    route_s01 = result[:routes].find{ |route| route[:activities].any?{ |activity| activity[:service_id] == 'service_0_1_2' } }
    route_s02 = result[:routes].find{ |route| route[:activities].any?{ |activity| activity[:service_id] == 'service_0_2_2' } }
    route_s11 = result[:routes].find{ |route| route[:activities].any?{ |activity| activity[:service_id] == 'service_1_1_2' } }
    route_s12 = result[:routes].find{ |route| route[:activities].any?{ |activity| activity[:service_id] == 'service_1_2_2' } }

    route_index_s01 = route_s01 && route_s01[:vehicle_id].split('_').last.to_i || -1
    route_index_s02 = route_s02 && route_s02[:vehicle_id].split('_').last.to_i || -1
    route_index_s11 = route_s11 && route_s11[:vehicle_id].split('_').last.to_i || 33
    route_index_s12 = route_s12 && route_s12[:vehicle_id].split('_').last.to_i || 33

    assert route_index_s02 - route_index_s01 >= 15
    assert route_index_s02 - route_index_s01 <= 32
    assert route_index_s12 - route_index_s11 >= 11
    assert route_index_s12 - route_index_s11 <= 22
  end

  def test_shipments_and_relation
    problem = {
      matrices: [{
        id: 'm1',
        time: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ],
        distance: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 48.9,
          lon: 2.3
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 48.8,
          lon: 2.3
        }
      }, {
        id: 'depot',
        matrix_index: 2,
        location: {
          lat: 50.5,
          lon: 2.7
        }
      }],
      units: [],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        timewindow: {
          start: 500
        }
      }, {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        timewindow: {
          start: 500
        },
        unavailable_work_day_indices: [1]
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_1',
          duration: 500,
          late_multiplier: 0.0
        }
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_1',
          duration: 500,
          late_multiplier: 0.0
        }
      }],
      relations: [{
        id: 'id_rel',
        type: 'meetup',
        linked_ids: ['shipment_0delivery', 'shipment_1delivery']
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 1000
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 5, result[:routes].size
    assert_equal 4, result[:routes][0][:activities].size
    assert_equal 4, result[:routes][1][:activities].size
    assert_equal result[:routes][0][:activities][2][:begin_time], result[:routes][1][:activities][2][:begin_time]
  end

  def test_remove_multiple_empty_service
    problem = {
      matrices: [{
        id: 'm1',
        time: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ],
        distance: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 48.9,
          lon: 2.3
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 48.8,
          lon: 2.3
        }
      }, {
        id: 'depot',
        matrix_index: 2,
        location: {
          lat: 50.5,
          lon: 2.7
        }
      }],
      units: [{
        id: 'unit_0',
      }, {
        id: 'unit_1',
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 5
        }]
      }, {
        id: 'empty_0',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          empty: true
        }, {
          unit_id: 'unit_1',
          value: 1
        }]
      }, {
        id: 'empty_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          empty: true
        }, {
          unit_id: 'unit_1',
          value: 1
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
          max_split_size: 500
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 4, result[:routes][0][:activities].size
  end

  def test_do_not_remove_multiple_empty_service
    problem = {
      matrices: [{
        id: 'm1',
        time: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ],
        distance: [
          [0,    1617, 7728],
          [1515, 0,    8676],
          [7660, 8394, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 48.9,
          lon: 2.3
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 48.8,
          lon: 2.3
        }
      }, {
        id: 'depot',
        matrix_index: 2,
        location: {
          lat: 50.5,
          lon: 2.7
        }
      }],
      units: [{
        id: 'unit_0',
      }, {
        id: 'unit_1',
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }, {
          unit_id: 'unit_1',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0'
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 5
        }]
      }, {
        id: 'empty_0',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          empty: true
        }, {
          unit_id: 'unit_1',
          value: 1
        }]
      }, {
        id: 'empty_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit_0',
          empty: true
        }, {
          unit_id: 'unit_1',
          value: 1
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
          max_split_size: 500
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 5, result[:routes][0][:activities].size
  end

  def test_multi_modal_route_with_capacity
    skip "The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: "
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 44.8457069,
          lon: -0.5759024
        }
      }, {
        id: 'point_1',
        location: {
          lat: 44.8446572,
          lon: -0.5753177
        }
      }, {
        id: 'point_2',
        location: {
          lat: 44.8451706,
          lon: -0.5764657
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.8507881,
          lon: -0.5745077
        }
      }],
      units: [{
        id: 'unit_0',
      }, {
        id: 'unit_1',
      }],
      subtours: [{
        id: 'sub_test',
        time_bounds: 180,
        transmodal_stop_ids: ['point_0'],
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 50
        }]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 5
        }]
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 5
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
          max_split_size: 500
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 7, result[:routes][0][:activities].size
  end

  def test_multi_modal_route_with_skills
    skip "The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: "
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 44.8457069,
          lon: -0.5759024
        }
      }, {
        id: 'point_1',
        location: {
          lat: 44.8446572,
          lon: -0.5753177
        }
      }, {
        id: 'point_2',
        location: {
          lat: 44.8451706,
          lon: -0.5764657
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.8507881,
          lon: -0.5745077
        }
      }],
      subtours: [{
        id: 'sub_test',
        time_bounds: 180,
        transmodal_stop_ids: ['point_0'],
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        skills: [['skill0']]
      }, {
        id: 'vehicle_1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        skills: [['skill1']]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 5
        },
        skills: ['skill0']
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5
        },
        skills: ['skill1']
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
          max_split_size: 500
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 5, result[:routes][0][:activities].size
    assert_equal 'service_0', result[:routes][0][:activities][2][:service_id]
    assert_equal 5, result[:routes][1][:activities].size
    assert_equal 'service_1', result[:routes][1][:activities][2][:service_id]
  end

  def test_multi_modal_route_with_skills_intersection
    skip "This test fails. The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: "
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 44.8457069,
          lon: -0.5759024
        }
      }, {
        id: 'point_1',
        location: {
          lat: 44.8446572,
          lon: -0.5753177
        }
      }, {
        id: 'point_2',
        location:
        {
          lat: 44.8451706,
          lon: -0.5764657
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.8507881,
          lon: -0.5745077
        }
      }],
      subtours: [{
        id: 'sub_test',
        time_bounds: 180,
        transmodal_stop_ids: ['point_0'],
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        skills: [['skill0', 'skill1']]
      }, {
        id: 'vehicle_1',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        skills: [['skill0']]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 5
        },
        skills: ['skill0']
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5
        },
        skills: ['skill1']
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
          max_split_size: 500
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 1, result[:routes].size
    assert_equal 6, result[:routes][0][:activities].size
  end

  def test_multi_modal_route_with_restrained_capacity
    skip "The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: "
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 44.8457069,
          lon: -0.5759024
        }
      }, {
        id: 'point_1',
        location: {
          lat: 44.8446572,
          lon: -0.5753177
        }
      }, {
        id: 'point_2',
        location: {
          lat: 44.8451706,
          lon: -0.5764657
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.8507881,
          lon: -0.5745077
        }
      }],
      units: [{
        id: 'unit_0',
      }, {
        id: 'unit_1',
      }],
      subtours: [{
        id: 'sub_test',
        time_bounds: 180,
        transmodal_stop_ids: ['point_0'],
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 50
        }]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 10
        }]
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 9.9
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 11, result[:routes][0][:activities].size
    assert_equal 9.9, (result[:routes][0][:activities].sum{ |activity| (activity[:service_id] == 'service_1') ? activity[:detail][:quantities].first[:value] : 0 })
    assert_equal 10, (result[:routes][0][:activities].sum{ |activity| (activity[:service_id] == 'service_0') ? activity[:detail][:quantities].first[:value] : 0 })
  end

  def test_multi_modal_route_with_complementary_partial_quantities
    skip "The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: "
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 44.8457069,
          lon: -0.5759024
        }
      }, {
        id: 'point_1',
        location: {
          lat: 44.8446572,
          lon: -0.5753177
        }
      }, {
        id: 'point_2',
        location: {
          lat: 44.8451706,
          lon: -0.5764657
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.8507881,
          lon: -0.5745077
        }
      }],
      units: [{
        id: 'unit_0',
      }, {
        id: 'unit_1',
      }],
      subtours: [{
        id: 'sub_test',
        time_bounds: 180,
        transmodal_stop_ids: ['point_0'],
        capacities: [{
          unit_id: 'unit_0',
          limit: 5
        }]
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'depot',
        end_point_id: 'depot',
        router_mode: 'car',
        cost_late_multiplier: 0.0,
        cost_time_multiplier: 1.0,
        speed_multiplier: 1.0,
        capacities: [{
          unit_id: 'unit_0',
          limit: 50
        }]
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 7.5
        }]
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_2',
          duration: 5
        },
        quantities: [{
          unit_id: 'unit_0',
          value: 7.5
        }]
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true,
        },
        resolution: {
          duration: 1000
        }
      }
    }
    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 10, result[:routes][0][:activities].size
    assert_equal 7.5, (result[:routes][0][:activities].sum{ |activity| (activity[:service_id] == 'service_1') ? activity[:detail][:quantities].first[:value] : 0 })
    assert_equal 7.5, (result[:routes][0][:activities].sum{ |activity| (activity[:service_id] == 'service_0') ? activity[:detail][:quantities].first[:value] : 0 })
  end

  def test_overall_duration_several_vehicles
    skip 'Requires an entire review of the :overall_duration feature'
    problem = VRP.basic
    problem[:vehicles] << { id: 'vehicle_1' }
    problem[:relations] = [{
      type: 'vehicle_group_duration_on_weeks',
      linked_vehicle_ids: ['vehicle_0', 'vehicle_1'],
      lapse: 10,
      periodicity: 1
    }]
    problem[:configuration][:schedule] = {
      range_indices: { start: 6, end: 7 }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 2, expanded_vrp.relations.size

    problem[:relations].first[:type] = 'vehicle_group_duration'
    expanded_vrp = periodic_expand(vrp)
    assert_equal 1,  expanded_vrp.relations.size
    assert_equal 4,  expanded_vrp.relations.first[:linked_vehicle_ids].size

    problem[:relations].first[:type] = 'vehicle_group_duration_on_months'
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
    }
    vrp = TestHelper.create(problem)
    refute_empty vrp.schedule_months_indices
    expanded_vrp = periodic.send(:expand, vrp, nil)
    assert_equal 2, expanded_vrp.relations.size
  end

  def test_overall_duration_with_periodicity
    problem = VRP.basic
    problem[:vehicles] << { id: 'vehicle_1' }
    problem[:relations] = [{
      type: 'vehicle_group_duration_on_weeks',
      linked_vehicle_ids: ['vehicle_0', 'vehicle_1'],
      lapse: 10,
      periodicity: 2
    }]
    problem[:configuration][:schedule] = {
      range_indices: { start: 6, end: 7 }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 1, expanded_vrp.relations.size

    problem[:relations].first[:type] = 'vehicle_group_duration_on_months'
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
    }
    vrp = TestHelper.create(problem)
    refute_empty vrp.schedule_months_indices
    expanded_vrp = periodic_expand(problem)
    assert_equal 1, expanded_vrp.relations.size
  end

  def test_expand_relations_of_one_week_and_one_day
    problem = VRP.basic
    problem[:relations] = [{
      type: 'vehicle_group_duration_on_weeks',
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 10
    }]
    problem[:configuration][:schedule] = {
      range_indices: { start: 0, end: 7 }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 2, expanded_vrp.relations.size

    problem[:relations].first[:periodicity] = 2
    expanded_vrp = periodic_expand(problem)
    assert_equal 1, expanded_vrp.relations.size

    problem[:configuration][:schedule] = {
      range_indices: { start: 0, end: 14 }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 2, expanded_vrp.relations.size
  end

  def test_expand_relations_of_one_month_and_one_day
    problem = VRP.basic
    problem[:relations] = [{
      type: 'vehicle_group_duration_on_months',
      linked_vehicle_ids: ['vehicle_0'],
      lapse: 10
    }]
    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 2, 1) }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 2, expanded_vrp.relations.size

    problem[:relations].first[:periodicity] = 2
    expanded_vrp = periodic_expand(problem)
    assert_equal 1, expanded_vrp.relations.size

    problem[:configuration][:schedule] = {
      range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 3, 1) }
    }
    expanded_vrp = periodic_expand(problem)
    assert_equal 2, expanded_vrp.relations.size
  end

  def test_expand_rests
    vrp = VRP.scheduling
    vrp[:rests] = [{
      id: 'rest',
      timewindows: [{ start: 1, end: 1, day_index: 0 }],
      duration: 1
    }]
    vrp[:vehicles].first[:rest_ids] = ['rest']

    expanded_vrp = periodic_expand(vrp)
    assert_equal 1, expanded_vrp.rests.size, 'We are expecting one rest because vehicle has rests on mondays and there is one in schedule'

    vrp[:configuration][:schedule][:range_indices][:end] = 9
    expanded_vrp = periodic_expand(vrp)
    assert_equal 2, expanded_vrp.rests.size, 'We are expecting two rests because vehicle has rests on mondays and there are two in schedule'

    vrp[:rests].first[:timewindows].each{ |tw| tw.delete(:day_index) }
    expanded_vrp = periodic_expand(vrp)
    assert_equal 10, expanded_vrp.rests.size, 'We are expecting ten rests because vehicle has rests everyday and there are ten days in schedule'
  end

  def test_first_last_possible_days
    vrp = VRP.scheduling
    vrp[:configuration][:schedule][:range_indices] = { start: 0, end: 6 }
    vrp[:services].first[:visits_number] = 3
    vrp[:services].first[:minimum_lapse] = 1

    expanded_vrp = periodic_expand(vrp)
    assert_equal 4, expanded_vrp.services.first.last_possible_days[0]

    vrp[:services].first[:minimum_lapse] = 2
    expanded_vrp = periodic_expand(vrp)
    assert_equal 2, expanded_vrp.services.first.last_possible_days[0]

    vrp[:services].first[:minimum_lapse] = 3
    expanded_vrp = periodic_expand(vrp)
    assert_equal 0, expanded_vrp.services.first.last_possible_days[0]

    # with unavailable days
    vrp[:services].first[:minimum_lapse] = 2

    # possible combinations :
    # 0 - 1 - 2 - 3 - 4 - 5 - 6
    # X -   - X -   - X -   -
    #   - X -   - X -   - X -
    #   -   - X -   - X -   - X
    vrp[:services].first[:unavailable_visit_day_indices] = [6]
    expanded_vrp = periodic_expand(vrp)
    assert_equal 1, expanded_vrp.services.first.last_possible_days[0]

    vrp[:services].first[:unavailable_visit_day_indices] = [3, 4, 5]
    expanded_vrp = periodic_expand(vrp)
    assert_equal 0, expanded_vrp.services.first.last_possible_days[0]

    vrp[:services].first[:unavailable_visit_day_indices] = [0, 1]
    expanded_vrp = periodic_expand(vrp)
    assert_equal 2, expanded_vrp.services.first.first_possible_days[0]
    assert_equal 2, expanded_vrp.services.first.last_possible_days[0]
  end
end
