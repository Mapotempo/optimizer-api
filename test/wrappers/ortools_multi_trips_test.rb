# Copyright © Mapotempo, 2021
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

class MultiTripsTest < Minitest::Test
  def test_solve_vehicles_trips_capacity
    vrp = VRP.lat_lon_capacitated
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 1, solutions[0].routes.size
    assert_equal 4, solutions[0].unassigned.size

    # increasing number of trips increases overall available capacity and reduces unassigned :

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_second_trip'
    vrp[:relations] = [{
      type: :vehicle_trips,
      linked_vehicle_ids: [vrp[:vehicles].first[:id], vrp[:vehicles].last[:id]]
    }]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, solutions[0].routes.size
    assert_equal 2, solutions[0].unassigned.size
    routes_start = solutions[0].routes.collect{ |route| route.stops.first.info.begin_time }
    routes_end = solutions[0].routes.collect{ |route| route.stops.last.info.begin_time }
    assert_operator routes_end[0], :<=, routes_start[1]

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_third_trip'
    vrp[:relations].first[:linked_vehicle_ids] << vrp[:vehicles].last[:id]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 3, solutions[0].routes.size
    assert_empty solutions[0].unassigned
    routes_start = solutions[0].routes.collect{ |route| route.stops.first.info.begin_time }
    routes_end = solutions[0].routes.collect{ |route| route.stops.last.info.begin_time }
    [1, 2].each{ |next_one|
      assert_operator routes_end[next_one - 1], :<=, routes_start[next_one]
    }
  end

  def test_solve_vehicles_trips_duration
    vrp = VRP.basic
    vrp[:matrices].first[:time] = vrp[:matrices].first[:time].collect{ |l| l.collect{ |v| v.positive? ? 4 : 0 } }
    vrp[:vehicles].first[:end_point_id] = vrp[:vehicles].first[:start_point_id]
    vrp[:vehicles].first[:duration] = 10
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 1, solutions[0].routes.size
    assert_equal 2, solutions[0].unassigned.size

    # increasing number of trips increases overall available duration and reduces unassigned :

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_second_trip'
    vrp[:relations] = [{
      type: :vehicle_trips,
      linked_vehicle_ids: [vrp[:vehicles].first[:id], vrp[:vehicles].last[:id]]
    }]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, solutions[0].routes.size
    assert_equal 1, solutions[0].unassigned.size
    routes_start = solutions[0].routes.collect{ |route| route.stops.first.info.begin_time }
    routes_end = solutions[0].routes.collect{ |route| route.stops.last.info.begin_time }
    assert_operator routes_end[0], :<=, routes_start[1]

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_third_trip'
    vrp[:relations].first[:linked_vehicle_ids] << vrp[:vehicles].last[:id]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 3, solutions[0].routes.size
    assert_empty solutions[0].unassigned
    routes_start = solutions[0].routes.collect{ |route| route.stops.first.info.begin_time }
    routes_end = solutions[0].routes.collect{ |route| route.stops.last.info.begin_time }
    [1, 2].each{ |next_one|
      assert_operator routes_end[next_one - 1], :<=, routes_start[next_one]
    }
  end

  def test_vehicle_trips_with_lapse_zero
    problem = VRP.lat_lon_two_vehicles
    problem[:relations] = [{
      type: :vehicle_trips,
      lapse: 0,
      linked_vehicle_ids: problem[:vehicles].collect{ |v| v[:id] }
    }]

    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    first_route = solutions[0].routes.find{ |r| r.vehicle.id == 'vehicle_0' }
    second_route = solutions[0].routes.find{ |r| r.vehicle.id == 'vehicle_1' }
    assert_operator first_route.info.end_time, :<=, second_route.info.start_time
  end

  def test_lapse_between_trips
    vrp = VRP.lat_lon_two_vehicles
    # ensure one vehicle only is not enough :
    vrp[:vehicles].each{ |vehicle| vehicle[:distance] = 100000 }
    vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]

    vrp[:relations].first[:lapses] = [3600]
    solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert(solutions[0].routes.all?{ |route| route.stops.size > 2 })
    first_route_end = solutions[0].routes[0].stops.last.info.begin_time
    last_route_start = solutions[0].routes[1].stops.first.info.begin_time
    assert_operator first_route_end + 3600, :<=, last_route_start
  end

  def test_multi_trips_with_max_split
    vrp = VRP.lat_lon_capacitated

    # 2 vehicles with 4 trips each (to make sure there will be unused but un-transferable vehicles)
    vrp[:relations] = []
    2.times{ |i|
      vrp[:vehicles] << vrp[:vehicles].first.dup.merge({ id: 'other_vehicle' }) if i == 1

      linked_vehicle_ids = [vrp[:vehicles].last[:id]]
      1.upto(3).each{ |trip|
        vrp[:vehicles] << vrp[:vehicles][-trip].dup.merge({ id: "#{vrp[:vehicles][-trip][:id]}_#{trip+1}_trip" })
        linked_vehicle_ids << vrp[:vehicles].last[:id]
      }
      vrp[:relations] << { type: :vehicle_trips, linked_vehicle_ids: linked_vehicle_ids }
    }
    # make sure split uses all vehicles
    vrp[:services].first[:sticky_vehicle_ids] = [vrp[:vehicles].first[:id]]
    vrp[:services].last[:sticky_vehicle_ids] = [vrp[:vehicles].last[:id]]
    # activate max_split
    vrp[:configuration][:preprocessing] ||= {}
    vrp[:configuration][:preprocessing][:max_split_size] = 1
    vrp[:configuration][:preprocessing][:first_solution_strategy] = 'global_cheapest_arc'

    vrp = TestHelper.create(vrp)

    OptimizerWrapper.stub(:solve, lambda{ |service_vrp, _job, _block| # stub with empty solution
      sub_vrp_vehicle_ids = service_vrp[:vrp].vehicles.map(&:id)

      # check vehicle trips are not split
      vrp.relations.each{ |relation|
        assert (relation.linked_vehicle_ids - sub_vrp_vehicle_ids).empty? ||
                 (relation.linked_vehicle_ids & sub_vrp_vehicle_ids).empty?,
               'All trips of a vehicle should be in the same subproblem'
      }

      OptimizerWrapper.send(:__minitest_stub__solve, service_vrp) # call original solve method
    }) do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    end
  end
end
