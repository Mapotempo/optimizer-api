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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size # without start/end/rest
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size # without start/end/rest
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
              start: i*10,
              end: i*10+1
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size # without start/end/rest
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
          id: "unit0",
          label: "kg"
      }, {
          id: "unit1",
          label: "kg"
      }, {
          id: "unit2",
          label: "kg"
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
          unit_id: "unit0",
          limit: 5
        },{
          unit_id: "unit1",
          limit: 5
        },{
          unit_id: "unit2",
          limit: 5
        }]
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          quantities: [{
            unit_id: "unit#{i%3}",
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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, true).size
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
              start: i*10,
              end: i*10 + 10
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
    assert_equal 3, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, true).size
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
              start: i*10,
              end: i*10 + 10
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size
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
    assert_equal 2, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size
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
    assert_equal 3, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size # without start/end/rest
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
    assert_equal 4, OptimizerWrapper.send(:zip_cluster, Models::Vrp.create(problem), 5, false).size # without start/end/rest
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
    vrp = Models::Vrp.create(problem)
    [:ortools, :jsprit, :vroom].each{ |o|
      result = OptimizerWrapper.solve([service: o, vrp: vrp])
      assert_equal size - 1 + 1, result[:routes][0][:activities].size, "[#{o}] "
      services = result[:routes][0][:activities].collect{ |a| a[:service_id] }
      1.upto(size - 1).each{ |i|
        assert_includes services, "service_#{i}", "[#{o}] Service missing: #{i}"
      }
      points = result[:routes][0][:activities].collect{ |a| a[:point_id] }
      assert_includes points, "point_0", "[#{o}] Point missing: 0"
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
          end: 1
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
    $stdout = StringIO.new('','w')
    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    traces = $stdout.string
    $stdout = original_stdout
    puts traces
    assert_match /> iter /, traces, "Missing /> iter / in:\n " + traces
    assert_equal size + 1, result[:routes][0][:activities].size # always return activities for start/end
    points = result[:routes][0][:activities].collect{ |a| a[:service_id] || a[:point_id] || a[:rest_id] }
    services_size = problem[:services].size
    services_size.times.each{ |i|
      assert_includes points, "service_#{i+1}", "Element missing: #{i+1}"
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
    assert OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, Models::Vrp.create(problem))
  end

  def test_multiple_matrices_not_provided
    size = 5
    problem = {
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          location: {
            lat: 45,
            lon: Float(i)/10
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
    assert OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, Models::Vrp.create(problem))
  end

  def test_router_matrix_error
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 1000,
            lon: 1000
          }
        }, {
          id: "point_1",
          location: {
            lat: 1000,
            lon: 1000
          }
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
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
      OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, Models::Vrp.create(problem))
    rescue StandardError => error
      assert error.message.match 'RouterWrapperError'
    end
  end

  def test_point_id_not_defined
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 1000,
            lon: 1000
          }
        }, {
          id: "point_1",
          location: {
            lat: 1000,
            lon: 1000
          }
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
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
            point_id: "point_2"
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
      OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, Models::Vrp.create(problem))
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
      points: [
        {
          id: "point_0",
          matrix_index: 0,
          location: {
            lat: 1000,
            lon: 1000
          }
        }, {
          id: "point_1",
          matrix_index: 2,
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
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
        restitution: {
          trace: true
        },
        resolution: {
          duration: 10
        }
      }
    }

    begin
      OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, Models::Vrp.create(problem))
    rescue StandardError => error
      assert error.is_a?(OptimizerWrapper::DiscordantProblemError)
      assert error.data.match 'Trace is not available if locations are not defined'
    end
  end

  def test_geometry_polyline_encoded
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 48,
            lon: 5
          }
        }, {
          id: "point_1",
          location: {
            lat: 50,
            lon: 1
          }
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
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
        restitution: {
          geometry: true,
          geometry_polyline: true
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert result[:routes][0][:geometry]
  end

  def test_geometry_polyline
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 48,
            lon: 5
          }
        }, {
          id: "point_1",
          location: {
            lat: 49,
            lon: 1
          }
        }
      ],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
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
        restitution: {
          geometry: true,
          geometry_polyline: false
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert result[:routes][0][:geometry]
  end

  def test_geometry_route_single_activity
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 48,
            lon: 5
          }
        }, {
          id: "point_1",
          location: {
            lat: 49,
            lon: 1
          }
        }
      ],
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
        restitution: {
          geometry: true,
          geometry_polyline: false
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert result[:routes][0][:geometry]
  end

  def test_input_zones
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 48,
            lon: 5
          }
        }, {
          id: "point_1",
          location: {
            lat: 49,
            lon: 1
          }
        }
      ],
      zones: [{
        id: "zone_0",
        polygon: {
        "type": "Polygon",
        "coordinates": [[[0.5,48.5],[1.5,48.5],[1.5,49.5],[0.5,49.5],[0.5,48.5]]]
        },
        allocations: [["vehicle_0"]]
      }, {
        id: "zone_1",
        polygon: {
          "type": "Polygon",
          "coordinates": [[[4.5,47.5],[5.5,47.5],[5.5,48.5],[4.5,48.5],[4.5,47.5]]]
        },
        allocations: [["vehicle_1"]]
      }, {
        id: "zone_2",
        polygon: {
          "type": "Polygon",
          "coordinates": [[[2.5,46.5],[4.5,46.5],[4.5,48.5],[2.5,48.5],[2.5,46.5]]]
        },
        allocations: [["vehicle_1"]]
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
        restitution: {
          geometry: true,
          geometry_polyline: false
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert_equal result[:routes][0][:activities].size, 2
    assert_equal result[:routes][1][:activities].size, 2
  end

  def test_input_zones_shipment
    problem = {
      points: [
        {
          id: "point_0",
          location: {
            lat: 48,
            lon: 5
          }
        }, {
          id: "point_1",
          location: {
            lat: 49,
            lon: 1
          }
        }
      ],
      zones: [{
        id: "zone_0",
        polygon: {
        "type": "Polygon",
        "coordinates": [[[0.5,48.5],[1.5,48.5],[1.5,49.5],[0.5,49.5],[0.5,48.5]]]
        },
        allocations: [["vehicle_0"]]
      }, {
        id: "zone_1",
        polygon: {
          "type": "Polygon",
          "coordinates": [[[4.5,47.5],[5.5,47.5],[5.5,48.5],[4.5,48.5],[4.5,47.5]]]
        },
        allocations: [["vehicle_1"]]
      }, {
        id: "zone_2",
        polygon: {
          "type": "Polygon",
          "coordinates": [[[2.5,46.5],[4.5,46.5],[4.5,48.5],[2.5,48.5],[2.5,46.5]]]
        },
        allocations: [["vehicle_1"]]
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
        id: "service_0",
        activity: {
          point_id: "point_0"
        }
      }],
      shipments: [
        {
          id: "shipment_0",
          pickup: {
            point_id: "point_0"
          },
          delivery: {
            point_id: "point_1"
          }
        }
      ],
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        restitution: {
          geometry: true,
          geometry_polyline: false
        },
        resolution: {
          duration: 10
        }
      }
    }

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert_equal 1, result[:routes][0][:activities].size
    assert_equal 2, result[:routes][1][:activities].size
    assert_equal 1, result[:unassigned].size
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
          id: "point_0",
          matrix_index: 0
        }, {
          id: "point_1",
          matrix_index: 1
        }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        speed_multiplier: 1,
        matrix_id: 'matrix_0'
      }],
      shipments: [
        {
          id: "shipment_0",
          pickup: {
            point_id: "point_0"
          },
          delivery: {
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

    result = OptimizerWrapper.solve([service: :ortools, vrp: Models::Vrp.create(problem)])
    assert result[:routes][0][:activities][1].has_key?(:pickup_shipment_id)
    assert !result[:routes][0][:activities][1].has_key?(:delivery_shipment_id)
    assert !result[:routes][0][:activities][2].has_key?(:pickup_shipment_id)
    assert result[:routes][0][:activities][2].has_key?(:delivery_shipment_id)

    result = OptimizerWrapper.solve([service: :jsprit, vrp: Models::Vrp.create(problem)])
    assert result[:routes][0][:activities][1].has_key?(:pickup_shipment_id)
    assert !result[:routes][0][:activities][1].has_key?(:delivery_shipment_id)
    assert !result[:routes][0][:activities][2].has_key?(:pickup_shipment_id)
    assert result[:routes][0][:activities][2].has_key?(:delivery_shipment_id)
  end
end
