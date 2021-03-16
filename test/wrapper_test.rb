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

class WrapperTest < Minitest::Test
  def test_zip_cluster
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        rest_ids: ['rest_0']
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: 1,
              end: 2
            }]
          },
          skills: ['A']
        }
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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size # without start/end/rest
  end

  def test_no_zip_cluster
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  10, 20, 30,  0],
          [10, 0,  30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
        ],
        distance: [
          [0,  10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
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
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size # without start/end/rest
  end

  def test_no_zip_cluster_tws
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        rest_ids: ['rest_0']
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: i * 10,
              end: i * 10 + 1
            }],
            duration: 1
          }
        }
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size # without start/end/rest
  end

  def test_force_zip_cluster_with_quantities
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }, {
          id: 'unit1',
          label: 'kg'
      }, {
          id: 'unit2',
          label: 'kg'
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
        capacities: [{
          unit_id: 'unit0',
          limit: 5
        }, {
          unit_id: 'unit1',
          limit: 5
        }, {
          unit_id: 'unit2',
          limit: 5
        }]
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          quantities: [{
            unit_id: "unit#{i % 3}",
            value: 1
          }],
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, true).size
  end

  def test_force_zip_cluster_with_timewindows
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: i * 10,
              end: i * 10 + 10
            }]
          }
        }
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
    assert_equal 3, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, true).size
  end

  def test_zip_cluster_with_timewindows
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: i * 10,
              end: i * 10 + 10
            }]
          }
        }
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size
  end

  def test_zip_cluster_with_multiple_vehicles_and_duration
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        matrix_id: 'matrix_0'
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            duration: 1
          }
        }
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size
  end

  def test_zip_cluster_with_multiple_vehicles_without_duration
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        matrix_id: 'matrix_0'
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size
  end

  def test_zip_cluster_with_real_matrix
    size = 6
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,    693,  655,  1948, 693,  0],
          [609,  0,    416,  2070, 0,    609],
          [603,  489,  0,    1692, 489,  603],
          [1861, 1933, 1636, 0,    1933, 1861],
          [609,  0,    416,  2070, 0,    609],
          [0,    693,  655,  1948, 693,  0]
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
        end_point_id: 'point_' + (size - 1).to_s,
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 2)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            timewindows: [{
              start: 1,
              end: 2
            }],
            duration: 0
          },
          skills: ['A']
        }
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
    assert_equal 3, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size # without start/end/rest
  end

  def test_no_zip_cluster_with_real_matrix
    size = 6
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,    655,  1948, 5231, 2971, 0],
          [603,  0,    1692, 4977, 2715, 603],
          [1861, 1636, 0,    6143, 1532, 1861],
          [5184, 4951, 6221, 0,    7244, 5184],
          [2982, 2758, 1652, 7264, 0,    2982],
          [0,    655,  1948, 5231, 2971, 0]
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
        end_point_id: 'point_' + (size - 1).to_s,
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 2)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, TestHelper.create(problem), 5, false).size # without start/end/rest
  end

  def test_with_cluster
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
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
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    vrp = TestHelper.create(problem)
    [:ortools, :vroom].compact.each{ |o|
      result = OptimizerWrapper.solve(service: o, vrp: vrp)
      assert_equal size - 1 + 1, result[:routes][0][:activities].size, "[#{o}] "
      services = result[:routes][0][:activities].collect{ |a| a[:service_id] }
      1.upto(size - 1).each{ |i|
        assert_includes services, "service_#{i}", "[#{o}] Service missing: #{i}"
      }
      points = result[:routes][0][:activities].collect{ |a| a[:point_id] }
      assert_includes points, 'point_0', "[#{o}] Point missing: 0"
    }
  end

  def test_with_large_size_cluster
    size = 9
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 2, 3, 4, 5, 6, 7, 8],
          [1, 0, 2, 3, 4, 5, 6, 7, 8],
          [1, 2, 0, 3, 4, 5, 6, 7, 8],
          [1, 2, 3, 0, 4, 5, 6, 7, 8],
          [1, 2, 3, 4, 0, 5, 6, 7, 8],
          [1, 2, 3, 4, 5, 0, 6, 7, 8],
          [1, 2, 3, 4, 5, 6, 0, 7, 8],
          [1, 2, 3, 4, 5, 6, 7, 0, 8],
          [1, 2, 3, 4, 5, 6, 7, 8, 0]
        ],
        distance: [
          [0, 1, 2, 3, 4, 5, 6, 7, 8],
          [1, 0, 2, 3, 4, 5, 6, 7, 8],
          [1, 2, 0, 3, 4, 5, 6, 7, 8],
          [1, 2, 3, 0, 4, 5, 6, 7, 8],
          [1, 2, 3, 4, 0, 5, 6, 7, 8],
          [1, 2, 3, 4, 5, 0, 6, 7, 8],
          [1, 2, 3, 4, 5, 6, 0, 7, 8],
          [1, 2, 3, 4, 5, 6, 7, 0, 8],
          [1, 2, 3, 4, 5, 6, 7, 8, 0]
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
          end: 2
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_' + (size - 1).to_s,
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0']
      }],
      services: (1..(size - 2)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
            late_multiplier: 3,
            timewindows: [{
              start: 1,
              end: 2
            }]
          }
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 6
        },
        resolution: {
          duration: 10
        }
      }
    }
    original_stdout = $stdout
    $stdout = StringIO.new('', 'w')
    result = OptimizerWrapper.solve(service: :ortools, vrp: TestHelper.create(problem))
    traces = $stdout.string
    $stdout = original_stdout
    puts traces
    assert_match(/> iter /, traces, "Missing /> iter / in:\n " + traces)
    assert_equal size + 1, result[:routes][0][:activities].size # always return activities for start/end
    points = result[:routes][0][:activities].collect{ |a| a[:service_id] || a[:point_id] || a[:rest_id] }
    services_size = problem[:services].size
    services_size.times.each{ |i|
      assert_includes points, "service_#{i + 1}", "Element missing: #{i + 1}"
    }
  end

  def test_multiple_matrices
    size = 5
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  10, 20, 30,  0],
          [10, 0,  30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
        ],
        distance: [
          [0,  10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
        ]
      }, {
        id: 'matrix_1',
        time: [
          [0,  10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
        ],
        distance: [
          [0,  10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0,  10, 20, 30,  0]
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
        matrix_id: 'matrix_0'
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_1'
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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
    assert OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
  end

  def test_multiple_matrices_not_provided
    size = 5
    problem = {
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          location: {
            lat: 45,
            lon: Float(i) / 10
          }
        }
      },
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 0.9,
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        speed_multiplier: 0.8,
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
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

    Routers::RouterWrapper.stub_any_instance(:matrix, proc{ |_url, _mode, _dimensions, _row, _column, options|
      case options[:speed_multiplier]
      when 0.9
        [[
          [0, 762, 1553, 2075, 2477],
          [764, 0, 928, 1485, 1778],
          [1546, 924, 0, 740, 1409],
          [2072, 1474, 742, 0, 870],
          [2389, 1680, 1414, 876, 0]
        ], [
          [0, 10122.7, 18352.7, 27993.5, 43422],
          [10120, 0, 10568.6, 19167.3, 33204.4],
          [17964.1, 10568.6, 0, 10382.8, 21812],
          [27952.7, 19173.2, 10382.8, 0, 11933.3],
          [42505.7, 32281.2, 21890.3, 12025.4, 0]
        ]]
      when 0.8
        [[
          [0, 858, 1747, 2334, 2786],
          [859, 0, 1044, 1671, 2000],
          [1739, 1040, 0, 833, 1585],
          [2332, 1658, 835, 0, 979],
          [2687, 1890, 1590, 985, 0]
        ], [
          [0, 10122.7, 18352.7, 27993.5, 43422],
          [10120, 0, 10568.6, 19167.3, 33204.4],
          [17964.1, 10568.6, 0, 10382.8, 21812],
          [27952.7, 19173.2, 10382.8, 0, 11933.3],
          [42505.7, 32281.2, 21890.3, 12025.4, 0]
        ]]
      else
        raise 'Fix test if distance_matrix calculation has changed'
      end
    }) do
      assert OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
    end
  end

  def test_router_matrix_error
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 1000,
          lon: 1000
        }
      }, {
        id: 'point_1',
        location: {
          lat: 1000,
          lon: 1000
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_0'
        }
      }, {
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }

    assert_raises RouterError do
      Routers::RouterWrapper.stub_any_instance(:matrix, proc{ raise RouterError, 'STUB: Expectation Failed - RouterWrapper::OutOfSupportedAreaOrNotSupportedDimensionError' }) do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      end
    end
  end

  def test_router_invalid_parameter_combination_error
    problem = {
      points: [
        {
          id: 'point_0',
          location: {
            lat: 47,
            lon: 0
          }
        }, {
          id: 'point_1',
          location: {
            lat: 48,
            lon: 0
          }
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
        track: false,
        toll: false
      }],
      services: [
        {
          id: 'service_0',
          activity: {
            point_id: 'point_0'
          }
        }, {
          id: 'service_1',
          activity: {
            point_id: 'point_1'
          }
        }
      ],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        }
      }
    }

    assert_raises RouterError do
      Routers::RouterWrapper.stub_any_instance(:matrix, proc{ raise RouterError, 'STUB: Internal Server Error - OSRM request fails with: InvalidValue Exclude flag combination is not supported.' }) do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      end
    end
  end

  def test_geometry_polyline_encoded
    vrp = TestHelper.load_vrp(self)
    Routers::RouterWrapper.stub_any_instance(:compute_batch, proc{
      (0..vrp.vehicles.size - 1).collect{ |_| [0, 0, 'trace'] }
    }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_polyline
    vrp = TestHelper.load_vrp(self)
    Routers::RouterWrapper.stub_any_instance(:compute_batch, proc{
      (0..vrp.vehicles.size - 1).collect{ |_| [0, 0, 'trace'] }
    }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_route_single_activity
    vrp = TestHelper.load_vrp(self)
    Routers::RouterWrapper.stub_any_instance(:compute_batch, proc{
      (0..vrp.vehicles.size - 1).collect{ |_| [0, 0, 'trace'] }
    }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_with_rests
    vrp = TestHelper.load_vrp(self)
    Routers::RouterWrapper.stub_any_instance(:compute_batch, proc{
      (0..vrp.vehicles.size - 1).collect{ |_| [0, 0, 'trace'] }
    }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal 5, result[:routes][0][:activities].size
      refute_nil result[:routes][0][:geometry]
    end
  end

  def test_input_zones
    problem = {
      matrices: [{
        id: 'm1',
        time: [[0, 17523], [17510, 0]],
        distance: [[0, 376184], [379177, 0]]
      }],
      points: [{
        id: 'point_0', location: { lat: 48, lon: 5 }
      }, {
        id: 'point_1', location: { lat: 49, lon: 1 }
      }],
      zones: [{
        id: 'zone_0',
        polygon: {
          type: 'Polygon',
          coordinates: [[[0.5, 48.5], [1.5, 48.5], [1.5, 49.5], [0.5, 49.5], [0.5, 48.5]]]
        },
        allocations: [['vehicle_0']]
      }, {
        id: 'zone_1',
        polygon: {
          type: 'Polygon',
          coordinates: [[[4.5, 47.5], [5.5, 47.5], [5.5, 48.5], [4.5, 48.5], [4.5, 47.5]]]
        },
        allocations: [['vehicle_1']]
      }, {
        id: 'zone_2',
        polygon: {
          type: 'Polygon',
          coordinates: [[[2.5, 46.5], [4.5, 46.5], [4.5, 48.5], [2.5, 48.5], [2.5, 46.5]]]
        },
        allocations: [['vehicle_1']]
      }],
      vehicles: [{
        id: 'vehicle_0', start_point_id: 'point_0', speed_multiplier: 1, matrix_id: 'm1'
      }, {
        id: 'vehicle_1', start_point_id: 'point_0', speed_multiplier: 1, matrix_id: 'm1'
      }],
      services: [{
        id: 'service_0', activity: { point_id: 'point_0' }
      }, {
        id: 'service_1', activity: { point_id: 'point_1' }
      }],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        restitution: {
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }

    vrp = TestHelper.load_vrp(self, problem: problem)
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 2, result[:routes][1][:activities].size
  end

  def test_input_zones_shipment
    problem = {
      matrices: [{
        id: 'm1',
        time: [[0, 17523, 14676], [17510, 0, 10878], [14734, 10827, 0]],
        distance: [[0, 376184, 342286], [379177, 0, 255792], [352304, 252333, 0]]
      }],
      points: [{
        id: 'point_0', location: { lat: 48, lon: 5 }, matrix_index: 0 # zone_1
      }, {
        id: 'point_1', location: { lat: 49, lon: 1 }, matrix_index: 1 # zone_0
      }, {
        id: 'point_2', location: { lat: 50, lon: 3 }, matrix_index: 2 # no_zone
      }],
      zones: [{
        id: 'zone_0',
        polygon: {
          type: 'Polygon',
          coordinates: [[[0.5, 48.5], [1.5, 48.5], [1.5, 49.5], [0.5, 49.5], [0.5, 48.5]]]
        },
        allocations: [['vehicle_0']]
      }, {
        id: 'zone_1',
        polygon: {
          type: 'Polygon',
          coordinates: [[[4.5, 47.5], [5.5, 47.5], [5.5, 48.5], [4.5, 48.5], [4.5, 47.5]]]
        },
        allocations: [['vehicle_1']]
      }, {
        id: 'zone_2',
        polygon: {
          type: 'Polygon',
          coordinates: [[[2.5, 46.5], [4.5, 46.5], [4.5, 48.5], [2.5, 48.5], [2.5, 46.5]]]
        },
        allocations: [['vehicle_1']]
      }],
      vehicles: [{
        id: 'vehicle_0', start_point_id: 'point_0', speed_multiplier: 1, matrix_id: 'm1'
      }, {
        id: 'vehicle_1', start_point_id: 'point_0', speed_multiplier: 1, matrix_id: 'm1'
      }],
      services: [{
        id: 'service_0', activity: { point_id: 'point_1' }
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: { point_id: 'point_0' },
        delivery: { point_id: 'point_2' }
      }],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        restitution: {
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }

    vrp = TestHelper.load_vrp(self, problem: problem)
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_shipments_result
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0, 10, 20, 30,  0]
        ],
        distance: [
          [0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [0, 10, 20, 30,  0]
        ]
      }],
      points: [{
          id: 'point_0',
          matrix_index: 0
        }, {
          id: 'point_1',
          matrix_index: 1
        }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_1'
        }
      }],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }

    result = OptimizerWrapper.solve(service: :ortools, vrp: TestHelper.create(problem))
    assert result[:routes][0][:activities][1].has_key?(:pickup_shipment_id)
    refute result[:routes][0][:activities][1].has_key?(:delivery_shipment_id)

    refute result[:routes][0][:activities][2].has_key?(:pickup_shipment_id)
    assert result[:routes][0][:activities][2].has_key?(:delivery_shipment_id)
  end

  def test_split_vrps_using_two_solver
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ],
        distance: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ]
      }],
      points: [{
          id: 'point_0',
          matrix_index: 0,
        }, {
          id: 'point_1',
          matrix_index: 1,
        }, {
          id: 'point_2',
          matrix_index: 2,
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        speed_multiplier: 1.0,
        start_point_id: 'point_0',
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        speed_multiplier: 1.0,
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0
      }],
      services: [{
        id: 'service_1',
        sticky_vehicle_ids: ['vehicle_0'],
        activity: {
          point_id: 'point_1',
          duration: 600.0
        }
      }, {
        id: 'service_2',
        sticky_vehicle_ids: ['vehicle_1'],
        activity: {
          point_id: 'point_2',
          duration: 600.0
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:vroom, :ortools] }}, TestHelper.create(problem), nil)
    assert_equal 'vroom', result[:solvers][0]
    assert_equal 'ortools', result[:solvers][1]
  end

  def test_possible_no_service_too_far_time
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, result[:unassigned].size
  end

  def test_skills_sticky_compatibility
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ],
        distance: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ]
      }],
      points: [{
          id: 'point_0',
          matrix_index: 0,
        }, {
          id: 'point_1',
          matrix_index: 1,
        }, {
          id: 'point_2',
          matrix_index: 2,
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        speed_multiplier: 1.0,
        start_point_id: 'point_0',
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        speed_multiplier: 1.0,
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0
      }],
      services: [{
        id: 'service_1',
        sticky_vehicle_ids: ['vehicle_0'],
        activity: {
          point_id: 'point_1',
          duration: 600.0
        }
      }, {
        id: 'service_2',
        sticky_vehicle_ids: ['vehicle_1'],
        activity: {
          point_id: 'point_2',
          duration: 600.0
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, result[:unassigned].size

    problem[:services][0][:sticky_vehicle_ids] << 'vehicle_1'
    problem[:services].each{ |service|
      service[:skills] = ['A']
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, result[:unassigned].size # no vehicle has the skill, so there is no problem

    problem[:vehicles][0][:skills] = [['A']]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, (result[:unassigned].count{ |un| un[:reason] == 'Incompatibility between service skills and sticky vehicles' })
  end

  def test_impossible_service_too_far_time
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
          end: 10
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'Service cannot be served due to vehicle parameters -- e.g., timewindow, distance limit, etc.' })
  end

  def test_impossible_service_too_far_distance
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ],
        distance: [
          [0, 10, 1],
          [10, 0, 10],
          [6, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
          end: 30
        },
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        distance: 10
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'Service cannot be served due to vehicle parameters -- e.g., timewindow, distance limit, etc.' })
  end

  def test_impossible_service_capacity
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }, {
          id: 'unit1',
          label: 'kg'
      }, {
          id: 'unit2',
          label: 'kg'
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit0',
          limit: 5
        }, {
          unit_id: 'unit1',
          limit: 5
        }, {
          unit_id: 'unit2',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
            unit_id: 'unit0',
            value: 6
          }],
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, (result[:unassigned].count{ |un| un[:reason] == 'Service quantity greater than any vehicle capacity' })
  end

  def test_impossible_service_skills
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        skills: ['A']
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 0, result[:unassigned].size
  end

  def test_impossible_service_tw
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 6,
          end: 10
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [{
              start: 0,
              end: 5
          }]
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(1, result[:unassigned].count{ |un| un[:reason].include?('No vehicle with compatible timewindow') })
  end

  def test_impossible_service_duration
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 6,
          end: 10
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 6,
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, (result[:unassigned].count{ |un| un[:reason].include?('Service duration greater than any vehicle timewindow') })
  end

  def test_impossible_service_duration_with_sequence_tw
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        sequence_timewindows: [{
          start: 6,
          end: 10
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 6,
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 10
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, (result[:unassigned].count{ |un| un[:reason].include?('Service duration greater than any vehicle timewindow') })
  end

  def test_impossible_service_duration_with_two_vehicles
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 6,
          end: 10
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          duration: 6,
          point_id: 'point_1',
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_empty result[:unassigned]
  end

  def test_impossible_service_tw_periodic
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        sequence_timewindows: [
          { start: 6, end: 10, day_index: 2 },
          { start: 0, end: 5, day_index: 0 }
        ]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [
            { start: 0, end: 5, day_index: 1 }
          ]
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'No vehicle with compatible timewindow' })
  end

  def test_impossible_service_distance
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [2147483647, 2147483647, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'Unreachable' })
  end

  def test_service_unreachable_two_matrices
    vrp = VRP.basic
    vrp[:matrices] << {
      id: 'matrix_1',
      time: vrp[:matrices].first[:time].collect(&:dup)
    }
    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_bis'
    vrp[:vehicles].last[:matrix_id] = 'matrix_1'
    unassigned_services = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)[:unassigned]
    assert_empty(unassigned_services.select{ |un| un[:reason] == 'Unreachable' })

    vrp[:matrices][0][:time].each{ |line| line[2] = 2**32 }
    vrp[:matrices][0][:time][2] = (1..vrp[:matrices].first[:time][2].size).collect{ |_i| 2**32 }
    unassigned_services = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)[:unassigned]
    assert_empty(unassigned_services.select{ |un| un[:reason] == 'Unreachable' })

    vrp[:matrices][1][:time].each{ |line| line[2] = 2**32 }
    vrp[:matrices][1][:time][2] = (1..vrp[:matrices].first[:time][2].size).collect{ |_i| 2**32 }
    unassigned_services = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)[:unassigned]
    assert_equal 1, (unassigned_services.count{ |un| un[:reason] == 'Unreachable' })
    assert_equal 'service_2', unassigned_services.find{ |un| un[:reason] == 'Unreachable' }[:service_id]
  end

  def test_service_reachable_tricky_case
    vrp = VRP.basic
    vrp[:matrices] << {
      id: 'matrix_1',
      time: vrp[:matrices].first[:time].collect(&:dup)
    }
    vrp[:vehicles] << vrp[:vehicles].first.dup
    vrp[:vehicles].last[:id] += '_bis'
    vrp[:vehicles].last[:matrix_id] = 'matrix_1'
    # filling both half of matrix line 1 with big value :
    vrp[:matrices].each{ |matrice|
      max_indice = matrice[:time].size - 1
      half_indice = (max_indice / 2.0).ceil
      (half_indice..max_indice).each{ |index| matrice[:time][1][index] = 2**32 }
    }
    # at total, matrix size ( <=> one line) elements are equal to 2**32
    # but not on the same matrix so service should not be rejected (it used to be)
    unassigned_services = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)[:unassigned]
    assert_empty(unassigned_services.select{ |un| un[:reason] == 'Unreachable' })
  end

  def test_impossible_service_unconsistent_minimum_lapse
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
        }
      }],
      services: [{
        id: 'service_1',
        visits_number: 2,
        activity: {
          point_id: 'point_1'
        },
        minimum_lapse: 2
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        },
        schedule: {
          range_date: {
            start: Date.new(2017, 1, 27),
            end: Date.new(2017, 1, 28)
          }
        }
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal(2, result[:unassigned].count{ |un| un[:reason] == 'Unconsistency between visit number and minimum lapse' })
  end

  def test_wrong_matrix_and_points_definitions
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1, 1],
          [1, 0, 1, 1],
          [1, 1, 0, 1],
          [1, 1, 1, 0]
        ],
      }],
      points: [{
        id: 'point_0',
        location: {
            lat: 44.82332,
            lon: -0.607338
        }
      }, {
        id: 'point_1',
        location: {
            lat: 44.83395,
            lon: -0.56545
        }
      }, {
        id: 'point_2',
        location: {
            lat: 44.853662,
            lon: -0.568542
        }
      }, {
        id: 'point_3',
        location: {
            lat: 44.853662,
            lon: -0.568542
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        cost_time_multiplier: 1,
        start_point_id: 'point_2',
        end_point_id: 'point_3',
        matrix_id: 'matrix_0'
      }],
      services: [{
        id: 'service_0',
        sticky_vehicle_ids: ['vehicle_0'],
        activity: {
          point_id: 'point_0'
        }
      }, {
        id: 'service_1',
        sticky_vehicle_ids: ['vehicle_0'],
        activity: {
          point_id: 'point_1'
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }
    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_correctness_matrices_vehicles_and_points_definition
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_correctness_matrices_vehicles_and_points_definition
  end

  def test_unassigned_presence
    problem = {
      units: [{
        id: 'test',
        label: 'test'
      }],
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 5, 2**32],
          [5, 0, 2**32],
          [2**32, 2**32, 0]
        ],
        distance: [
          [0, 5, 2**32],
          [5, 0, 2**32],
          [2**32, 2**32, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        capacities: [{
          unit_id: 'test',
          limit: 1
        }],
        timewindow: {
          start: 0,
          end: 100
        }
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        cost_time_multiplier: 0,
        cost_distance_multiplier: 1,
        capacities: [{
          unit_id: 'test',
          limit: 1
        }],
        timewindow: {
          start: 0,
          end: 100
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'test',
          value: 1
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_1',
        },
        quantities: [{
          unit_id: 'test',
          value: 5
        }]
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_1',
          timewindows: [{
            start: 200,
            end: 205
          }]
        }
      }, {
        id: 'service_5',
        visits_number: 2,
        minimum_lapse: 1,
        activity: {
          point_id: 'point_1'
        }
      }],
      configuration: {
        preprocessing: {
          first_solution_strategy: ['local_cheapest_insertion']
        },
        resolution: {
          duration: 10
        },
        restitution: {
          intermediate_solutions: false,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 0
          }
        }
      }
    }

    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
    assert_equal 1, (result[:routes].sum{ |route| route[:activities].count{ |activity| activity[:service_id] } })
    assert_equal 5, result[:unassigned].size
  end

  def test_all_points_rejected_by_capacity
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        capacities: [{
          unit_id: 'unit0',
          limit: 2
        }],
        timewindow: {
          start: 0,
          end: 2
        }
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'unit0',
          value: 6
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'unit0',
          value: 3
        }]
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }
    Interpreters::PeriodicVisits.stub_any_instance(:expand, ->(vrp, _job, &_block){ vrp }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal 2, result[:unassigned].size
    end
  end

  def test_all_points_rejected_by_tw
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        timewindow: {
          start: 0,
          end: 2
        }
      }],
      services: [{
        id: 'service_1',
        visits_number: 2,
        activity: {
          point_id: 'point_1',
          timewindows: [{
              start: 3,
              end: 4
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
              start: 5,
              end: 6
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }
    Interpreters::PeriodicVisits.stub_any_instance(:expand, ->(vrp, _job, &_block){ vrp }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal 3, result[:unassigned].size
    end
  end

  def test_all_points_rejected_by_sequence_tw
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        sequence_timewindows: [
          { start: 6, end: 10, day_index: 2 },
          { start: 0, end: 5, day_index: 0 }
        ]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [
            { start: 3, end: 4, day_index: 1 }
          ]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [
            { start: 4, end: 5, day_index: 2 }
          ]
        }
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }

    Interpreters::PeriodicVisits.stub_any_instance(:expand, ->(vrp, _job, &_block){ vrp }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal 2, result[:unassigned].size
    end
  end

  def test_all_points_rejected_by_lapse
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 1, 1],
          [1, 0, 1],
          [1, 1, 0]
        ]
      }],
      units: [{
          id: 'unit0',
          label: 'kg'
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        sequence_timewindows: [
          { start: 6, end: 10, day_index: 2 },
          { start: 0, end: 5, day_index: 0 }
        ]
      }],
      services: [{
        id: 'service_1',
        visits_number: 2,
        minimum_lapse: 4,
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        visits_number: 4,
        minimum_lapse: 1,
        activity: {
          point_id: 'point_2'
        }
      }],
      configuration: {
        resolution: {
          duration: 10,
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 2
          }
        }
      }
    }

    Interpreters::PeriodicVisits.stub_any_instance(:expand, ->(vrp, _job, &_block){ vrp }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert_equal 6, result[:unassigned].size
    end
  end

  def test_impossible_service_too_long
    vrp = VRP.toy

    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))

    vrp[:vehicles].first[:timewindow] = {
      start: 0,
      end: 10
    }
    vrp[:services].first[:activity][:duration] = 15
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(1, result.count{ |un| un[:reason] == 'Service duration greater than any vehicle timewindow' })

    vrp[:vehicles].first[:timewindow] = nil
    vrp[:vehicles].first[:sequence_timewindows] = [{
      start: 0,
      end: 10
    }]
    vrp[:services].first[:activity][:duration] = 15
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(1, result.count{ |un| un[:reason] == 'Service duration greater than any vehicle timewindow' })

    vrp[:vehicles].first[:sequence_timewindows] << {
      start: 0,
      end: 20
    }
    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
  end

  def test_impossible_service_with_negative_quantity
    vrp = VRP.toy
    vrp[:services].first[:quantities] = [{ unit_id: 'u1', value: -5 }]
    vrp[:vehicles].first[:capacities] = [{ unit_id: 'u1', limit: 5 }]
    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))

    vrp[:services].first[:quantities].first[:value] = -6
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(1, result.count{ |un| un[:reason] == 'Service quantity greater than any vehicle capacity' })
  end

  def test_feasible_if_tardiness_allowed
    vrp = VRP.basic

    vrp[:vehicles].first[:timewindow] = { start: 0, end: 1 }
    assert_equal 3, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'All services (3) should be eliminated'

    vrp[:vehicles].first[:cost_late_multiplier] = 1
    assert_equal 0, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'No services should be eliminated due to vehicle timewindow since tardiness is allowed'

    vrp[:services].first[:activity][:timewindows] = [{ start: 0, end: 3 }]
    assert_equal 1, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'First service should be eliminated due its timewindow'

    vrp[:services].first[:activity][:late_multiplier] = 1
    assert_equal 0, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'First service should not be eliminated due to its timewindow since tardiness is allowed'
  end

  def test_return_empty_if_all_eliminated
    vrp = VRP.basic
    vrp[:vehicles].first[:timewindow] = { start: 0, end: 1 }
    vrp[:vehicles].first[:end_point_id] = vrp[:vehicles].first[:start_point_id]
    assert OptimizerWrapper.solve(service: :vroom, vrp: TestHelper.create(vrp))
  end

  def test_eliminate_even_if_no_start_or_end
    vrp = VRP.basic
    vrp[:vehicles].first[:timewindow] = { start: 0, end: 1 }

    vrp[:vehicles].first[:start_point_id] = nil
    vrp[:vehicles].first[:end_point_id] = 'point_0'
    assert_equal 2, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'Two services should be eliminated even if there is no vehicle start'

    vrp[:vehicles].first[:start_point_id] = 'point_0'
    vrp[:vehicles].first[:end_point_id] = nil
    assert_equal 3, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'All services (3) should be eliminated even if there is no vehicle end'

    vrp[:vehicles].first[:start_point_id] = nil
    vrp[:vehicles].first[:end_point_id] = nil
    vrp[:services].first[:activity][:duration] = 2
    assert_equal 1, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), []).size, 'First service should be eliminated even if there is no vehicle start nor end'
  end

  def test_work_day_entity_after_eventual_vehicle
    problem = VRP.lat_lon_scheduling_two_vehicles
    problem[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: :work_day
    }]
    assert_empty OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem))

    problem[:configuration][:preprocessing][:partitions] << {
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: :vehicle
    }
    assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)), :assert_vehicle_entity_only_before_work_day
  end

  def test_unfeasible_services
    problem = VRP.basic
    problem[:matrices][0][:time][1][0] = 900
    problem[:matrices][0][:time][1][2] = 900
    problem[:matrices][0][:time][2][1] = 900
    problem[:matrices][0][:time][1][3] = 900
    problem[:matrices][0][:time][3][1] = 900

    problem[:services][0] = {
      id: 'service_1',
      activity: {
        point_id: 'point_1',
        timewindows: [{
          start: 0,
          end: 2,
        }]
      }
    }
    problem[:vehicles] = [{
      id: 'vehicle_0',
      matrix_id: 'matrix_0',
      start_point_id: 'point_0',
      timewindow: {
        start: 0,
        end: 100
      }
    }]

    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
    assert_equal problem[:services].size,
                 result[:routes].sum{ |r| r[:activities].count{ |a| a[:service_id] } } + result[:unassigned].count{ |u| u[:service_id] }
  end

  def test_compute_several_solutions
    problem = VRP.basic
    problem[:configuration][:resolution][:several_solutions] = 2
    problem[:configuration][:resolution][:variation_ratio] = 25

    vrp = TestHelper.create(problem)
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
    assert_equal vrp.resolution_several_solutions, result.size
  end

  def test_add_unassigned
    vrp = TestHelper.create(VRP.scheduling)
    vrp[:services].first.visits_number = 4

    unfeasible = []

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][1], 'reason1')
    assert_equal 1, unfeasible.size

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][0], 'reason2')
    assert_equal 5, unfeasible.size

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][0], 'reason3')
    assert_equal 5, unfeasible.size
  end

  def test_default_repetition
    [[VRP.scheduling, nil, 1],
     [VRP.scheduling, [{ method: 'balanced_kmeans', metric: 'duration', entity: :vehicle }], 3],
     [VRP.basic, [{ method: 'balanced_kmeans', metric: 'duration', entity: :vehicle }], 1],
     [VRP.basic, nil, 1]
    ].each{ |problem_set|
      vrp, partition, expected_repetitions = problem_set

      solve_call = 0
      vrp = TestHelper.create(vrp)
      vrp.preprocessing_partitions = partition
      OptimizerWrapper.stub(:solve, lambda { |_vrp, _job, _block|
        solve_call += 1
        { routes: [], unassigned: vrp.services.collect{ |s| s }}
      }) do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
      end
      assert_equal expected_repetitions, solve_call,
        "#{expected_repetitions} repetitions expected, with#{vrp.preprocessing_partitions ? '' : 'no'} partitions and#{vrp.scheduling? ? '' : 'no'} scheduling"
    }
  end

  def test_skills_independent
    vrp = TestHelper.create(VRP.independent_skills)
    OptimizerWrapper.stub(:define_main_process, lambda { |services_vrps, _job_id|
      assert_equal 3, services_vrps.size
      services_vrps.each{ |service_vrp|
        assert_equal 2, service_vrp[:vrp].services.size
      }
    }) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
  end

  def test_impossible_minimum_lapse_opened_days
    vrp = VRP.lat_lon_scheduling_two_vehicles
    vrp[:services].first[:visits_number] = 2
    vrp[:services].first[:minimum_lapse] = 2

    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))

    vrp[:configuration][:schedule][:range_indices] = { start: 0, end: 2 }
    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    vrp[:vehicles].each{ |v| v[:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? } }
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(2, result.count{ |un| un[:reason] == 'Unconsistency between visit number and minimum lapse' })
    vrp[:vehicles].each{ |v| v[:sequence_timewindows].select{ |tw| tw[:day_index] == 2 }.each{ |tw| tw[:day_index] = 0 } }
    assert_equal(2, result.count{ |un| un[:reason] == 'Unconsistency between visit number and minimum lapse' })
  end

  def test_impossible_minimum_lapse_opened_days_real_case
    vrp = TestHelper.load_vrp(self, fixture_file: 'real_case_impossible_visits_because_lapse')
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(vrp)
    result.select!{ |un| un[:reason] == 'Unconsistency between visit number and minimum lapse' }
    result.collect!{ |un| un[:original_service_id] }
    result.uniq!
    assert_equal 12, result.size
  end

  def test_lapse_with_unavailable_work_days
    vrp = Marshal.load(File.binread('test/fixtures/check_lapse_with_unav_days_vrp.bindump')) # rubocop: disable Security/MarshalLoad

    refute vrp.can_affect_all_visits?(vrp.services.find{ |s| s.visits_number == 12 })
  end

  def test_detecting_unfeasible_services_can_not_take_too_long
    old_config_solve_repetition = OptimizerWrapper.config[:solve][:repetition]
    old_logger_level = OptimizerLogger.level # this is a perf test
    OptimizerLogger.level = :fatal # turn off output completely no matter the setting
    OptimizerWrapper.config[:solve][:repetition] = 1 # fix repetition to measure the perf correctly

    total_time = 0.0
    OptimizerWrapper.stub(
      :solve,
      lambda { |vrp_in, _job, block|
        vrp = vrp_in[:vrp]
        vrp.compute_matrix(&block)
        start = Time.now
        OptimizerWrapper.config[:services][:demo].check_distances(vrp, [])
        total_time += Time.now - start

        {
          routes: [],
          unassigned: vrp.services.flat_map{ |service|
            (1..service.visits_number).collect{ |visit|
              { service_id: "#{service.id}_#{visit}", detail: {}}
            }
          }
        }
      }
    ) do
      vrps = TestHelper.load_vrps(self, fixture_file: 'performance_12vl')

      vrps.each{ |vrp|
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      }
    end

    assert_operator total_time, :<=, 3.0, 'check_distances function took longer than expected'
  ensure
    OptimizerLogger.level = old_logger_level if old_logger_level
    OptimizerWrapper.config[:solve][:repetition] = old_config_solve_repetition if old_config_solve_repetition
  end

  def test_initial_route_with_infeasible_service
    # service_1 is eliminated due to
    # "Incompatibility between service skills and sticky vehicles"
    # but it is referenced inside an initial route which should not cause an issue
    problem = VRP.basic

    problem[:vehicles] += [{
      id: 'vehicle_1',
      matrix_id: 'matrix_0',
      start_point_id: 'point_0',
      skills: [['vehicle_1']]
    }]

    problem[:services][0][:skills] = ['vehicle_1']
    problem[:services][0][:sticky_vehicle_ids] = ['vehicle_0']

    problem[:routes] = [{
      vehicle_id: 'vehicle_0',
      mission_ids: ['service_1', 'service_2', 'service_3']
    }]

    assert OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
  end

  def test_solver_used_with_direct_shipment
    problem = VRP.pud
    problem[:shipments].first[:direct] = true

    generated_vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(generated_vrp), :assert_no_direct_shipments
    assert_empty OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(generated_vrp)
  end

  def test_check_distances_if_distance_and_time_with_lateness
    vrp = VRP.basic

    vrp[:matrices][0][:distance] = vrp[:matrices][0][:time]

    vrp[:vehicles].first[:cost_time_multiplier] = 1
    vrp[:vehicles].first[:cost_late_multiplier] = 1
    vrp[:vehicles].first[:cost_distance_multiplier] = 1
    vrp[:vehicles].first[:distance] = 1

    OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), [])
  end

  def test_number_of_service_vrps_generated_in_split_independent
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    services_vrps = OptimizerWrapper.split_independent_vrp_by_skills(vrp)
    assert_equal 5, services_vrps.size, 'Split_independent_vrp_by_skills function does not generate expected number of services_vrps'
    assert_equal vrp.resolution_duration, services_vrps.sum(&:resolution_duration)

    # add services that can not be served by any vehicle (different configurations)
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    vrp.services << Models::Service.new(id: 'fake_service_1', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    vrp.services << Models::Service.new(id: 'fake_service_2', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    services_vrps = OptimizerWrapper.split_independent_vrp_by_skills(vrp)
    assert_equal 6, services_vrps.size, 'Split_independent_vrp_by_skills function does not generate expected number of services_vrps'
    assert_equal vrp.resolution_duration, services_vrps.sum(&:resolution_duration)
    assert_equal 3, (services_vrps.count{ |s| s.resolution_duration.zero? })

    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    vrp.services << Models::Service.new(id: 'fake_service_1', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    vrp.services << Models::Service.new(id: 'fake_service_3', skills: ['fake_skill2'], activity: { point: vrp.points.first })
    services_vrps = OptimizerWrapper.split_independent_vrp_by_skills(vrp)
    assert_equal 7, services_vrps.size, 'Split_independent_vrp_by_skills function does not generate expected number of services_vrps'
    assert_equal vrp.resolution_duration, services_vrps.sum(&:resolution_duration)
    assert_equal 4, (services_vrps.count{ |s| s.resolution_duration.zero? })
  end

  def test_split_independent_vrps_with_useless_vehicle
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.vehicles << Models::Vehicle.new(id: 'useless_vehicle')
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal vrp.vehicles.size, result[:routes].size, 'All vehicles should appear in result, even though they can serve no service'
  end

  def test_split_independent_vrp_by_sticky_vehicle_with_useless_vehicle
    vrp = TestHelper.create(VRP.independent)
    vrp.vehicles << Models::Vehicle.new(id: 'useless_vehicle')
    expected_number_of_vehicles = vrp.vehicles.size
    services_vrps = OptimizerWrapper.split_independent_vrp_by_sticky_vehicle(vrp)
    assert_equal expected_number_of_vehicles, services_vrps.collect{ |sub_vrp| sub_vrp.vehicles.size }.sum, 'some vehicles disapear because of split_independent_vrp_by_sticky_vehicle function'
  end

  def test_ensure_original_id_provided_if_scheduling_optimization
    [['periodic', false], ['savings', true]].each{ |parameters|
      strategy, solver = parameters
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_andalucia2')
      vrp.preprocessing_first_solution_strategy = [strategy]
      vrp.resolution_duration = 6000
      vrp.resolution_solver = solver
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      refute_empty result[:unassigned]
      assert(result[:unassigned].all?{ |un| un[:original_service_id] })
      result[:routes].each{ |route|
        route[:activities].each{ |a|
          next unless a[:service_id]

          assert a[:original_service_id], 'Original ID is missing for service'
          refute_equal(a[:original_service_id], a[:service_id], 'Original ID should not be equal to internal ID')
        }
      }
      result[:routes].each{ |route|
        assert route[:vehicle_id]
        assert route[:original_vehicle_id]
        refute_equal(route[:vehicle_id], route[:original_vehicle_id], 'Original ID should not be equal to internal ID')
      }
    }
  end

  def test_consistency_between_current_and_total_route_distance
    vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)
    assert(result[:routes].all?{ |route| route[:activities].last[:current_distance] == route[:total_distance] })
  end

  def test_empty_result_when_no_vehicle
    [VRP.toy, VRP.pud].each{ |vrp|
      vrp = TestHelper.create(vrp)
      vrp.vehicles = []
      expected = vrp.visits
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_equal expected, result[:unassigned].size # automatically checked within define_process call
    }

    # ensure timewindows are returned even if they have work day
    vrp = VRP.scheduling
    vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
    vrp[:services][1][:activity][:timewindows] = [{ start: 30, end: 40, day_index: 5 }]
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    corresponding_in_route = result[:routes].collect{ |r|
      r[:activities].find{ |a| a[:original_service_id] == vrp[:services][0][:id] }
    }.first
    assert_equal [{ start: 0, end: 10, day_index: 0 }], corresponding_in_route[:detail][:timewindows]
    corresponding_unassigned = result[:unassigned].find{ |un| un[:original_service_id] == vrp[:services][1][:id] }
    assert_equal [{ start: 30, end: 40, day_index: 5 }], corresponding_unassigned[:detail][:timewindows]
  end

  def test_empty_result_when_no_mission
    vrp = TestHelper.create(VRP.lat_lon_two_vehicles)
    vrp.services = []
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal 2, result[:routes].size

    vrp = TestHelper.create(VRP.scheduling)
    vrp.services = []
    expected_days = vrp.schedule_range_indices[:end] - vrp.schedule_range_indices[:start] + 1
    nb_vehicles = vrp.vehicles.size
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal expected_days * nb_vehicles, result[:routes].size
  end

  def test_assert_inapplicable_for_vroom_if_vehicle_distance
    problem = VRP.basic
    problem[:vehicles].first[:distance] = 10

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_distance_limitation
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_distance_limitation
  end

  def test_assert_inapplicable_vroom_with_periodic_heuristic
    problem = VRP.scheduling
    problem[:services].first[:visits_number] = 2

    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(TestHelper.create(problem)), :assert_only_one_visit
  end

  def test_assert_applicable_for_vroom_if_initial_routes
    problem = VRP.basic
    problem[:routes] = [{
      mission_ids: ['service_1']
    }]
    vrp = TestHelper.create(problem)
    assert_empty OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp)
  end

  def test_assert_inapplicable_relations
    problem = VRP.basic
    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: [],
      linked_vehicle_ids: [],
      lapse: 1
    }]

    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_relations
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_relations

    problem[:relations] = [{
      type: 'vehicle_group_duration',
      linked_ids: ['vehicle_0'],
      linked_vehicle_ids: [],
      lapse: 1
    }]

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_relations
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_relations
  end

  def test_solver_needed
    problem = VRP.basic
    problem[:configuration][:resolution][:solver] = false

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_solver
    assert_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_solver_if_not_periodic
  end

  def test_first_solution_acceptance_with_solvers
    problem = VRP.basic
    problem[:configuration][:preprocessing][:first_solution_strategy] = [1]

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_first_solution_strategy
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_first_solution_strategy
  end

  def test_reject_when_duplicated_ids
    vrp = VRP.toy
    vrp[:services] << vrp[:services].first

    assert_raises OptimizerWrapper::DiscordantProblemError do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
    end
  end
end
