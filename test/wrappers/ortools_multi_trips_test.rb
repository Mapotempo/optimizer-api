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
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 1, result[:routes].size
    assert_equal 4, result[:unassigned].size

    # increasing number of trips increases overall available capacity and reduces unassigned :

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_second_trip'
    vrp[:relations] = [{
      type: :vehicle_trips,
      linked_vehicle_ids: [vrp[:vehicles].first[:id], vrp[:vehicles].last[:id]]
    }]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, result[:routes].size
    assert_equal 2, result[:unassigned].size
    routes_start = result[:routes].collect{ |route| route[:activities].first[:begin_time] }
    routes_end = result[:routes].collect{ |route| route[:activities].last[:begin_time] }
    assert_operator routes_end[0], :<=, routes_start[1]

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_third_trip'
    vrp[:relations].first[:linked_vehicle_ids] << vrp[:vehicles].last[:id]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 3, result[:routes].size
    assert_empty result[:unassigned]
    routes_start = result[:routes].collect{ |route| route[:activities].first[:begin_time] }
    routes_end = result[:routes].collect{ |route| route[:activities].last[:begin_time] }
    [1, 2].each{ |next_one|
      assert_operator routes_end[next_one - 1], :<=, routes_start[next_one]
    }
  end

  def test_solve_vehicles_trips_duration
    vrp = VRP.basic
    vrp[:matrices].first[:time] = vrp[:matrices].first[:time].collect{ |l| l.collect{ |v| v.positive? ? 4 : 0 } }
    vrp[:vehicles].first[:end_point_id] = vrp[:vehicles].first[:start_point_id]
    vrp[:vehicles].first[:duration] = 10
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 1, result[:routes].size
    assert_equal 2, result[:unassigned].size

    # increasing number of trips increases overall available duration and reduces unassigned :

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_second_trip'
    vrp[:relations] = [{
      type: :vehicle_trips,
      linked_vehicle_ids: [vrp[:vehicles].first[:id], vrp[:vehicles].last[:id]]
    }]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 2, result[:routes].size
    assert_equal 1, result[:unassigned].size
    routes_start = result[:routes].collect{ |route| route[:activities].first[:begin_time] }
    routes_end = result[:routes].collect{ |route| route[:activities].last[:begin_time] }
    assert_operator routes_end[0], :<=, routes_start[1]

    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_third_trip'
    vrp[:relations].first[:linked_vehicle_ids] << vrp[:vehicles].last[:id]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert_equal 3, result[:routes].size
    assert_empty result[:unassigned]
    routes_start = result[:routes].collect{ |route| route[:activities].first[:begin_time] }
    routes_end = result[:routes].collect{ |route| route[:activities].last[:begin_time] }
    [1, 2].each{ |next_one|
      assert_operator routes_end[next_one - 1], :<=, routes_start[next_one]
    }
  end

  def test_vehicle_trips_with_lapse_0
    problem = VRP.lat_lon_two_vehicles
    problem[:relations] = [{
      type: :vehicle_trips,
      lapse: 0,
      linked_vehicle_ids: problem[:vehicles].collect{ |v| v[:id] }
    }]

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    first_route = result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_0' }
    second_route = result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_1' }
    assert_operator first_route[:end_time], :<=, second_route[:start_time]
  end

  def test_lapse_between_trips
    vrp = VRP.lat_lon_two_vehicles
    # ensure one vehicle only is not enough :
    vrp[:vehicles].each{ |vehicle| vehicle[:distance] = 100000 }
    vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]

    vrp[:relations].first[:lapses] = [3600]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    assert(result[:routes].all?{ |route| route[:activities].size > 2 })
    first_route_end = result[:routes][0][:activities].last[:begin_time]
    last_route_start = result[:routes][1][:activities].first[:begin_time]
    assert_operator first_route_end + 3600, :<=, last_route_start
  end
end
