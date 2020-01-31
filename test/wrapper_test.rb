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
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ],
        distance: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
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
          [0, 693, 655, 1948, 693, 0],
          [609, 0, 416, 2070, 0, 609],
          [603, 489, 0, 1692, 489, 603],
          [1861, 1933, 1636, 0, 1933, 1861],
          [609, 0, 416, 2070, 0, 609],
          [0, 693, 655, 1948, 693, 0]
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
          [0, 655, 1948, 5231, 2971, 0],
          [603, 0, 1692, 4977, 2715, 603],
          [1861, 1636, 0, 6143, 1532, 1861],
          [5184, 4951, 6221, 0, 7244, 5184],
          [2982, 2758, 1652, 7264, 0, 2982],
          [0, 655, 1948, 5231, 2971, 0]
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
    [:ortools, ENV['SKIP_JSPRIT'] ? nil : :jsprit, :vroom].compact.each{ |o|
      result = OptimizerWrapper.solve([service: o, vrp: vrp])
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
    skip "This test fails with ortools-v7 due to our way of modelling rests.
          It will be fixed with the rest implementation"
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
    result = OptimizerWrapper.solve([service: :ortools, vrp: TestHelper.create(problem)])
    traces = $stdout.string
    $stdout = original_stdout
    puts traces
    assert_match /> iter /, traces, "Missing /> iter / in:\n " + traces
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
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ],
        distance: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ]
      }, {
        id: 'matrix_1',
        time: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ],
        distance: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
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
    assert OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
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

    begin
      Routers::RouterWrapper.stub_any_instance(:matrix, lambda{ |*a| raise RouterError.new('STUB: Expectation Failed - RouterWrapper::OutOfSupportedAreaOrNotSupportedDimensionError') }) do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
      end
    rescue StandardError => error
      assert error.class.name.match 'RouterError'
    end
  end

  def test_router_invalid_parameter_combination_error
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 47,
            lon: 0
          }
        }, {
          id: "point_1",
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
          id: "service_0",
          activity: {
            point_id: "point_0"
          }
        }, {
          id: "service_1",
          activity: {
            point_id: "point_1"
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

    begin
      Routers::RouterWrapper.stub_any_instance(:matrix, lambda{ |*a| raise RouterError.new('STUB: Internal Server Error - OSRM request fails with: InvalidValue Exclude flag combination is not supported.') }) do
        OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, TestHelper.create(problem), nil)
      end
    rescue StandardError => error
      assert error.class.name.match 'RouterError'
    end
  end

  def test_point_id_not_defined
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
            point_id: 'point_2'
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

    begin
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
    rescue StandardError => error
      assert error.is_a?(ActiveHash::RecordNotFound)
      assert error.message.match 'Couldn\'t find Models::Point with ID=point_2'
    end
  end

  def test_trace_location_not_defined
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ],
        distance: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 1000,
          lon: 1000
        }
      }, {
        id: 'point_1',
        matrix_index: 2,
    }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
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
        restitution: {
          trace: true
        },
        resolution: {
          duration: 10
        }
      }
    }

    begin
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)
    rescue StandardError => error
      assert error.is_a?(OptimizerWrapper::DiscordantProblemError)
      assert error.data.match 'Trace is not available if locations are not defined'
    end
  end

  def test_geometry_polyline_encoded
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 48,
          lon: 5
        }
      }, {
        id: 'point_1',
        location: {
          lat: 50,
          lon: 1
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
        restitution: {
          geometry: true,
          geometry_polyline: true,
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }

    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda{ |*a| (0..problem[:vehicles].size - 1).collect{ |_| [0, 0, 'trace'] } }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_polyline
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 48,
          lon: 5
        }
      }, {
        id: 'point_1',
        location: {
          lat: 49,
          lon: 1
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
        restitution: {
          geometry: true,
          geometry_polyline: false,
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda{ |*a| (0..problem[:vehicles].size - 1).collect{ |_| [0, 0, 'trace'] } }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_route_single_activity
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 48,
          lon: 5
        }
      }, {
        id: 'point_1',
        location: {
          lat: 49,
          lon: 1
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        speed_multiplier: 1
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
        restitution: {
          geometry: true,
          geometry_polyline: false,
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda{ |*a| (0..problem[:vehicles].size - 1).collect{ |_| [0, 0, 'trace'] } }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
      assert result[:routes][0][:geometry]
    end
  end

  def test_geometry_with_rests
    problem = {
      points: [{
        id: 'point0',
        location: {
          lat: 43.7,
          lon: 5.7
        }
      }, {
        id: 'point1',
        location: {
          lat: 44.2,
          lon: 6.2
        }
      }, {
        id: 'depot',
        location: {
          lat: 44.0,
          lon: 5.1
        }
      }],
      rests: [{
          id: 'break1',
          duration: 3600.0,
          timewindows: [{
            start: 45000,
            end: 48600
          }]
        }],
      vehicles: [{
        id: 'vehicle1',
        cost_fixed: 0.0,
        cost_time_multiplier: 1.0,
        cost_waiting_time_multiplier: 1.0,
        router_mode: 'car',
        router_dimension: 'time',
        speed_multiplier: 1.0,
        start_point_id: 'depot',
        end_point_id: 'depot',
        rest_ids: ['break1'],
        timewindow: {
          start: 28800,
          end: 61200
        }
      }],
      services: [{
        id: 'point0',
        type: 'service',
        activity: {
          duration: 1200.0,
          point_id: 'point0',
          timewindows: [{
            start: 28800,
            end: 63000
          }]
        }
      }, {
        id: 'point1',
        priority: 2,
        visits_number: 1,
        type: 'service',
        activity: {
          duration: 1800.0,
          point_id: 'point1',
          timewindows: [{
            start: 30600,
            end: 57600
          }]
        }
      }],
      configuration: {
        resolution: {
          duration: 100,
        },
        restitution: {
          geometry: true,
          geometry_polyline: true,
          intermediate_solutions: false,
        }
      }
    }
    Routers::RouterWrapper.stub_any_instance(:compute_batch, lambda{ |*a| (0..problem[:vehicles].size - 1).collect{ |_| [0, 0, 'trace'] } }) do
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
      assert_equal 5, result[:routes][0][:activities].size
      assert !result[:routes][0][:geometry].nil?
    end
  end

  def test_input_zones
    problem = {
      points: [{
        id: 'point_0',
        location: {
          lat: 48,
          lon: 5
        }
      }, {
        id: 'point_1',
        location: {
          lat: 49,
          lon: 1
        }
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
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        speed_multiplier: 1
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
        restitution: {
          intermediate_solutions: false,
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 2, result[:routes][1][:activities].size
  end

  def test_input_zones_shipment
    problem = {
      points: [{
        id: 'point_0', # zone_1
        location: {
          lat: 48,
          lon: 5
        }
      }, {
        id: 'point_1', # zone_0
        location: {
          lat: 49,
          lon: 1
        }
      }, {
        id: 'point_2', # no_zone
        location: {
          lat: 50,
          lon: 3
        }
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
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        speed_multiplier: 1
      }],
      services: [{
        id: 'service_0',
        activity: {
          point_id: 'point_1'
        }
      }],
      shipments: [{
          id: 'shipment_0',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_2'
          }
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

    result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.load_vrp(self, { problem: problem }), nil)
    assert_equal 2, result[:routes][0][:activities].size
    assert_equal 3, result[:routes][1][:activities].size
    assert_equal 0, result[:unassigned].size
  end

  def test_shipments_result
    problem = {
      matrices: [{
        id: 'matrix_0',
        time: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
        ],
        distance: [
          [ 0, 10, 20, 30,  0],
          [10,  0, 30, 40, 10],
          [20, 30,  0, 50, 20],
          [30, 40, 50,  0, 30],
          [ 0, 10, 20, 30,  0]
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

    result = OptimizerWrapper.solve([service: :ortools, vrp: TestHelper.create(problem)])
    assert result[:routes][0][:activities][1].has_key?(:pickup_shipment_id)
    assert !result[:routes][0][:activities][1].has_key?(:delivery_shipment_id)
    assert !result[:routes][0][:activities][2].has_key?(:pickup_shipment_id)
    assert result[:routes][0][:activities][2].has_key?(:delivery_shipment_id)

    if !ENV['SKIP_JSPRIT']
      result = OptimizerWrapper.solve([service: :jsprit, vrp: TestHelper.create(problem)])
      assert result[:routes][0][:activities][1].has_key?(:pickup_shipment_id)
      assert !result[:routes][0][:activities][1].has_key?(:delivery_shipment_id)
      assert !result[:routes][0][:activities][2].has_key?(:pickup_shipment_id)
      assert result[:routes][0][:activities][2].has_key?(:delivery_shipment_id)
    end
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
    assert result[:unassigned].empty?
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
        sequence_timewindows: [{
          start: 6,
          end: 10,
          day_index: 2
        }, {
          start: 0,
          end: 5,
          day_index: 0
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [{
              start: 0,
              end: 5,
              day_index: 1
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
        preprocessing: {
          max_split_size: 500,
        },
        resolution: {
          duration: 100,
        }
      }
    }
    vrp = TestHelper.create(problem)
    assert OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(vrp).include?(:assert_correctness_matrices_vehicles_and_points_definition)
    assert OptimizerWrapper.config[:services][:vroom].inapplicable_solve?(vrp).include?(:assert_correctness_matrices_vehicles_and_points_definition)
  end

  def test_unassigned_presence
    problem = {
      units: [{
        id: 'test',
        label: 'test'
      }],
      matrices: [{
        id: 'matrix_0',
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
    assert_equal 1, result[:routes].collect{ |route| route[:activities].reject{ |activity| activity[:service_id].nil? }.size }.reduce(&:+)
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
      schedule: {
        range_indices: {
          start: 0,
          end: 2
        }
      },
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    job = nil
    Interpreters::PeriodicVisits.stub_any_instance(:expand, lambda{ |vrp, job, &_block| vrp }) do
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
      schedule: {
        range_indices: {
          start: 0,
          end: 2
        }
      },
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    job = nil
    Interpreters::PeriodicVisits.stub_any_instance(:expand, lambda{ |vrp, job, &_block| vrp }) do
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
        sequence_timewindows: [{
          start: 6,
          end: 10,
          day_index: 2
        }, {
          start: 0,
          end: 5,
          day_index: 0
        }]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
          timewindows: [{
              start: 3,
              end: 4,
              day_index: 1
          }]
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2',
          timewindows: [{
              start: 4,
              end: 5,
              day_index: 2
          }]
        }
      }],
      schedule: {
        range_indices: {
          start: 0,
          end: 2
        }
      },
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    job = nil
    Interpreters::PeriodicVisits.stub_any_instance(:expand, lambda{ |vrp, job, &_block| vrp }) do
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
        sequence_timewindows: [{
          start: 6,
          end: 10,
          day_index: 2
        }, {
          start: 0,
          end: 5,
          day_index: 0
        }]
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
      schedule: {
        range_indices: {
          start: 0,
          end: 2
        }
      },
      configuration: {
        resolution: {
          duration: 10,
        }
      }
    }
    job = nil
    Interpreters::PeriodicVisits.stub_any_instance(:expand, lambda{ |vrp, job, &_block| vrp }) do
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
    assert OptimizerWrapper.solve([service: :vroom, vrp: TestHelper.create(vrp)])
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
      entity: 'work_day'
    }]
    assert OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)).empty?

    problem[:configuration][:preprocessing][:partitions] << {
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'vehicle'
    }
    assert OptimizerWrapper.config[:services][:ortools].inapplicable_solve?(TestHelper.create(problem)).include?(:assert_vehicle_entity_only_before_work_day)
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
                 result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + result[:unassigned].map{ |u| u[:service_id] }.size
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

  def test_repetition
    solve_call = 0
    vrp = TestHelper.create(VRP.scheduling)
    OptimizerWrapper.stub(:solve, lambda { |_vrp, _job, _block|
      solve_call += 1
      { routes: [], unassigned: vrp.services.collect{ |s| s }}
    }) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
    assert_equal 1, solve_call # 1 repetition if only periodic

    solve_call = 0
    vrp = TestHelper.create(VRP.scheduling)
    vrp.preprocessing_partitions = [{ 'method': 'balanced_kmeans', 'metric': 'duration', 'entity': 'vehicle' }]
    OptimizerWrapper.stub(:solve, lambda { |_vrp, _job, _block|
      solve_call += 1
      { routes: [], unassigned: vrp.services.collect{ |s| s }}
    }) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
    assert_equal 3, solve_call # 3 repetitions if periodic + clustering

    solve_call = 0
    vrp = TestHelper.create(VRP.scheduling)
    vrp.preprocessing_partitions = [{ 'method': 'balanced_kmeans', 'metric': 'duration', 'entity': 'vehicle' }]
    vrp.preprocessing_first_solution_strategy = nil
    vrp.resolution_solver = true
    OptimizerWrapper.stub(:solve, lambda { |_vrp, _job, _block|
      solve_call += 1
      { routes: [], unassigned: vrp.services.collect{ |s| s }}
    }) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
    assert_equal 1, solve_call # 1 repetition if only clustering

    solve_call = 0
    vrp = TestHelper.create(VRP.basic)
    OptimizerWrapper.stub(:solve, lambda { |_vrp, _job, _block|
      solve_call += 1
      { routes: [], unassigned: vrp.services.collect{ |s| s }}
    }) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end
    assert_equal 1, solve_call # 1 repetition if basic instance
  end

  def test_skills_independent
    vrp = TestHelper.create(VRP.independent_skills)
    OptimizerWrapper.stub(:define_process, lambda { |services_vrps, _job_id|
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
    assert_equal 12, result.select{ |un| un[:reason] == 'Unconsistency between visit number and minimum lapse' }.collect{ |un| un[:original_service_id] }.uniq.size
  end
end
