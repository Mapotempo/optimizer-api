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


class Wrappers::JspritTest < Minitest::Test
  if !ENV['SKIP_JSPRIT']
    def test_minimal_problem
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 1],
            [1, 0]
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
          matrix_id: 'matrix_0'
        }],
        services: [{
          id: 'service_0',
          activity: {
            point_id: 'point_0',
            duration: 5
          }
        }, {
          id: 'service_1',
          activity: {
            point_id: 'point_1',
            duration: 5
          }
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 1, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      assert_equal problem[:services].size + 1, result[:routes][0][:activities].size
    end

    def test_invalid_timewindow
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 1],
            [1, 0]
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
          matrix_id: 'matrix_0'
        }],
        services: [{
          id: 'service_0',
          activity: {
            point_id: 'point_0',
            timewindows: [{
              start: 2000,
              end: 10
            }]
          }
        }, {
          id: 'service_1',
          activity: {
            point_id: 'point_1'
          }
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      assert_raises do
        jsprit.solve(vrp, 'test')
      end
    end

    def test_loop_problem
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 655, 1948, 5231, 2971],
            [603, 0, 1692, 4977, 2715],
            [1861, 1636, 0, 6143, 1532],
            [5184, 4951, 6221, 0, 7244],
            [2982, 2758, 1652, 7264, 0],
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
        }, {
          id: 'point_3',
          matrix_index: 3
        }, {
          id: 'point_4',
          matrix_index: 4
        }],
        vehicles: [{
          id: 'vehicle_0',
          start_point_id: 'point_0',
          end_point_id: 'point_0',
          matrix_id: 'matrix_0'
        }],
        services: [{
          id: 'service_1',
          activity: {
            point_id: 'point_1',
            timewindows: [{
              start: 10,
              end: 2000
            }]
          }
        }, {
          id: 'service_2',
          activity: {
            point_id: 'point_2',
          }
        }, {
          id: 'service_3',
          activity: {
            point_id: 'point_3'
          }
        }, {
          id: 'service_4',
          activity: {
            point_id: 'point_4'
          }
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 1, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    end

    def test_minimal_unassigned_service
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 1],
            [1, 0]
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
          matrix_id: 'matrix_0',
          timewindow: { # infeasible
            start: 0,
            end: 0
          },
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
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 1, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      assert_equal problem[:services].size - 1 + 1, result[:routes][0][:activities].size
      assert_equal 1, result[:unassigned].size
    end

    def test_minimal_unassigned_shipment
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 1],
            [1, 0]
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
          matrix_id: 'matrix_0',
          timewindow: { # infeasible
            start: 0,
            end: 0
          },
        }],
        shipments: [{
          id: 'service_0',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_1'
          }
        }, {
          id: 'service_1',
          pickup: {
            point_id: 'point_1'
          },
          delivery: {
            point_id: 'point_0'
          }
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 0, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      assert_equal 2, result[:unassigned].size
    end

    def test_service_with_rest
    end

    def test_service_with_skills
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 655, 1948, 5231, 2971],
            [603, 0, 1692, 4977, 2715],
            [1861, 1636, 0, 6143, 1532],
            [5184, 4951, 6221, 0, 7244],
            [2982, 2758, 1652, 7264, 0],
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
        }, {
          id: 'point_3',
          matrix_index: 3
        }, {
          id: 'point_4',
          matrix_index: 4
        }],
        vehicles: [{
          id: 'vehicle_0',
          start_point_id: 'point_0',
          end_point_id: 'point_0',
          matrix_id: 'matrix_0',
          skills: [['a', 'b', 'c']],
        }],
        services: [{
          id: 'service_1',
          activity: {
            point_id: 'point_1',
            timewindows: [{
              start: 10,
              end: 2000
            }]
          }
        }, {
          id: 'service_2',
          activity: {
            point_id: 'point_2',
          }
        }, {
          id: 'service_3',
          activity: {
            point_id: 'point_3'
          },
          skills: ['b']
        }, {
          id: 'service_4',
          activity: {
            point_id: 'point_4'
          },
          skills: ['a']
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 1, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      assert_equal problem[:services].size + 2, result[:routes][0][:activities].size
    end

    def test_shipment_with_exclusive_skills
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 655, 1948, 5231, 2971],
            [603, 0, 1692, 4977, 2715],
            [1861, 1636, 0, 6143, 1532],
            [5184, 4951, 6221, 0, 7244],
            [2982, 2758, 1652, 7264, 0],
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
        }, {
          id: 'point_3',
          matrix_index: 3
        }, {
          id: 'point_4',
          matrix_index: 4
        }],
        vehicles: [{
          id: 'vehicle_0',
          start_point_id: 'point_0',
          end_point_id: 'point_0',
          matrix_id: 'matrix_0',
          skills: [['a', 'c'], ['b', 'c']],
        }],
        shipments: [{
          id: 'shipment_1',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_1'
          }
        }, {
          id: 'shipment_2',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_2',
          }
        }, {
          id: 'shipment_3',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_3'
          },
          skills: ['b']
        }, {
          id: 'shipment_4',
          pickup: {
            point_id: 'point_0'
          },
          delivery: {
            point_id: 'point_4'
          },
          skills: ['a']
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 1, result[:routes].select{ |r| r[:activities].select{ |a| a[:pickup_shipment_id] }.size > 0 || r[:activities].select{ |a| a[:delivery_shipment_id] }.size > 0 }.size
      assert_equal problem[:shipments].size * 2 + 2, result[:routes][0][:activities].size # activities for start/end and return to start for skills
    end

    def test_service_sticky_vehicle
      jsprit = OptimizerWrapper.config[:services][:jsprit]
      problem = {
        matrices: [{
          id: 'matrix_0',
          time: [
            [0, 655, 1948, 5231, 2971],
            [603, 0, 1692, 4977, 2715],
            [1861, 1636, 0, 6143, 1532],
            [5184, 4951, 6221, 0, 7244],
            [2982, 2758, 1652, 7264, 0],
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
        }, {
          id: 'point_3',
          matrix_index: 3
        }, {
          id: 'point_4',
          matrix_index: 4
        }],
        vehicles: [{
          id: 'vehicle_0',
          start_point_id: 'point_0',
          end_point_id: 'point_0',
          matrix_id: 'matrix_0',
          skills: [['a', 'b', 'c']],
        }, {
          id: 'vehicle_1',
          start_point_id: 'point_0',
          end_point_id: 'point_0',
          matrix_id: 'matrix_0',
          skills: [['a', 'b', 'c']],
        }],
        services: [{
          id: 'service_1',
          sticky_vehicle_ids: ['vehicle_0'],
          activity: {
            point_id: 'point_1'
          }
        }, {
          id: 'service_2',
          sticky_vehicle_ids: ['vehicle_0'],
          activity: {
            point_id: 'point_2',
          }
        }, {
          id: 'service_3',
          activity: {
            point_id: 'point_3'
          },
          skills: ['b']
        }, {
          id: 'service_4',
          sticky_vehicle_ids: ['vehicle_1'],
          activity: {
            point_id: 'point_4'
          },
          skills: ['a']
        }],
        configuration: {
          resolution: {
            duration: 1000,
            iterations: 20
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 2, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size
      rv0 = result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_0' }
      assert rv0[:activities].collect{ |a| a[:service_id] }.include?('service_1')
      assert rv0[:activities].collect{ |a| a[:service_id] }.include?('service_2')
      rv1 = result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_1' }
      assert rv1[:activities].collect{ |a| a[:service_id] }.include?('service_4')
    end

      def test_vehicle_limit
      jsprit = OptimizerWrapper.config[:services][:jsprit]
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
            end: 1
          }
        }, {
          id: 'vehicle_1',
          start_point_id: 'point_0',
          matrix_id: 'matrix_0',
          timewindow: {
            end: 1
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
            duration: 10,
            vehicle_limit: 1
          }
        }
      }
      vrp = TestHelper.create(problem)
      assert jsprit.inapplicable_solve?(vrp).empty?
      result = jsprit.solve(vrp, 'test')
      assert result
      assert_equal 2, result[:routes].size
      assert_equal problem[:services].size + 1, result[:routes][0][:activities].size + result[:routes][1][:activities].size
    end
  end
end
