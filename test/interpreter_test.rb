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
    assert_equal 2, expanded_vrp[:vehicles].size
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 2}
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] == expanded_vrp[:services][1].activity.timewindows[0][:start]
    assert expanded_vrp[:services][0].skills == ["1_f_2"]
    assert expanded_vrp[:services][1].skills == ["2_f_2"]
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
    assert expanded_vrp[:services][0].activity.timewindows[0][:start] == expanded_vrp[:services][1].activity.timewindows[0][:start]
    assert expanded_vrp[:services][0].skills == ["1_f_2"]
    assert expanded_vrp[:services][1].skills == ["2_f_2"]
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
        }, {
          day_index: 1,
          start: 1,
          end: 11
        }, {
          day_index: 2,
          start: 1,
          end: 11
        }, {
          day_index: 3,
          start: 1,
          end: 11
        }, {
          day_index: 4,
          start: 1,
          end: 11
        }]
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
    assert_equal 10, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] == 1
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 86400 == expanded_vrp[:vehicles][1].timewindow[:start]
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert_equal 2 * problem[:rests].size, expanded_vrp[:rests].size
    assert expanded_vrp[:services][0].activity.timewindows.size == 3
    assert expanded_vrp[:services][1].activity.timewindows.size == 3
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
        }, {
          day_index: 1,
          start: 1,
          end: 11
        }],
        unavailable_work_date: [Date.new(2017,1,8), Date.new(2017,1,11)]
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
            start: Date.new(2017,1,2), # monday
            end: Date.new(2017,1,12) # thursday
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 4, expanded_vrp[:vehicles].size
    assert expanded_vrp[:vehicles][0].timewindow[:start] + 86400 == expanded_vrp[:vehicles][1].timewindow[:start]
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
        }]
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
    assert expanded_vrp[:services][0].skills == ["1_f_2"]
    assert expanded_vrp[:services][1].skills == ["2_f_2"]
  end

    def test_expand_vrp_with_date_and_indices
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
        }, {
          day_index: 1,
          start: 4,
          end: 14
        }],
        unavailable_work_day_indices: [1,2,3,4,6,7]
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
          unavailable_visit_day_indices: [0,1,2,4,6,7],
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
            start: Date.new(2017,1,2), # monday
            end: Date.new(2017,1,12) # thursday
          }
        }
      }
    }
    expanded_vrp = Interpreters::PeriodicVisits.send(:expand, Models::Vrp.create(problem))
    assert_equal 2, expanded_vrp[:vehicles].size
    assert_equal expanded_vrp[:vehicles][0].timewindow[:start], 1
    assert_equal expanded_vrp[:vehicles][0].timewindow[:end], 11
    assert_equal expanded_vrp[:vehicles][1].timewindow[:start], 86404
    assert_equal expanded_vrp[:vehicles][1].timewindow[:end], 86414
    assert_equal 2 * (size - 1), expanded_vrp[:services].size
    assert expanded_vrp[:services].all?{ |service| service.activity.timewindows.size == 6 || 7 }
  end


  def test_multiple_reference_to_same_rests
    problem = {
      "points": [
        {
          "id": "point_1",
          "location": {
            "lat": 5.8,
            "lon": 43.8
          }
        },
        {
          "id": "point_2",
          "location": {
            "lat": 5.8,
            "lon": 43.8
          }
        },
        {
          "id": "point_3",
          "location": {
            "lat": 5.9,
            "lon": 44.2
          }
        },
        {
          "id": "point_4",
          "location": {
            "lat": 5.8,
            "lon": 43.8
          }
        },
        {
          "id": "point5",
          "location": {
            "lat": 6.2,
            "lon": 44.1
          }
        },
        {
          "id": "agent_home",
          "location": {
            "lat": 44.0,
            "lon": 5.1
          }
        },
        {
          "id": "agent_interm",
          "location": {
            "lat": 44.6,
            "lon": 6.1
          }
        }
      ],
      "rests": [
        {
          "id": "break-1",
          "duration": 3600.0,
          "timewindows": [
            {
              "start": 45000,
              "end": 48600,
              "day_index": 0
            },
            {
              "start": 45000,
              "end": 48600,
              "day_index": 1
            },
            {
              "start": 45000,
              "end": 48600,
              "day_index": 2
            },
            {
              "start": 45000,
              "end": 48600,
              "day_index": 3
            },
            {
              "start": 45000,
              "end": 48600,
              "day_index": 4
            }
          ]
        }
      ],
      "vehicles": [
        {
          "id": "car_1",
          "cost_fixed": 0.0,
          "cost_distance_multiplier": 1.0,
          "cost_time_multiplier": 1.0,
          "start_point_id": "agent_home",
          "end_point_id": "agent_home",
          "rest_ids": [
            "break-1"
          ],
          "sequence_timewindows": [
            {
              "start": 28800,
              "end": 61200,
              "day_index": 0
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 1
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 2
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 3
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 4
            }
          ]
        },
        {
          "id": "car_2",
          "cost_fixed": 0.0,
          "cost_distance_multiplier": 1.0,
          "cost_time_multiplier": 1.0,
          "start_point_id": "agent_home",
          "end_point_id": "agent_interm",
          "rest_ids": [
            "break-1"
          ],
          "sequence_timewindows": [
            {
              "start": 28800,
              "end": 61200,
              "day_index": 0
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 1
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 2
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 3
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 4
            }
          ]
        },
        {
          "id": "car_3",
          "cost_fixed": 0.0,
          "cost_distance_multiplier": 1.0,
          "cost_time_multiplier": 1.0,
          "start_point_id": "agent_interm",
          "end_point_id": "agent_home",
          "rest_ids": [
            "break-1"
          ],
          "sequence_timewindows": [
            {
              "start": 28800,
              "end": 61200,
              "day_index": 0
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 1
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 2
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 3
            },
            {
              "start": 28800,
              "end": 61200,
              "day_index": 4
            }
          ]
        }
      ],
      "services": [
        {
          "id": "point_1",
          "priority": 2,
          "visits_number": 2,
          "minimum_lapse": 14,
          "type": "service",
          "activity": {
            "duration": 5400.0,
            "point_id": "point_1",
            "timewindows": [
              {
                "start": 30600,
                "end": 41400,
                "day_index": 1
              },
              {
                "start": 30600,
                "end": 41400,
                "day_index": 2
              },
              {
                "start": 30600,
                "end": 41400,
                "day_index": 3
              }
            ]
          }
        },
        {
          "id": "point_2",
          "priority": 2,
          "visits_number": 2,
          "minimum_lapse": 10,
          "type": "service",
          "activity": {
            "duration": 5400.0,
            "point_id": "point_2",
            "timewindows": [
              {
                "start": 30600,
                "end": 41400,
                "day_index": 1
              },
              {
                "start": 30600,
                "end": 41400,
                "day_index": 2
              },
              {
                "start": 30600,
                "end": 41400,
                "day_index": 3
              }
            ]
          }
        },
        {
          "id": "point_3",
          "priority": 2,
          "visits_number": 1,
          "minimum_lapse": 18,
          "type": "service",
          "activity": {
            "duration": 2700.0,
            "point_id": "point_3",
            "timewindows": [
              {
                "start": 30600,
                "end": 42300,
                "day_index": 0
              },
              {
                "start": 30600,
                "end": 42300,
                "day_index": 1
              },
              {
                "start": 30600,
                "end": 42300,
                "day_index": 2
              },
              {
                "start": 30600,
                "end": 42300,
                "day_index": 3
              },
              {
                "start": 30600,
                "end": 42300,
                "day_index": 4
              }
            ]
          }
        },
        {
          "id": "point_4",
          "priority": 2,
          "visits_number": 1,
          "minimum_lapse": 23,
          "type": "service",
          "activity": {
            "duration": 1200.0,
            "point_id": "point_4",
            "timewindows": [
              {
                "start": 28800,
                "end": 45000,
                "day_index": 0
              },
              {
                "start": 54000,
                "end": 63000,
                "day_index": 0
              },
              {
                "start": 28800,
                "end": 45000,
                "day_index": 1
              },
              {
                "start": 54000,
                "end": 63000,
                "day_index": 1
              },
              {
                "start": 28800,
                "end": 45000,
                "day_index": 2
              },
              {
                "start": 54000,
                "end": 63000,
                "day_index": 2
              },
              {
                "start": 28800,
                "end": 45000,
                "day_index": 3
              },
              {
                "start": 54000,
                "end": 63000,
                "day_index": 3
              },
              {
                "start": 28800,
                "end": 45000,
                "day_index": 4
              },
              {
                "start": 54000,
                "end": 63000,
                "day_index": 4
              }
            ]
          }
        },
        {
          "id": "point5",
          "priority": 2,
          "visits_number": 1,
          "minimum_lapse": 23,
          "type": "service",
          "activity": {
            "duration": 1800.0,
            "point_id": "point5",
            "timewindows": [
              {
                "start": 30600,
                "end": 45000,
                "day_index": 0
              },
              {
                "start": 50400,
                "end": 57600,
                "day_index": 0
              },
              {
                "start": 30600,
                "end": 45000,
                "day_index": 1
              },
              {
                "start": 50400,
                "end": 57600,
                "day_index": 1
              },
              {
                "start": 30600,
                "end": 45000,
                "day_index": 2
              },
              {
                "start": 50400,
                "end": 57600,
                "day_index": 2
              },
              {
                "start": 30600,
                "end": 45000,
                "day_index": 3
              },
              {
                "start": 50400,
                "end": 57600,
                "day_index": 3
              },
              {
                "start": 30600,
                "end": 45000,
                "day_index": 4
              },
              {
                "start": 50400,
                "end": 57600,
                "day_index": 4
              }
            ]
          }
        }
      ],
      "configuration": {
        "preprocessing": {
          "prefer_short_segment": true
        },
        "resolution": {
          "duration": 60000,
          "iterations": 50,
          "iterations_without_improvment": 30,
          "initial_time_out": 2160000,
          "time_out_multiplier": 1
        },
        "schedule": {
          "range_date": {
            "start": "2017-09-01",
            "end": "2017-09-30"
          }
        }
      }
    }
    vrp = Models::Vrp.create(problem)
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    assert_equal 1, result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:rest_id] }.size }.min
    assert_equal 1, result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:rest_id] }.size }.max
  end
end
