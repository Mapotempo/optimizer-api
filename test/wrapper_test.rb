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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
              maximum_lateness: 10,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
        }
      }
    }

    assert_raises RouterError do
      Routers::RouterWrapper.stub_any_instance(:matrix, proc{
        raise RouterError.new('STUB: Expectation Failed - RouterWrapper::OutOfSupportedAreaOrNotSupportedDimensionError')
      }) do
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
          duration: 20,
        }
      }
    }

    assert_raises RouterError do
      Routers::RouterWrapper.stub_any_instance(:matrix, proc{
        raise RouterError.new('STUB: Internal Server Error - OSRM request fails with: InvalidValue Exclude flag combination is not supported.')
      }) do
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
        id: 'point_0', location: { lat: 48, lon: 5 }, matrix_index: 0
      }, {
        id: 'point_1', location: { lat: 49, lon: 1 }, matrix_index: 1
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
    assert_equal 1, (result[:unassigned].count{ |un| un[:reason].include?('No vehicle available for this service') })
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
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'No compatible vehicle can reach this service while respecting all constraints' })
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
    assert_equal(1, result[:unassigned].count{ |un| un[:reason] == 'No compatible vehicle can reach this service while respecting all constraints' })
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
    vrp = VRP.periodic
    vrp[:vehicles].first.delete(:timewindow)
    vrp[:vehicles].first[:sequence_timewindows] = [
      { start: 6, end: 10, day_index: 2 },
      { start: 0, end: 5, day_index: 0 }
    ]
    vrp[:services].first[:activity][:timewindows] = [{ start: 0, end: 5, day_index: 1 }]
    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
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

  def test_impossible_service_inconsistent_minimum_lapse
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
    assert_equal(2, result[:unassigned].count{ |un| un[:reason] == 'Inconsistency between visit number and minimum lapse' })
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

  def test_activity_position_presence
    problem = VRP.basic
    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_activity_with_position
    refute_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_activity_with_position

    problem[:services].first[:activity][:position] = 'always_last'
    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp), :assert_no_activity_with_position
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp), :assert_no_activity_with_position
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
          duration: 20,
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
    assert_equal(1, result.values.flatten.count{ |un| un[:reason] == 'Service duration greater than any vehicle timewindow' })

    vrp[:vehicles].first[:timewindow] = nil
    vrp[:vehicles].first[:sequence_timewindows] = [{
      start: 0,
      end: 10
    }]
    vrp[:services].first[:activity][:duration] = 15
    vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }}
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(1, result.values.flatten.count{ |un| un[:reason] == 'Service duration greater than any vehicle timewindow' })

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
    assert_equal(1, result.values.flatten.count{ |un| un[:reason] == 'Service quantity greater than any vehicle capacity' })
  end

  def test_feasible_if_tardiness_allowed
    vrp = VRP.basic

    vrp[:vehicles].first[:timewindow] = { start: 0, end: 1 }
    assert_equal 3, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'All services (3) should be eliminated'

    vrp[:vehicles].first[:cost_late_multiplier] = 1
    assert_equal 3, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'All services (3) should be eliminated since maximum_lateness is too low even tough tardiness is allowed'

    vrp[:vehicles].first[:timewindow][:maximum_lateness] = 10 # eliminates no services
    assert_equal 0, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'No services should be eliminated due to vehicle timewindow since tardiness is allowed'

    vrp[:vehicles].first[:timewindow][:maximum_lateness] = 3 # eliminates service 2 and 3 but not 1
    assert_equal 2, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'Only Services 2 and 3 should be eliminated'

    vrp[:services].first[:activity][:timewindows] = [{ start: 0, end: 3 }]
    vrp[:vehicles].first[:timewindow][:maximum_lateness] = 10
    assert_equal 1, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'First service should be eliminated due its timewindow'

    vrp[:services].first[:activity][:late_multiplier] = 1
    assert_equal 0, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'First service should not be eliminated due to its timewindow since tardiness is allowed'

    vrp[:services].first[:activity][:timewindows].first[:maximum_lateness] = 0
    assert_equal 1, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size, 'First service should be eliminated due to its timewindow even if tardiness is allowed since maximum_lateness is not enough'
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
    assert_equal 2, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size,
                 'Two services should be eliminated even if there is no vehicle start'

    vrp[:vehicles].first[:start_point_id] = 'point_0'
    vrp[:vehicles].first[:end_point_id] = nil
    assert_equal 3, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size,
                 'All services (3) should be eliminated even if there is no vehicle end'

    vrp[:vehicles].first[:start_point_id] = nil
    vrp[:vehicles].first[:end_point_id] = nil
    vrp[:services].first[:activity][:duration] = 2
    assert_equal 1, OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size,
                 'First service should be eliminated even if there is no vehicle start nor end'
  end

  def test_work_day_entity_after_eventual_vehicle
    problem = VRP.lat_lon_periodic_two_vehicles
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
    vrp = TestHelper.create(VRP.periodic)
    vrp[:services].first.visits_number = 4

    unfeasible = {}

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][1], 'reason1')
    assert_equal 1, unfeasible.values.flatten.size

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][0], 'reason2')
    assert_equal 5, unfeasible.values.flatten.size

    unfeasible = OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible, vrp, vrp[:services][0], 'reason3')
    assert_equal 5, unfeasible.values.flatten.size
  end

  def test_add_unassigned_respects_relations
    assert_equal %i[shipment sequence meetup].sort, Models::Relation::ALL_OR_NONE_RELATIONS.sort

    problem = VRP.lat_lon
    service_zero = Oj.load(Oj.dump(problem[:services].first))
    service_zero[:id] = 'service_0'
    problem[:services].insert(0, service_zero)
    services_demo = OptimizerWrapper.config[:services][:demo]

    # no relation
    vrp = TestHelper.create(problem)
    assert_equal 1, services_demo.add_unassigned({}, vrp, vrp[:services][0], 'reason').values.flatten.size

    # all 7 services in one relation type become unfeasible at the same time
    Models::Relation::ALL_OR_NONE_RELATIONS.each{ |relation_type|
      linked_ids_size = relation_type == :shipment ? 2 : problem[:services].size
      problem[:relations] = [{ type: relation_type, linked_ids: problem[:services][0..linked_ids_size-1].collect{ |s| s[:id] } }]
      vrp = TestHelper.create(problem)
      assert_equal linked_ids_size, services_demo.add_unassigned({}, vrp, vrp[:services][0], 'reason').values.flatten.size
    }

    # 2 services in shipment, 2 in meetup, which are connected by sequence becomes unfeasible at the same time
    problem[:relations] = [
      { type: :shipment, linked_ids: problem[:services][0..1].collect{ |s| s[:id] } },
      { type: :meetup, linked_ids: problem[:services][2..3].collect{ |s| s[:id] } },
      { type: :sequence, linked_ids: [0, 2].collect{ |s| problem[:services][s][:id] } },
      { type: :shipment, linked_ids: problem[:services][5..6].collect{ |s| s[:id] } },
    ]
    vrp = TestHelper.create(problem)
    unassigned = {}
    assert_equal 2, services_demo.add_unassigned(unassigned, vrp, vrp[:services][5], 'reason').values.flatten.size # only 1 shipment
    services_demo.add_unassigned(unassigned, vrp, vrp[:services][0], 'reason') # shipment + meetup
    assert_equal 6, unassigned.values.flatten.size
    in_relation_msg = 'In a relation with an unfeasible service: '
    expected_reasons = { service_0: 'reason', service_1: "#{in_relation_msg}service_0",
                         service_2: "#{in_relation_msg}service_0", service_3: "#{in_relation_msg}service_2",
                         service_5: 'reason', service_6: "#{in_relation_msg}service_5" }
    assert_equal expected_reasons, unassigned.values.flatten.collect{ |u| [u[:service_id], u[:reason]] }.to_h.symbolize_keys
  end

  def test_default_repetition
    [[VRP.periodic, nil, 1],
     [VRP.periodic, [{ method: 'balanced_kmeans', metric: 'duration', entity: :vehicle }], 3],
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
                   "#{expected_repetitions} repetitions expected, with#{vrp.preprocessing_partitions ? '' : 'no'} partitions and #{vrp.schedule? ? '' : 'no'} periodic"
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
    vrp = VRP.lat_lon_periodic_two_vehicles
    vrp[:services].first[:visits_number] = 2
    vrp[:services].first[:minimum_lapse] = 2

    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))

    vrp[:configuration][:schedule][:range_indices] = { start: 0, end: 2 }
    assert_empty OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))

    vrp[:vehicles].each{ |v| v[:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? } }
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(2, result.values.flatten.count{ |un| un[:reason] == 'Inconsistency between visit number and minimum lapse' })

    vrp[:vehicles].each{ |v| v[:sequence_timewindows].select{ |tw| tw[:day_index] == 2 }.each{ |tw| tw[:day_index] = 0 } }
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal(2, result.values.flatten.count{ |un| un[:reason] == 'Inconsistency between visit number and minimum lapse' })
  end

  def test_impossible_minimum_lapse_opened_days_real_case
    vrp = TestHelper.load_vrp(self, fixture_file: 'real_case_impossible_visits_because_lapse')
    result = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(vrp)
    assert_equal 12, (result.count{ |_o_s_id, uns| uns.any?{ |un| un[:reason] == 'Inconsistency between visit number and minimum lapse' }})
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

    total_detect_unfeasible_services_time = 0.0
    total_check_distances_time = 0.0
    total_add_unassigned_time = 0.0
    OptimizerWrapper.stub(
      :solve,
      lambda { |vrp_in, _job, block|
        vrp = vrp_in[:vrp]

        start = Time.now
        unfeasible_services = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(vrp)
        total_detect_unfeasible_services_time += Time.now - start

        vrp.compute_matrix(&block)

        start = Time.now
        OptimizerWrapper.config[:services][:demo].check_distances(vrp, unfeasible_services)
        total_check_distances_time += Time.now - start

        # In these vrps, there is no unfeasible service, manually calling the add_unassigned
        # for all services to check add_unassigned performance correctly
        start = Time.now
        vrp.services.each{ |service|
          OptimizerWrapper.config[:services][:demo].add_unassigned(unfeasible_services, vrp, service, 'reason')
        }
        total_add_unassigned_time += Time.now - start

        { routes: [], unassigned: unfeasible_services.values.flatten }
      }
    ) do
      vrps = TestHelper.load_vrps(self, fixture_file: 'performance_12vl')

      vrps.each{ |vrp|
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      }
    end

    # The time limits down below should be relax enough to take into account github performance variation. If any one of
    # them is violated "marginally" (without any change in the infeasibility detection logic) then the limits can be
    # corrected/increased. On local, the total_times are almost half the limits.
    # The goal of this test is to prevent adding an involuntary exponential logic and the limits can increase linearly
    # if more verifications are added but the time should not jump orders of magnitude.
    assert_operator total_check_distances_time, :<=, 3.3, 'check_distances function took longer than expected'
    assert_operator total_add_unassigned_time, :<=, 6.6, 'add_unassigned function took longer than expected'
    assert_operator total_detect_unfeasible_services_time, :<=, 8.8, 'detect_unfeasible_services function took too long'
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
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(generated_vrp),
                    :assert_no_relations_except_simple_shipments
    assert_empty OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(generated_vrp)
  end

  def test_check_distances_if_distance_and_time_with_lateness
    vrp = VRP.basic

    vrp[:matrices][0][:distance] = vrp[:matrices][0][:time]

    vrp[:vehicles].first[:cost_time_multiplier] = 1
    vrp[:vehicles].first[:cost_late_multiplier] = 1
    vrp[:vehicles].first[:cost_distance_multiplier] = 1
    vrp[:vehicles].first[:distance] = 1

    assert_equal 3,
                 OptimizerWrapper.config[:services][:demo].check_distances(TestHelper.create(vrp), {}).values.flatten.size,
                 "all should be infeasible due to distance constraint"
  end

  def test_split_independent_vrp_does_not_reset_relations
    problem = VRP.independent_skills
    # The following pairs of services (those in the same relation) would stay on the same vehicle
    # after the split_independent_vrp even without the relations (they are forced by skills).
    # Here we test only if the relations passed correctly to sub-problems after split_independent_vrp.
    # split_independent_vrp does not take into account relations during split.
    # If the services are not feasible in the first place
    # -- i.e., both services of the same relation cannot be served on the same vehicle --
    # then split cannot do anything but split these services into different sub-problems.
    problem[:relations] = [
      { type: :shipment, linked_ids: ['service_2', 'service_4'] },
      { type: :same_route, linked_ids: ['service_3', 'service_5'] },
      { type: :sequence, linked_ids: ['service_1', 'service_6'] },
    ]

    vrp = TestHelper.create(problem)
    vrp.matrices = nil
    split_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 3, split_vrps.size, 'split_independent_vrp function does not generate expected number of split_vrps'
    expected_split = [
      [['vehicle_0'], ['service_2', 'service_4']],
      [['vehicle_1'], ['service_3', 'service_5']],
      [['vehicle_2'], ['service_1', 'service_6']],
    ]
    assert_equal expected_split, split_vrps.map{ |sv| [sv.vehicles.map(&:id).sort, sv.services.map(&:id)] }.sort
    assert_in_delta split_vrps.sum(&:resolution_duration), vrp.resolution_duration, split_vrps.size
    assert_equal 0, (split_vrps.count{ |s| s.resolution_duration.zero? })

    expected_relations = problem[:relations].map{ |r| r[:linked_ids] }.sort
    actual_relation = split_vrps.map{ |svrp| svrp.relations.flat_map(&:linked_ids) }.sort
    assert_equal expected_relations, actual_relation, 'split_independent_vrp should keep relations'
  end

  def test_split_independent_vrp_generates_correct_split_vrps
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    split_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 3, split_vrps.size, 'split_independent_vrp function does not generate expected number of split_vrps'
    expected_split = [
      [['vehicle_0'], ['service_2', 'service_4']],
      [['vehicle_1'], ['service_3', 'service_5']],
      [['vehicle_2'], ['service_1', 'service_6']],
    ]
    assert_equal expected_split, split_vrps.map{ |sv| [sv.vehicles.map(&:id).sort, sv.services.map(&:id)] }.sort
    assert_in_delta split_vrps.sum(&:resolution_duration), vrp.resolution_duration, split_vrps.size
    assert_equal 0, (split_vrps.count{ |s| s.resolution_duration.zero? })

    # add services that can not be served by any vehicle (different configurations)
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    vrp.services << Models::Service.create(id: 'fake_service_1', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    vrp.services << Models::Service.create(id: 'fake_service_2', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    split_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 4, split_vrps.size, 'split_independent_vrp function does not generate expected number of split_vrps'
    expected_split.unshift [[], ['fake_service_1', 'fake_service_2']]
    assert_equal expected_split, split_vrps.map{ |sv| [sv.vehicles.map(&:id).sort, sv.services.map(&:id)] }.sort
    assert_in_delta split_vrps.sum(&:resolution_duration), vrp.resolution_duration, split_vrps.size
    assert_equal 1, (split_vrps.count{ |s| s.resolution_duration.zero? })

    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    vrp.services << Models::Service.create(id: 'fake_service_1', skills: ['fake_skill1'], activity: { point: vrp.points.first })
    vrp.services << Models::Service.create(id: 'fake_service_3', skills: ['fake_skill2'], activity: { point: vrp.points.first })
    split_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 5, split_vrps.size, 'split_independent_vrp function does not generate expected number of split_vrps'
    expected_split.shift
    expected_split.unshift [[], ['fake_service_3']]
    expected_split.unshift [[], ['fake_service_1']]
    assert_equal expected_split, split_vrps.map{ |sv| [sv.vehicles.map(&:id).sort, sv.services.map(&:id)] }.sort
    assert_in_delta split_vrps.sum(&:resolution_duration), vrp.resolution_duration, split_vrps.size
    assert_equal 2, (split_vrps.count{ |s| s.resolution_duration.zero? })

    vrp = TestHelper.create(VRP.independent_skills)
    vrp.matrices = nil
    vrp.services[1].skills = [:D]
    split_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 2, split_vrps.size, 'split_independent_vrp function does not generate expected number of split_vrps'
    expected_split = [
      [['vehicle_0', 'vehicle_1'], ['service_2', 'service_3', 'service_4', 'service_5']],
      [['vehicle_2'], ['service_1', 'service_6']],
    ]
    assert_equal expected_split, split_vrps.map{ |sv| [sv.vehicles.map(&:id).sort, sv.services.map(&:id)] }.sort
    assert_in_delta split_vrps.sum(&:resolution_duration), vrp.resolution_duration, split_vrps.size
    assert_equal 0, (split_vrps.count{ |s| s.resolution_duration.zero? })
  end

  def test_split_independent_with_trip_relation
    problem = VRP.independent
    problem[:vehicles].first[:end_point_id] = problem[:vehicles].first[:start_point_id]
    problem[:relations] = [{
      type: :vehicle_trips,
      linked_vehicle_ids: ['vehicle_0', 'vehicle_1']
    }]
    vrp = TestHelper.create(problem)

    vrp.matrices = nil
    services_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal 1, services_vrps.size, 'split_independent_vrp function does not generate expected number of services_vrps'
    assert_equal vrp.resolution_duration, services_vrps.sum(&:resolution_duration)
  end

  def test_split_independent_skills_with_trip_relation
    problem = VRP.independent_skills

    problem[:vehicles][1][:end_point_id] = problem[:vehicles].first[:start_point_id]
    problem[:vehicles][1][:skills] = [[]] # vehicle_1

    # WITHOUT vehicle_trips
    vrp = TestHelper.create(problem)
    independent_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    # 5 independent vrps
    # one with v0
    # one with v2
    # one without vehicle for "infeasible" service_3
    # one without vehicle for "infeasible" service_5 (this and the previous one can be in the same sub-vrp eventually)
    # one with v1 and without services because it cannot serve any
    assert_equal 5, independent_vrps.size,
                 'split_independent_vrp function does not generate expected number of independent_vrps'

    expected_vehicles = [["vehicle_0"], ["vehicle_2"], [], [], ["vehicle_1"]]
    expected_services = [["service_2", "service_4"], ["service_1", "service_6"], ["service_3"], ["service_5"], []]
    assert_equal expected_vehicles.sort, independent_vrps.map{ |i| i.vehicles.map(&:id) }.sort
    assert_equal expected_services.sort, independent_vrps.map{ |i| i.services.map(&:id).sort }.sort

    # INTERIM CHECK
    problem[:relations] = [{ type: :vehicle_trips, linked_vehicle_ids: ['vehicle_1', 'vehicle_2'] }]
    vrp = TestHelper.create(problem)
    independent_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    msg = "Waiting for split_independent_vrp forcing relation implementation. This INTERIM CHECK part can be "\
          "deleted upto the skip and the rest of the test with vehicle_trips can be activated."
    assert_equal 1, independent_vrps.size,
                 'split_independent_vrp function does not generate expected number of independent_vrps' + msg
    skip msg

    # WITH vehicle_trips
    problem[:relations] = [{ type: :vehicle_trips, linked_vehicle_ids: ['vehicle_1', 'vehicle_2'] }]
    vrp = TestHelper.create(problem)
    independent_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    # 4 independent vrps
    # one with v0
    # one with v1 and v2 (because of vehicle trips relation otherwise v1 would be in a separate "empty" sub-problem)
    # one without vehicle for "infeasible" service_3
    # one without vehicle for "infeasible" service_5 (this and the previous one can be in the same sub-vrp eventually)
    assert_equal 4, independent_vrps.size,
                'split_independent_vrp function does not generate expected number of independent_vrps'

    expected_vehicles = [["vehicle_0"], ["vehicle_1", "vehicle_2"], [], []]
    expected_services = [["service_2", "service_4"], ["service_1", "service_6"], ["service_3"], ["service_5"]]
    assert_equal expected_vehicles.sort, independent_vrps.map{ |i| i.vehicles.map(&:id) }.sort
    assert_equal expected_services.sort, independent_vrps.map{ |i| i.services.map(&:id).sort }.sort
  end

  def test_split_independent_vrps_with_useless_vehicle
    vrp = TestHelper.create(VRP.independent_skills)
    vrp.vehicles << Models::Vehicle.create(id: 'useless_vehicle')
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    assert_equal vrp.vehicles.size, result[:routes].size, 'All vehicles should appear in result, even though they can serve no service'
  end

  def test_split_independent_vrp_by_sticky_vehicle_with_useless_vehicle
    vrp = TestHelper.create(VRP.independent)
    vrp.vehicles << Models::Vehicle.create(id: 'useless_vehicle')
    expected_number_of_vehicles = vrp.vehicles.size
    services_vrps = OptimizerWrapper.split_independent_vrp(vrp)
    assert_equal expected_number_of_vehicles, services_vrps.collect{ |sub_vrp| sub_vrp.vehicles.size }.sum, 'some vehicles disapear because of split_independent_vrp_by_sticky_vehicle function'
  end

  def test_ensure_original_id_provided_if_periodic_optimization
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
    vrp = VRP.periodic
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

    vrp = TestHelper.create(VRP.periodic)
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
    problem = VRP.periodic
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

  def test_assert_can_handle_empty_quantities
    problem = VRP.basic
    problem[:relations] = [{
      type: :shipment,
      linked_ids: ['service_1', 'service_2']
    }]
    problem[:units] << { id: 'vol' }
    problem[:vehicles].first[:capacities] = [{ unit_id: 'kg', limit: 2 }, { unit_id: 'vol', limit: 1 }]
    problem[:services][0][:quantities] = [{ unit_id: 'kg', value: 1 }]
    problem[:services][1][:quantities] = [{ unit_id: 'kg', value: -1 }]
    problem[:services][2][:quantities] = [{ unit_id: 'vol', value: 1 }]
    vrp = TestHelper.create(problem)

    OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp)
    OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp)
  end

  def test_assert_inapplicable_relations
    problem = VRP.basic
    problem[:relations] = [{
      type: :vehicle_group_duration,
      linked_vehicle_ids: ['vehicle_0']
    }, {
      type: :shipment,
      linked_ids: ['service_1', 'service_2']
    }]

    assert_raises OptimizerWrapper::DiscordantProblemError do
      TestHelper.create(problem)
    end
    problem[:relations] = [problem[:relations][1]]
    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments

    problem[:relations] = [{
      type: :vehicle_group_duration,
      linked_vehicle_ids: ['vehicle_0'],
      lapses: [1]
    }]

    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_overall_duration
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments
    refute_includes OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments

    problem = VRP.basic
    problem[:relations] = [{
      type: :shipment,
      linked_ids: ['service_1', 'service_2']
    }]
    problem[:vehicles].first[:capacities] = [{ unit_id: 'kg', limit: 2 }]
    problem[:services][0][:quantities] = [{ unit_id: 'kg', value: 1 }]
    problem[:services][1][:quantities] = [{ unit_id: 'kg', value: -1 }]
    vrp = TestHelper.create(problem)
    refute_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments

    problem[:services][0][:quantities] = [{ unit_id: 'kg', value: nil }]
    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments

    problem[:services][1][:quantities] = [{ unit_id: 'kg', value: 2 }]
    vrp = TestHelper.create(problem)
    assert_includes OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp),
                    :assert_no_relations_except_simple_shipments
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

  def test_vroom_cannot_be_called_synchronously_if_max_split_lower_than_services_size
    problem = VRP.lat_lon_two_vehicles
    assert_empty OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(TestHelper.create(problem))
    assert OptimizerWrapper.config[:services][:vroom].solve_synchronous?(TestHelper.create(problem))

    problem[:configuration][:preprocessing] = { max_split_size: 2 }
    assert_empty OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(TestHelper.create(problem))
    refute OptimizerWrapper.config[:services][:vroom].solve_synchronous?(TestHelper.create(problem))
  end

  def test_simplify_constraints_simplifies_pause
    problem = VRP.toy
    problem[:rests] = [{ id: 'rest_0', timewindows: [{ start: 1, end: 10 }], duration: 1 }]
    problem[:vehicles].first[:rest_ids] = ['rest_0']

    vrp = TestHelper.create(problem)
    original_rests = vrp.vehicles.first.rests.dup
    assert original_rests, 'Original vehicle should have a rest'

    vrp = OptimizerWrapper.config[:services][:demo].simplify_constraints(vrp)
    assert vrp.vehicles.first.rests.none?, 'Simplification should have removed this rest'
    assert vrp.vehicles.first[:rest_ids].none?
    assert_equal original_rests, vrp.vehicles.first[:simplified_rests]
    assert_equal original_rests.collect(&:id).sort, vrp.vehicles.first[:simplified_rests].map(&:id).sort

    problem[:vehicles].first[:timewindow] = { start: 0, end: 100 }
    problem[:vehicles].first[:cost_late_multiplier] = 0.3
    vrp = OptimizerWrapper.config[:services][:demo].simplify_constraints(TestHelper.create(problem))
    refute vrp.vehicles.first.rests.none?, 'Should not have removed this rest because there is cost_late_multiplier'
  end

  def test_simplified_pause_returns_the_same_cost
    # TODO: instance needs to be replaced with an appropriate local instance with a matrix and the dump can be deleted
    # The instance needs at least:
    #  - a vehicle without a start and an end (and the opposite)
    #  - a vehicle with a start but without an end (and the opposite)
    #  - some vehicles to be with force_start and some not
    #  - some pauses with and without TW
    #  - some pauses that will be simplified and some not simplified (due to conditions) (and verified in the test)
    #  - a route that has a natural solution where the pause needs to be inserted after all services
    vrp = TestHelper.load_vrp(self, fixture_file: 'problem_w_pause_that_can_be_simplified')

    # solve WITH simplification
    result_w_simplification = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    # check if all rests respect their TWs (duplicated below)
    result_w_simplification[:routes].each{ |route|
      planned_rest = route[:activities].find{ |a| a[:type] == 'rest' }

      rest_id = vrp.vehicles.find{ |v| v[:id] == route[:vehicle_id] }[:rest_ids].first
      rest = vrp.rests.find{ |r| r[:id] == rest_id }
      assert rest, 'Simplification should put back the original rests'

      assert_operator planned_rest[:begin_time], :>=, rest.timewindows[0].start, 'Rest violates its timewindow.start'
      assert_operator planned_rest[:begin_time], :<=, rest.timewindows[0].end, 'Rest violates its timewindow.end'
    }

    # solve WITHOUT simplification but from the last solution with evaluate_only
    result_wo_simplification = Wrappers::Wrapper.stub_any_instance(:simplify_vehicle_pause, proc{ nil } ) do
      vrp = TestHelper.load_vrp(self, fixture_file: 'problem_w_pause_that_can_be_simplified')
      vrp.resolution_evaluate_only = true
      vrp.preprocessing_first_solution_strategy = nil
      vrp.routes = result_w_simplification[:routes].collect{ |r|
        next if r[:activities].none?{ |a| a[:service_id] }

        {
          vehicle: vrp.vehicles.find{ |v| v.id == r[:vehicle_id] },
          mission_ids: r[:activities].collect{ |a| a[:service_id] }.compact
        }
      }.compact
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end

    # check if the results with and without simplification are the same
    result_wo_simplification[:routes].each_with_index{ |r, i|
      # TODO: following fails due to a bug in total_travel_time calculation
      # assert_equal r[:total_travel_time], result_w_simplification[:routes][i][:total_travel_time],
      #              'Manually inserting the simplified pause should give the same route total travel time'

      # TODO: the delta should be a lot smaller, may be as small as 1e-5 but due to a cost calculation difference
      # or-tools returns a different internal cost when there is a pause, we can decrease the delta when this difference
      # is fixed.
      assert_in_delta r[:cost_details][:time], result_w_simplification[:routes][i][:cost_details][:time], 0.1,
                      'Manually inserting the simplified pause should give the same time cost'

      assert_equal r[:total_time], result_w_simplification[:routes][i][:total_time],
                   'Manually inserting the simplified pause should give the same route total time'
    }

    # solve WITH simplification but from the last solution with evaluate_only
    vrp = TestHelper.load_vrp(self, fixture_file: 'problem_w_pause_that_can_be_simplified')
    vrp.resolution_evaluate_only = true
    vrp.preprocessing_first_solution_strategy = nil
    vrp.routes = result_wo_simplification[:routes].collect{ |r|
      next if r[:activities].none?{ |a| a[:service_id] }

      {
        vehicle: vrp.vehicles.find{ |v| v.id == r[:vehicle_id] },
        mission_ids: r[:activities].collect{ |a| a[:service_id] }.compact
      }
    }.compact
    result_w_simplification = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

    # check if all rests respect their TWs
    result_w_simplification[:routes].each{ |route|
      planned_rest = route[:activities].find{ |a| a[:type] == 'rest' }

      rest_id = vrp.vehicles.find{ |v| v[:id] == route[:vehicle_id] }[:rest_ids].first
      rest = vrp.rests.find{ |r| r[:id] == rest_id }
      assert rest, 'Simplification should put back the original rests'

      assert_operator planned_rest[:begin_time], :>=, rest.timewindows[0].start, 'Rest violates its timewindow.start'
      assert_operator planned_rest[:begin_time], :<=, rest.timewindows[0].end, 'Rest violates its timewindow.end'
    }

    # check if the results with and without simplification are the same
    result_wo_simplification[:routes].each_with_index{ |r, i|
      assert_in_delta r[:cost_details][:time], result_w_simplification[:routes][i][:cost_details][:time], 0.1,
                      'Manually inserting the simplified pause should give the same time cost'

      assert_equal r[:total_time], result_w_simplification[:routes][i][:total_time],
                   'Manually inserting the simplified pause should give the same route total time'
    }
  end

  def test_simplify_service_setup_duration
    problem = VRP.basic

    original_time_matrix = Oj.load(Oj.dump(problem[:matrices][0][:time]))
    problem[:services].each_with_index{ |service, index|
      service[:activity][:setup_duration] = 600 + index
    }

    vrp = TestHelper.create(problem)

    OptimizerWrapper.config[:services][:demo].simplify_service_setup_duration_and_vehicle_setup_modifiers(vrp)

    vrp.matrices[0][:time].each_with_index{ |row, row_index|
      row[1..-1].each_with_index{ |value, col_index|
        original_value = original_time_matrix[row_index][col_index + 1] # the first column is skipped
        if original_value.zero?
          assert_equal 0, value, 'A zero time should stay zero after setup_duration simplification'
        else
          assert_equal original_value + 600 + col_index, value, 'Time should have been increased with the setup duration'
        end
      }
    }
  end

  def test_cannot_simplify_service_setup_duration
    problem = VRP.basic

    original_time_matrix = Oj.load(Oj.dump(problem[:matrices][0][:time]))
    problem[:services] << Oj.load(Oj.dump(problem[:services].last)) # the same point_id
    problem[:services].last[:id] += '_dup'

    problem[:services].each_with_index{ |service, index|
      service[:activity][:setup_duration] = 600 + index # but different setup_duration
    }

    vrp = TestHelper.create(problem)

    OptimizerWrapper.config[:services][:demo].simplify_service_setup_duration_and_vehicle_setup_modifiers(vrp)

    dup_service_matrix_index = vrp.services.last.activity.point.matrix_index
    vrp.matrices[0][:time].each_with_index{ |row, row_index|
      assert_equal original_time_matrix[row_index][dup_service_matrix_index],
                   row[dup_service_matrix_index],
                   'Cannot simplify the pause if the point has multiple setup durations'
    }
  end

  def test_prioritize_first_available_trips_and_vehicles
    # Solve WITH simplification and note the cost and check if trips are not skipped
    vrp = TestHelper.load_vrp(self, fixture_file: 'vrp_multi_trips_which_uses_trip2_before_trip1')

    soln_with_simplification = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)

    there_is_no_skipped_trip_when_simplification_is_on = vrp.relations.none?{ |relation|
      skipped_a_trip = false
      relation.linked_vehicle_ids.any?{ |vid|
        route = soln_with_simplification[:routes].find{ |r| r[:vehicle_id] == vid }

        # if an earlier trip is skipped check if a later trip is active
        if skipped_a_trip
          route[:end_time] > route[:start_time]
        else
          skipped_a_trip = (route[:end_time] <= route[:start_time])
          nil
        end
      }
    }
    assert there_is_no_skipped_trip_when_simplification_is_on, 'Should prevent skipped trips for this instance'

    # Solve WITHOUT simplification (when prioritize_first_available_trips_and_vehicles is off)
    # verify the cost is the same or better with the simplification and that the trip2 is used before trip1
    function_called = false
    soln_without_simplification = Wrappers::Wrapper.stub_any_instance(:prioritize_first_available_trips_and_vehicles,
                                                                      proc{
                                                                        function_called = true
                                                                        nil
                                                                      }) do
      vrp = TestHelper.load_vrp(self, fixture_file: 'vrp_multi_trips_which_uses_trip2_before_trip1')
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
    assert function_called, 'prioritize_first_available_trips_and_vehicles should have been called'

    assert_operator soln_with_simplification[:cost], :<=, soln_without_simplification[:cost],
                    'simplification should not increase the cost'
    assert_operator soln_with_simplification[:unassigned].size, :<=, soln_without_simplification[:unassigned].size,
                    'simplification should not increase unassigned services'

    # If the next check starts to fail regularly, it may be removed after verification
    assert_msg = 'This instance used to skip a trip when prioritize_first_available_trips_and_vehicles is off. ' \
                 'This is not the case anymore either due to randomness in or-tools or ' \
                 'the prioritize_first_available_trips_and_vehicles is not necessary anymore.'
    there_is_a_skipped_trip_when_simplification_is_off = vrp.relations.any?{ |relation|
      skipped_a_trip = false
      relation.linked_vehicle_ids.any?{ |vid|
        route = soln_without_simplification[:routes].find{ |r| r[:vehicle_id] == vid }

        # if an earlier trip is skipped check if a later trip is active
        if skipped_a_trip
          route[:end_time] > route[:start_time]
        else
          skipped_a_trip = (route[:end_time] <= route[:start_time])
          nil
        end
      }
    }
    assert there_is_a_skipped_trip_when_simplification_is_off, assert_msg
  end

  def test_protobuf_receives_correct_simplified_complex_shipments
    vrp = TestHelper.load_vrp(self, fixture_file: 'vrp_multipickup_singledelivery_shipments')

    assert_raises OptimizerWrapper::JobKilledError do
      OptimizerWrapper.config[:services][:ortools].stub(
        :run_ortools,
        proc{ |problem, _vrp, _thread_proc, _block|
          # there are 7 multi-pickup-single-delivery P&Ds so the stats should be as follows:
          err_msg = 'Simplified multi-pickup-single-delivery p&d relation count is not correct'
          assert_equal 7, (problem.relations.count{ |r| r.type == 'sequence' }), err_msg
          assert_equal 20, (problem.relations.count{ |r| r.type == 'shipment' }), err_msg
          assert_equal 54, problem.relations.flat_map(&:linked_ids).size, err_msg
          assert_equal 40, problem.relations.flat_map(&:linked_ids).uniq.size, err_msg

          raise OptimizerWrapper::JobKilledError # Return "Job killed" to stop gracefully
        }
      ) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      end
    end
  end

  def test_simplified_complex_shipments_respect_the_original_relations
    vrp = VRP.basic

    vrp[:relations] = [
      { type: :shipment, linked_ids: %w[service_1 service_3] },
      { type: :shipment, linked_ids: %w[service_2 service_3] },
    ]

    vrp[:vehicles] << vrp[:vehicles].first.merge({id: 'vehicle_2', cost_fixed: 1 })

    # The matrix makes it so that if we ignore the complex shipment, serving s1 and s2 in two different vehicles is a
    # lot cheaper (4) then serving them on one vehicle (102). So we verify if optim-api does the "right" thing even if
    # it is inconvenient.
    vrp[:matrices][0][:time] = [
      [0, 1, 1, 1],
      [1, 0, 100, 1], # pickup1 to pickup2 is hard
      [1, 101, 0, 1], # pickup2 to pickup1 is hard
      [1, 11, 10, 0]  # delivery to p1 and p2 are hard
    ]
    vrp = TestHelper.create(vrp)

    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

    assert_empty result[:unassigned], 'There should be no unsigned services'
    assert_equal 1, result[:routes].count{ |r| r[:activities].any?{ |a| a[:service_id] } }, 'All services must be assigned to one vehicle'

    planned_order = result[:routes][0][:activities].map{ |a| a[:service_id] }.compact
    feasible_orders = [%w[service_1 service_2 service_3], %w[service_2 service_1 service_3]]
    assert_includes feasible_orders, planned_order, 'Complex shipment relation is violated'
  end

  def test_reject_when_unfeasible_timewindows
    vrp = VRP.toy
    vrp[:services].first[:activity][:timewindows] = [{ start: 0, end: 10 }, { start: 20, end: 15 }]
    # ship and service but only check service
    unfeasible_services = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(TestHelper.create(vrp))
    assert_equal 1, (unfeasible_services.values.flatten.count{ |un| un[:reason] == 'Service timewindows are infeasible' })
  end

  def test_multiple_reason
    problem = VRP.lat_lon_periodic
    problem[:services][5][:activity][:duration] = 28000
    problem[:services][5][:quantities] = [{ unit_id: 'kg', value: 5000 }]
    problem[:vehicles].first[:timewindow] = { start: 0, end: 24500 }
    problem[:vehicles].first[:capacities] = [{ unit_id: 'kg', limit: 1100 }]

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, problem: problem), nil)
    assert(result[:unassigned].collect{ |una| una[:reason].include?('&&') })
  end

  def test_possible_days_consistency
    vrp = TestHelper.create(VRP.lat_lon_periodic_two_vehicles)
    vrp.services[0].first_possible_days = [3]
    vrp.services[0].last_possible_days = [0]

    vrp.services[1].first_possible_days = [vrp.schedule_range_indices[:end] + 1]

    vrp.services[2].last_possible_days = [-1]

    unfeasible_services = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(vrp)
    assert_equal 3, unfeasible_services.values.flatten.size
    assert(unfeasible_services.values.flatten.all?{ |un| un[:reason] == 'Provided possible days do not allow service to be assigned' })
  end

  def test_possible_days_consistency_regarding_other_visits_possible_days
    vrp = TestHelper.create(VRP.lat_lon_periodic_two_vehicles)
    vrp.schedule_range_indices[:end] = 100
    vrp.services.each{ |s| s.visits_number = 3 }
    # this one should not be rejected
    vrp.services[0].first_possible_days = [0, 1, 0]
    vrp.services[0].last_possible_days = [7, 6, 5]

    # visit 1 and 2 should both be at day 3, which is not acceptable
    vrp.services[1].first_possible_days = [3, 3, 4]
    vrp.services[1].last_possible_days = [6, 3, 8]

    # last visit should be before first one, which is not acceptable
    vrp.services[2].first_possible_days = [3, 2, 1]
    vrp.services[2].last_possible_days = [6, 4, 2]

    # these days does not allow to respect minimum lapse
    vrp.services[3].minimum_lapse = 5
    vrp.services[3].first_possible_days = [0, 0, 0]
    vrp.services[3].last_possible_days = [7, 2, 3]

    unfeasible_services = OptimizerWrapper.config[:services][:demo].detect_unfeasible_services(vrp)
    assert_equal 9, unfeasible_services.values.flatten.size
    assert(unfeasible_services.values.flatten.all?{ |un| un[:reason] == 'Provided possible days do not allow service to be assigned' })
    refute_includes unfeasible_services.values.flatten.collect{ |un| un[:original_service_id] }, vrp.services.first.id
  end
end
