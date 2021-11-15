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
  if !ENV['SKIP_PERIODIC']
    def test_empty_services
      vrp = VRP.periodic_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.services = []

      periodic = Interpreters::PeriodicVisits.new(vrp)
      periodic.expand(vrp, nil)
      assert vrp.preprocessing_heuristic_result
    end

    def test_not_allowing_partial_affectation
      vrp = VRP.periodic_seq_timewindows
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
      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

      assert_equal 4, solutions[0].unassigned.size
      assert(solutions[0].unassigned.all?{ |unassigned|
        unassigned.reason.include?('Partial assignment only') ||
        unassigned.reason.include?('Inconsistency between visit number and minimum lapse')
      })
    end

    def test_max_ride_time
      vrp = VRP.periodic
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

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, solutions[0].routes.find{ |route|
        route.stops.collect{ |stop| stop.activity.point.id }.include?('point_2')
      }.stops.size
    end

    def test_max_ride_distance
      vrp = VRP.periodic
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

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, solutions[0].routes.find{ |route|
        route.stops.collect{ |stop| stop.activity.point.id }.include?('point_2')
      }.stops.size
    end

    def test_duration_with_heuristic
      vrp = VRP.periodic
      vrp[:vehicles].first[:duration] = 6

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert(solutions[0].routes.none?{ |route|
        route.stops.sum{ |stop| stop.info.departure_time - stop.info.begin_time + stop.info.travel_time } > 6
      })
    end

    def test_heuristic_called_with_first_sol_param
      vrp = VRP.periodic
      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert_includes solutions[0].solvers, :heuristic
    end

    def test_visit_every_day
      problem = VRP.periodic
      problem[:services].first[:visits_number] = 10
      problem[:services].first[:minimum_lapse] = 1
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 10
        }
      }

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      solutions[0].routes.each{ |r|
        assert_nil r.stops.collect{ |a| a.activity.point.id }.uniq!, 'stops should not contain any duplicates'
      }

      problem[:configuration][:resolution][:allow_partial_assignment] = false
      problem[:configuration][:schedule] = {
        range_indices: {
          start: 0,
          end: 5
        }
      }
      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal 10, solutions[0].unassigned.size
    end

    def test_visit_every_day_2
      problem = VRP.periodic
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

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal 'service_1_1_1', solutions[0].unassigned.first.service_id
    end

    def test_same_cycle
      problem = VRP.lat_lon_periodic
      [[3, 28], [1, 84], [3, 28], [1, 84], [3, 28], [1, 84]].each_with_index{ |data, index|
        problem[:services][index][:visits_number] = data[0]
        problem[:services][index][:minimum_lapse] = data[1]
        problem[:services][index][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      }
      problem[:services][1][:activity][:point_id] = problem[:services][0][:activity][:point_id]
      problem[:services][3][:activity][:point_id] = problem[:services][2][:activity][:point_id]
      problem[:services][5][:activity][:point_id] = problem[:services][4][:activity][:point_id]
      problem[:vehicles].first.delete(:timewindow)
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 20,
        solver: false,
        same_point_day: true,
        allow_partial_assignment: false
      }
      problem[:configuration][:schedule] = { range_indices: { start: 0, end: 83 } }

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }},
                                               TestHelper.load_vrp(self, problem: problem), nil)
      assert_includes solutions[0].routes.find{ |route|
        route.stops.find{ |stop| stop.service_id == 'service_3_1_3' }
      }.stops.map(&:service_id), 'service_4_1_1'
      assert_includes solutions[0].routes.find{ |route|
        route.stops.find{ |stop| stop.service_id == 'service_5_1_3' }
      }.stops.map(&:service_id), 'service_6_1_1'
      assert_includes solutions[0].routes.find{ |route|
        route.stops.find{ |stop| stop.service_id == 'service_1_1_3' }
      }.stops.map(&:service_id), 'service_2_1_1'
    end

    def test_same_cycle_more_difficult
      problem = VRP.lat_lon_periodic
      [[3, 28], [1, 84], [3, 28], [2, 14], [3, 28], [1, 84]].each_with_index{ |data, index|
        problem[:services][index][:visits_number] = data[0]
        problem[:services][index][:minimum_lapse] = data[1]
        problem[:services][index][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      }
      problem[:services][1][:activity][:point_id] = problem[:services][0][:activity][:point_id]
      problem[:services][3][:activity][:point_id] = problem[:services][2][:activity][:point_id]
      problem[:services][5][:activity][:point_id] = problem[:services][4][:activity][:point_id]
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 500000, day_index: 1 }]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:resolution] = {
        duration: 20,
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

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      assert_equal(3, solutions[0].routes.count{ |route|
        route.stops.any?{ |stop| stop.activity.point.id == 'point_1' }
      })
      assert_equal(4, solutions[0].routes.count{ |route|
        route.stops.any?{ |stop| stop.activity.point.id == 'point_3' }
      })
      assert_equal(3, solutions[0].routes.count{ |route|
        route.stops.any?{ |stop| stop.activity.point.id == 'point_5' }
      })
    end

    def test_returned_vehicles_ids_with_two_stage_cluster
      problem = VRP.lat_lon_periodic
      problem[:services].each{ |service|
        service[:visits_number] = 1
        service[:minimum_lapse] = 84
        service[:activity][:timewindows] = [{ start: 0, end: 50000, day_index: 0 },
                                            { start: 0, end: 50000, day_index: 1 }]
      }
      problem[:vehicles] << problem[:vehicles].first.dup
      problem[:vehicles][1][:id] = 'vehicle_1'
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      problem[:configuration][:schedule] = { range_indices: { start: 0, end: 83 } }

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }},
                                               TestHelper.load_vrp(self, problem: problem), nil)
      assert solutions[0]
      route_vehicle_ids = solutions[0].routes.collect{ |route| route.vehicle.id }
      route_uniq_vehicle_ids = route_vehicle_ids.uniq
      assert_includes route_uniq_vehicle_ids, 'vehicle_0_0'
      assert_includes route_uniq_vehicle_ids, 'vehicle_1_0'
      assert_equal route_uniq_vehicle_ids.size, route_vehicle_ids.size
    end

    def test_day_closed_on_work_day
      problem = VRP.lat_lon_periodic
      [[3, 7], [2, 12], [2, 12], [3, 7], [3, 7], [2, 12]].each_with_index{ |data, index|
        problem[:services][index][:visits_number] = data[0]
        problem[:services][index][:minimum_lapse] = data[1]
        problem[:services][index][:activity][:timewindows] = [{ start: 0, end: 500000, day_index: index < 4 ? 0 : 1 }]
      }
      problem[:vehicles].first.delete(:timewindows)
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 7000, day_index: 0 },
                                                         { start: 0, end: 7000, day_index: 1 }]

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }},
                                               TestHelper.load_vrp(self, problem: problem), nil)
      refute_includes solutions[0].unassigned.collect{ |una| una[:reason] }, 'No vehicle with compatible timewindow'
    end

    def test_no_duplicated_skills_with_clustering
      problem = VRP.lat_lon_periodic
      problem[:services] = [problem[:services][0], problem[:services][1]]
      problem[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},
                                            TestHelper.load_vrp(self, problem: problem), nil)
      assert_empty solutions[0].unassigned
      assert(solutions[0].routes.all?{ |route|
        route.stops.all?{ |stop| stop.skills.empty? || stop.skills.size == 3 }
      })
    end

    def test_callage_freq
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      solutions[0].routes.each{ |r| assert_equal 15, r.stops.size }
      assert_empty solutions[0].unassigned
    end

    def test_same_point_day_relaxation
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, Marshal.load(Marshal.dump(vrp)), nil)

      result_service_size = solutions[0].routes.sum{ |route| route.stops.count(&:service_id) } + solutions[0].unassigned.size
      assert_equal vrp.visits, result_service_size, "Found #{result_service_size} instead of #{vrp.visits} expected"

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = solutions[0].routes.collect{ |r|
          r.stops.count{ |stop| stop.activity.point.id == point_id }
        }.count(&:positive?)
        assert days_used <= expected_number_of_days,
               "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }
    end

    def test_total_distance_and_travel_time
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      assert(solutions[0].routes.all?{ |route| route.info.total_travel_time > 0 && route.info.total_distance > 0 })
    end

    def test_provide_initial_solution
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      routes = [Models::Route.create(vehicle: vrp.vehicles.first, mission_ids: %w[1810 1623 2434 8508], day_index: 2)]
      vrp.routes = routes

      expecting = vrp.routes.first.mission_ids
      expected_nb_visits = vrp.visits

      # check generated routes
      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      s = Wrappers::PeriodicHeuristic.new(vrp)
      candidate_routes = s.instance_variable_get(:@candidate_routes)
      assert(candidate_routes.any?{ |_vehicle, vehicle_data| vehicle_data.any?{ |_day, data| data[:stops].size == expecting.size } })

      # providing incomplete solution (compared to solution without initial routes)
      OptimizerLogger.log "On vehicle ANDALUCIA 1_2, expecting #{expecting}"
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = routes
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1, solutions[0].unassigned.size
      assert_equal expected_nb_visits, solutions[0].routes.sum{ |r| r.stops.size - 2 } + solutions[0].unassigned.size
      assert_equal expecting.size,
                   (solutions[0].routes.find{ |r| r.vehicle.id == 'ANDALUCIA 1_2' }.stops.collect{ |a|
                     a.service_id.to_s.split('_')[0..-3].join('_')
                   } & expecting).size

      # providing different solution (compared to solution without initial routes)
      vehicle_id, day = vrp.routes.first.vehicle.id.split('_')
      OptimizerLogger.log "On vehicle #{vehicle_id}_#{day}, expecting #{expecting}"
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia1_two_vehicles')
      vrp.routes = routes
      vrp.routes.first.vehicle.id = vehicle_id
      vrp.routes.first.day_index = day

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal expected_nb_visits, solutions[0].routes.sum{ |r| r.stops.size - 2 } + solutions[0].unassigned.size
      assert_equal expecting.size,
                   (solutions[0].routes.find{ |r| r.vehicle.id == "#{vehicle_id}_#{day}" }.stops.collect{ |a|
                     a.service_id.to_s.split('_')[0..-3].join('_')
                   } & expecting).size
    end

    def test_fix_unfeasible_initial_solution
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = [Models::Route.create(vehicle: vrp.vehicles.first, mission_ids: %w[5482 0833 8595 0352 0799 2047 5446 0726 0708], day_index: 0)]

      vrp.services.find{ |s|
        s[:id] == vrp.routes.first.mission_ids[0]
      }[:activity][:timewindows] = [Models::Timewindow.create(start: 43500, end: 55500)]
      vrp.services.find{ |s|
        s[:id] == vrp.routes.first.mission_ids[1]
      }[:activity][:timewindows] = [Models::Timewindow.create(start: 31500, end: 43500)]

      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      periodic = Wrappers::PeriodicHeuristic.new(vrp)
      generated_starting_routes = periodic.instance_variable_get(:@candidate_routes)

      # periodic initialization uses best order to initialize routes
      assert(generated_starting_routes['BALEARES'][0][:stops].find_index{ |stop| stop[:id] == '5482' } >
             generated_starting_routes['BALEARES'][0][:stops].find_index{ |stop| stop[:id] == '0833' })
    end

    def test_unassign_if_vehicle_not_available_at_provided_day
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.routes = [Models::Route.create(vehicle: vrp.vehicles.first, mission_ids: %w[5482 0833 8595 0352 0799 2047 5446 0726 0708], day_index: 300)]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 36, solutions[0].unassigned.size
    end

    def test_sticky_in_periodic
      vrp = VRP.lat_lon_periodic_two_vehicles
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_includes solutions[0].routes.find{ |r|
                        r.stops.any?{ |stop| stop.service_id == 'service_6_1_1' }
                      }.vehicle.id, 'vehicle_0_' # default result

      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp[:services].find{ |s| s[:id] == 'service_6' }[:sticky_vehicle_ids] = ['vehicle_1']
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      refute_includes solutions[0].routes.find{ |r|
                        r.stops.any?{ |stop| stop.service_id == 'service_6_1_1' }
                      }.vehicle.id, 'vehicle_0_'
    end

    def test_skills_in_periodic_heuristic
      vrp = VRP.lat_lon_periodic_two_vehicles
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assigned_route = solutions[0].routes.find{ |r| r.stops.any?{ |stop| stop.service_id == 'service_6_1_1' } }
      assert_includes assigned_route.vehicle.id, 'vehicle_0_' # default result

      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp[:vehicles][1][:skills] = [[:compatible]]
      vrp[:services].find{ |s| s[:id] == 'service_6' }[:skills] = [:compatible]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assigned_route = solutions[0].routes.find{ |r| r.stops.any?{ |stop| stop.service_id == 'service_6_1_1' } }
      refute_includes assigned_route.vehicle.id, 'vehicle_0_'
    end

    def test_with_activities
      vrp = VRP.lat_lon_periodic_two_vehicles
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

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      routes_with_stops = solutions[0].routes.select{ |r|
        r.stops.map(&:id).any?{ |id| id&.include?('service_with_activities') }
      }
      assert_equal 4, routes_with_stops.size # all stops scheduled (high priority)
      assert_equal 1, routes_with_stops.collect{ |r| r.vehicle.id.split('_').slice(0, 2) }.uniq!&.size # every activity on same vehicle
      assert_equal 2, solutions[0].routes.collect{ |r|
        r.stops.collect{ |a| a.service_id&.include?('service_with_activities') ? a.activity.point.id : nil }.compact!
      }.flatten!&.uniq!&.size
    end

    def test_unavailability_in_schedule
      vrp = VRP.periodic
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 4, solutions[0].routes.size

      vrp[:configuration][:schedule][:unavailable_indices] = [2]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 3, solutions[0].routes.size
      assert(solutions[0].routes.collect{ |r| r.vehicle.id }.none?{ |id| id.split.last == 2 })

      # with date :
      vrp = VRP.periodic
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2017, 1, 2),
          end: Date.new(2017, 1, 5)
        }
      }
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 4, solutions[0].routes.size

      vrp = VRP.periodic
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2017, 1, 2),
          end: Date.new(2017, 1, 5)
        }
      }
      vrp[:configuration][:schedule][:unavailable_date] = [Date.new(2017, 1, 4)]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 3, solutions[0].routes.size
      assert(solutions[0].routes.collect{ |r| r.vehicle.id }.none?{ |id| id.split.last == 3 })
    end

    def test_make_start_tuesday
      problem = VRP.periodic
      problem[:vehicles].first[:id] = 'vehicle'
      problem[:vehicles].first[:timewindow] = nil
      problem[:vehicles].first[:sequence_timewindows] =
        [{ start: 0, end: 100, day_index: 0 },
         { start: 0, end: 200, day_index: 1 },
         { start: 0, end: 300, day_index: 2 },
         { start: 0, end: 400, day_index: 3 },
         { start: 0, end: 500, day_index: 4 }]
      problem[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      problem[:services][1][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 2 }]
      problem[:services][2][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 3 }]
      problem[:configuration][:schedule][:range_indices] = { start: 1, end: 3 }

      vrp = TestHelper.create(problem)

      vrp.vehicles = TestHelper.expand_vehicles(vrp)
      assert_equal(['vehicle_1', 'vehicle_2', 'vehicle_3'], vrp.vehicles.collect(&:id))
      assert_equal([1, 2, 3], vrp.vehicles.collect(&:global_day_index))

      s = Wrappers::PeriodicHeuristic.new(vrp)
      generated_starting_routes = s.instance_variable_get(:@candidate_routes)
      assert_equal([1, 2, 3], generated_starting_routes['vehicle'].keys)
      assert_equal([200, 300, 400], generated_starting_routes['vehicle'].collect{ |_day, route_data| route_data[:tw_end] }) # correct timewindow was provided

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal(['vehicle_1', 'vehicle_2', 'vehicle_3'], solutions[0].routes.collect{ |r| r.vehicle.id })
      solutions[0].routes.each{ |route|
        assert_equal 2, route.stops.size
      }
      assert_equal(['tue_1', 'wed_1', 'thu_1'], solutions[0].routes.collect{ |r| r.stops[1].info.day_week })
    end

    def test_authorized_lapse_with_work_day
      vrp = VRP.periodic
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
      Wrappers::PeriodicHeuristic.stub_any_instance(
        :compute_initial_solution,
        lambda { |vrp_in|
          @starting_time = Time.now
          correct_lapses &&= @services_data.collect{ |_id, data|
            data[:heuristic_period]
          }.all?{ |lapse| lapse.nil? || (lapse % 7).zero? }
          prepare_output_and_collect_routes(vrp_in)
        }
      ) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      end

      assert correct_lapses
    end

    def test_ensure_total_time_and_travel_info
      vrp = VRP.periodic
      vrp[:matrices].first[:distance] = vrp[:matrices].first[:time]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_time.positive?
      }, 'At least one route total_time was not provided'
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_time.positive?
      }, 'At least one route total_time is lower or equal to zero'
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_travel_time.positive?
      }, 'At least one route total_travel_time was not provided'
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_travel_time.positive?
      }, 'At least one route total_travel_time is lower or equal to zero'
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_distance.positive?
      }, 'At least one route total_travel_distance was not provided'
      assert solutions[0].routes.all?{ |route|
        route.stops.none?(&:service_id) || route.info.total_distance.positive?
      }, 'At least one route total_distance is lower or equal to zero'
    end

    def test_global_formula_to_find_original_id_back
      vrp = VRP.lat_lon_periodic
      vrp[:services][0][:id] = 'service1'
      vrp[:services][1][:id] = 'service2_d'
      vrp[:services][2][:id] = 'service_3_'
      vrp[:services][3][:id] = 'service__4'

      vrp = TestHelper.create(vrp)
      original_ids = vrp.services.collect(&:id)
      periodic = Interpreters::PeriodicVisits.new(vrp)
      periodic.expand(vrp, nil)
      assert_empty vrp.services.collect{ |s| s[:id].split('_').slice(0..-3).join('_') } - original_ids,
                   'Periodic IDs structure has changed. We can not find original ID from expanded ID ' \
                   'with current formula (used in periodic heuristic mainly)'
    end

    def test_correct_detailed_costs_merge_with_empty_subproblem
      vrp = VRP.periodic
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
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert solutions[0].cost_info # TODO: Verify costs content whenever it is correctly returned by scheduling heuristic
    end

    def test_same_point_day_option_used_with_incompatible_lapses
      vrp = VRP.lat_lon_periodic
      vrp[:configuration][:schedule][:range_indices][:end] = 5 # 6 days
      [[nil, nil], [5, 5], [2, 3], [1, 2], [1, 2], [1, 1]].each_with_index{ |data, index|
        vrp[:services][index][:activity][:point_id] = 'point_1'
        vrp[:services][index][:activity][:duration] = 1 # in order to try to spread
        vrp[:services][index][:visits_number] = index + 1
        vrp[:services][index][:minimum_lapse], vrp[:services][index][:maximum_lapse] = data
      }

      vrp[:configuration][:resolution][:same_point_day] = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_empty solutions[0].unassigned # there is one service that happens every day so there is no conflict between visits assignment

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
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, solutions[0].unassigned.size
      # TODO : this message should be improved
      # in fact service with 5 visits goes from day 0 to day 4
      # therefore service 2 can not be assigned because it will be assigned after service with 5 visits
      # and service with 5 visits implies that no visit should be assigned at day 5
      assert_equal [2, 2], (solutions[0].unassigned.collect{ |un| un.service_id.split('_').last.to_i })
      reasons = solutions[0].unassigned.map(&:reason)
      assert_equal ["All this service's visits can not be assigned with other services at same location"], reasons.uniq
    end

    def test_empty_periodic_result_when_no_mission
      vrp = TestHelper.create(VRP.periodic)
      # 1 vehicle, 4 days
      vrp.services = []
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 4, solutions[0].routes.size

      vrp = TestHelper.create(VRP.periodic)
      # 1 vehicle, 4 days
      vrp.services = []
      vrp.vehicles.first.unavailable_days = Set[0]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 3, solutions[0].routes.size

      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.vehicles.first.sequence_timewindows.delete_if{ |tw| tw.day_index < 2 }
      vrp.schedule_range_indices[:end] = 3
      # 1 vehicle, 2 days available / 4 days in schedule
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 1 * 2, solutions[0].routes.size

      # testing behaviour within periodic_heuristic
      vrp = TestHelper.create(VRP.periodic)
      solutions = Wrappers::PeriodicHeuristic.stub_any_instance(
        :compute_initial_solution,
        lambda { |vrp_in|
          vrp.preprocessing_heuristic_result = vrp_in.empty_solution(:heuristic)
          return []
        }
      ) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      end
      assert_equal 1 * 4, solutions[0].routes.size
    end

    def test_periodic_with_unavailable_interval
      vrp = VRP.periodic
      vrp[:configuration][:schedule][:range_indices] = { start: 0, end: 10}
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

      filled_routes = solutions[0].routes.collect.with_index{ |r, index|
        [index, r.stops.any?{ |a| a.type == :service }]
      }.select{ |tab| tab[1] }.collect(&:first)
      assert_equal [0, 1, 2], filled_routes

      vrp[:services].first[:unavailable_visit_day_indices] = [0, 1, 2]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      filled_routes = solutions[0].routes.collect.with_index{ |r, index|
        [index, r.stops.any?{ |a| a.type == :service }]
      }.select{ |tab| tab[1] }.collect(&:first)
      assert_equal [0, 1, 3], filled_routes

      vrp = VRP.periodic
      vrp[:vehicles].first[:unavailable_index_ranges] = [{ start: 1, end: 2 }]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, solutions[0].routes.size

      vrp = VRP.periodic
      vrp[:configuration][:schedule].delete(:range_indices)
      vrp[:configuration][:schedule][:range_date] = { start: Date.new(2021, 2, 1), end: Date.new(2021, 2, 11) }
      vrp[:configuration][:schedule][:unavailable_date_ranges] =
        [{ start: Date.new(2021, 2, 3), end: Date.new(2021, 2, 5) },
         { start: Date.new(2021, 2, 8), end: Date.new(2021, 2, 10) }]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 5, solutions[0].routes.size
    end

    def test_unavailable_days_in_periodic
      vrp = VRP.periodic
      vrp[:services].first[:visits_number] = 3
      vrp[:services].first[:minimum_lapse] = 2
      vrp[:services].first[:maximum_lapse] = 3
      vrp[:configuration][:schedule][:range_indices][:end] = 6

      [[[], [0, 2, 4]], [[2], [0, 4, 6]]].each{ |unavailable_indices, expectation|
        vrp[:services].first[:unavailable_visit_day_indices] = unavailable_indices
        solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},
                                                 TestHelper.create(vrp), nil)
        days_with_service =
          solutions[0].routes.collect{ |r|
            r.vehicle.id.split('_').last.to_i if r.stops.any?{ |a| a.id == 'service_1' }
          }.compact
        assert_equal expectation, days_with_service, 'Service was not planned at expected days'
      }
    end

    def test_when_providing_possible_days
      vrp = VRP.periodic
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      service_at_first_day_by_default = solutions[0].routes.first.stops.find(&:service_id).id

      vrp[:services].find{ |s| s[:id] == service_at_first_day_by_default }[:first_possible_day_indices] = [2]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      refute_includes solutions[0].routes.first.stops.collect(&:id), service_at_first_day_by_default

      vrp[:services].each{ |s|
        s[:first_possible_day_indices] = []
        s[:last_possible_day_indices] = [0]
      }
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 3, solutions[0].routes.first.stops.count(&:service_id)
    end

    def test_first_last_possible_day_respected
      vrp = VRP.periodic
      vrp[:services][1][:visits_number] = 2
      vrp[:services][1][:minimum_lapse] = 1
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      second_route = solutions[0].routes.find{ |r| r.vehicle_id == 'vehicle_0_1' }
      assert second_route.stops.any?{ |a| a.service_id == 'service_2_2_2' },
             'This test is not consistent if this fails'
      assert solutions[0].routes[-1].stops.any?{ |a| a.service_id == 'service_1_1_1' },
             'This test is not consistent if this fails'

      vrp[:services][0][:last_possible_day_indices] = [1]
      vrp[:services][1][:first_possible_day_indices] = [1]
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert [0, 1].any?{ |r_i| solutions[0].routes[r_i].stops.any?{ |a| a.service_id == 'service_1_1_1' } },
             'Service_1 can not take place after day index 1'
      assert solutions[0].routes[0].stops.none?{ |a| a.service_id == 'service_2_1_2' },
             'Service_2 can not take before day index 1'
    end

    def test_first_last_possible_day_validation_done_in_data_initialization
      vrp = VRP.lat_lon_periodic
      vrp[:vehicles].each{ |v|
        v[:sequence_timewindows] = (0..4).map{ |day_index|
          { start: 31500, end: 55500, day_index: day_index }
        }
        v.delete(:timewindow)
      }
      vrp[:services][1][:visits_number] = 2
      vrp[:services][1][:first_possible_day_indices] = [2]
      vrp[:services][1][:minimum_lapse] = 3

      vrp[:services][2][:visits_number] = 2
      vrp[:services][2][:first_possible_dates] = [Date.new(2021, 1, 20)]
      vrp[:services][2][:minimum_lapse] = 3

      vrp[:configuration][:schedule] = { range_date: { start: Date.new(2021, 1, 19), end: Date.new(2021, 1, 24)} }

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 4, solutions[0].unassigned.size
      assert(solutions[0].unassigned.all?{ |u| u.reason == 'First and last possible days do not allow this service planification' })
    end
  end
end
