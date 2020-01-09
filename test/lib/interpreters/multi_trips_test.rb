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
require 'date'

class MultiTripsTest < Minitest::Test

  def test_expand_vehicles_trips
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [ 0,  1,  1, 10,  0],
          [ 1,  0,  1, 10,  1],
          [ 1,  1,  0, 10,  1],
          [10, 10, 10,  0, 10],
          [ 0,  1,  1, 10,  0]
        ],
        distance: [
          [ 0,  1,  1, 10,  0],
          [ 1,  0,  1, 10,  1],
          [ 1,  1,  0, 10,  1],
          [10, 10, 10,  0, 10],
          [ 0,  1,  1, 10,  0]
        ]
      }],
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          matrix_index: i
        }
      },
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 1,
          end: 2
        },
        trips: 2
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: 1,
              end: 2
            },{
              start: 5,
              end: 7
            }]
          }
        }
      },
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    vrp = TestHelper.create(problem)
    periodic = Interpreters::MultiTrips.new
    res_vrp = periodic.send(:expand, vrp)

    assert_equal 2, vrp.vehicles.size
    assert vrp.relations.size == 1
    vrp.relations.each{ |relation|
      assert relation.type == 'vehicle_trips'
      assert relation.linked_vehicle_ids.include?('vehicle_0_trip_0')
      assert relation.linked_vehicle_ids.include?('vehicle_0_trip_1')
    }
  end

  def test_solve_vehicles_trips
    size = 5
    problem = {
      units: [{
        id: 'parcels'
      }],
      matrices: [{
        id: 'matrix_0',
        time: [
          [ 0,  1,  1, 10,  0],
          [ 1,  0,  1, 10,  1],
          [ 1,  1,  0, 10,  1],
          [10, 10, 10,  0, 10],
          [ 0,  1,  1, 10,  0]
        ],
        distance: [
          [ 0,  1,  1, 10,  0],
          [ 1,  0,  1, 10,  1],
          [ 1,  1,  0, 10,  1],
          [10, 10, 10,  0, 10],
          [ 0,  1,  1, 10,  0]
        ]
      }],
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          matrix_index: i
        }
      },
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 1,
          end: 30
        },
        trips: 2,
        capacities: [{
          unit_id: 'parcels',
          limit: 2
        }]
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          },
          quantities: [{
            unit_id: 'parcels',
            value: 1
          }]
        }
      },
      configuration: {
        resolution: {
          duration: 10
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 2, result[:routes].size
    route_0 = result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_0_trip_0' }
    route_1 = result[:routes].find{ |route| route[:vehicle_id] == 'vehicle_0_trip_1' }
    assert route_0
    assert route_1
    assert route_0[:activities].last[:departure_time] <= route_1[:activities].first[:begin_time]
  end
end
