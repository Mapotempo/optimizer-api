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
          day_index: 0,
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
          day_index: 0,
          start: 1,
          end: 1
        }],
        work_period_days_number: 2
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
          visits_number: 2
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 1
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 1, expanded_vrp[:vehicles].size
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 2}
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 86400 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end

  def test_expand_vrp_schedule_range_date
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
          day_index: 0,
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
        }],
        work_period_days_number: 1
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
          visits_number: 2
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        schedule: {
          range_date: {
            start: Date.new(2017,1,27),
            end: Date.new(2017,1,28)
          }
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

  def test_expand_vrp_unavailable_visits
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
          day_index: 0,
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
          day_index: 0,
          start: 1,
          end: 11
        }],
        work_period_days_number: 2
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              day_index: 0,
              start: 1,
              end: 2
            },{
              day_index: 0,
              start: 5,
              end: 7
            },{
              day_index: 1,
              start: 402,
              end: 408
            }]
          },
          visits_period_days_number: 2,
          unavailable_visit_day_indices: (6..8).to_a + (12..13).to_a,
          unavailable_visit_indices: [2],
          visits_number: 3
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        schedule: {
          range_indices: {
            start: 6,
            end: 20
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 8, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 172800 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services][0].activity.timewindows.size == 3
    assert expanded_vrp[:services][1].activity.timewindows.size == 5
  end

  def test_expand_vrp_with_date
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
          day_index: 0,
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
          day_index: 0,
          start: 1,
          end: 11
        }],
        unavailable_work_date: [Date.new(2017,1,8), Date.new(2017,1,11)],
        work_period_days_number: 2
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              day_index: 0,
              start: 1,
              end: 2
            },{
              day_index: 0,
              start: 5,
              end: 7
            },{
              day_index: 1,
              start: 402,
              end: 408
            }]
          },
          unavailable_visit_day_date: [Date.new(2017,1,2), Date.new(2017,1,11), Date.new(2017,1,17)],
          visits_number: 2,
          visits_period_days_number: 2
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        schedule: {
          range_date: {
            start: Date.new(2017,1,2),
            end: Date.new(2017,1,12)
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 5, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 172800 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 6 || 7 }
  end

  def test_expand_vrp_service_over_a_week
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
          day_index: 0,
          start: 1,
          end: 11
        }, {
          day_index: 1,
          start: 2,
          end: 12
        }],
        work_period_days_number: 7,
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              day_index: 0,
              start: 1,
              end: 2
            },{
              day_index: 0,
              start: 5,
              end: 7
            },{
              day_index: 1,
              start: 402,
              end: 408
            }, {
              day_index: 3,
              start: 803,
              end: 809
            }, {
              day_index: 4,
              start: 204,
              end: 210
            }, {
              day_index: 5,
              start: 605,
              end: 611
            }]
          },
          visits_number: 2,
          visits_period_days_number: 7
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 13
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 4, expanded_vrp[:vehicles].size
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 6 }
    ## The timewindows cover multiple services
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] + 7 * 86400 == expanded_vrp[:services][1].activity.timewindows[0][:start]
  end
end
