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

  def test_expand_vrp_sequence_and_visit_range
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        sequence_timewindows: [{
          start: 1,
          end: 1
        }]
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
          },
          visits_range_days_number: 1,
          visits_number: 2
        }
      },
      schedule_range_indices: [0, 1],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 2, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 86400 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 2}
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 86400 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end

  def test_expand_vrp_sequence_and_visit_range_with_date
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        sequence_timewindows: [{
          start: 1,
          end: 1
        }]
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
          },
          visits_range_days_number: 1,
          visits_number: 2
        }
      },
      schedule_range_date: {
        start: Date.new(2017,1,27), 
        end: Date.new(2017,1,28)
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 2, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 86400 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 2}
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 86400 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end

  def test_expand_vrp_static_interval
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        sequence_timewindows: [{
          start: 1,
          end: 11
        }, {}],
        static_interval_indices: [[9,11]],
        sequence_timewindow_start_index: 1
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
            },{
              start: 86402,
              end: 86408
            }]
          },
          static_interval_indices: [[9,11] , [12, 13]],
          particular_unavailable_indices: [2, 11, 17],
          visits_number: 2
        }
      },
      schedule_range_indices: [8, 15],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 2, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 172800 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 3}
    ## The timewindows shifts over their period
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 3 * 86400 - 1 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end

  def test_expand_vrp_static_interval_with_date
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        sequence_timewindows: [{
          start: 1,
          end: 11
        }, {}],
        static_interval_date: [{
          start: Date.new(2017,1,9),
          end: Date.new(2017,1,11)
          }],
        sequence_timewindow_start_index: 1
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
            },{
              start: 86402,
              end: 86408
            }]
          },
          static_interval_date: [{
            start: Date.new(2017,1,9),
            end: Date.new(2017,1,11)
          }, {
            start: Date.new(2017,1,12),
            end: Date.new(2017,1,13)
          }],
          particular_unavailable_date: [Date.new(2017,1,2), Date.new(2017,1,11), Date.new(2017,1,17)],
          visits_number: 2
        }
      },
      schedule_range_date: {
        start: Date.new(2017,1,8),
        end: Date.new(2017,1,15)
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 2, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 172800 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 3}
    ## The timewindows shifts over their period
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 3 * 86400 - 1 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end

  def test_expand_vrp_service_over_multiple_interval
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
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0'],
        sequence_timewindows: [{
          start: 1,
          end: 11
        }, {
          start: 2,
          end: 12
        }],
        static_interval_indices: [[0, 4]],
        sequence_timewindow_start_index: 1
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
            },{
              start: 86402,
              end: 86408
            }, {
              start: 172803,
              end: 172809
            }, {
              start: 259204,
              end: 259210
            }, {
              start: 345605,
              end: 345611
            }]
          },
          static_interval_indices: [[0,1] , [3, 4]],
          visits_number: 2
        }
      },
      schedule_range_indices: [0, 4],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 5, expanded_vrp[:vehicles].size
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 3 || service.activity.timewindows.size == 2 }
    ## The timewindows cover multiple services
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 3 * 86400 + 3 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end
end
