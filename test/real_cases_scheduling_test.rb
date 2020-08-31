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

class HeuristicTest < Minitest::Test
  if !ENV['SKIP_REAL_SCHEDULING'] && !ENV['SKIP_SCHEDULING']
    def test_instance_baleares2
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert result[:unassigned].size <= 3
      assert_equal vrp[:services].size, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
      assert_equal vrp.services.sum{ |service| service[:quantities][0][:value] }, result[:routes].sum{ |route| route[:activities].sum{ |activity| activity[:service_id] ? activity[:detail][:quantities][0][:value] : 0 } } + result[:unassigned].sum{ |unassigned| unassigned[:detail][:quantities][0][:value] }
      result[:routes].each{ |route|
        assert_operator route[:activities].sum{ |stop| stop[:detail][:quantities].empty? ? 0 : stop[:detail][:quantities][0][:value] }, :<=, vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] + 1e-5
      }
      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_instance_baleares2_with_priority
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('3359') })
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('0110') })
      assert_equal vrp[:services].size, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
      assert_equal vrp.services.sum{ |service| service[:quantities][0][:value] }, result[:routes].sum{ |route| route[:activities].sum{ |activity| activity[:service_id] ? activity[:detail][:quantities][0][:value] : 0 } } + result[:unassigned].sum{ |unassigned| unassigned[:detail][:quantities][0][:value] }
      assert(result[:routes].none?{ |route| route[:activities].sum{ |stop| stop[:detail][:quantities].empty? ? 0 : stop[:detail][:quantities][0][:value] } > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] })
      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_instance_andalucia2
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal 30, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
      assert_equal vrp.services.sum{ |service| service[:quantities][0][:value] }, result[:routes].sum{ |route| route[:activities].sum{ |activity| activity[:service_id] ? activity[:detail][:quantities][0][:value] : 0 } } + result[:unassigned].sum{ |unassigned| unassigned[:detail][:quantities][0][:value] }
      assert(result[:routes].none?{ |route| route[:activities].sum{ |stop| stop[:detail][:quantities].empty? ? 0 : stop[:detail][:quantities][0][:value] } > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] })
      service_ids = (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] })
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_instance_andalucia1_two_vehicles
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal 0, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
      assert_equal vrp.services.sum{ |service| service[:quantities][0] ? service[:quantities][0][:value] : 0 }, result[:routes].sum{ |route| route[:activities].sum{ |activity| activity[:service_id] && activity[:detail][:quantities][0] ? activity[:detail][:quantities][0][:value] : 0 } } + result[:unassigned].sum{ |unassigned| unassigned[:detail][:quantities][0] ? unassigned[:detail][:quantities][0][:value] : 0 }
      assert(result[:routes].none?{ |route| route[:activities].sum{ |stop| stop[:detail][:quantities].empty? ? 0 : stop[:detail][:quantities][0][:value] } > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] })
      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_without_same_point_day
      vrp = TestHelper.load_vrp(self)
      expecting = vrp.visits
      vrp[:configuration][:resolution][:solver] = false
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_equal expecting, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
      unassigned = result[:unassigned].size
      assert_equal 46, unassigned

      vrp = TestHelper.load_vrp(self)
      vrp[:configuration][:resolution][:solver] = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert unassigned >= result[:unassigned].size
      assert_equal expecting, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size
    end

    def test_instance_clustered
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal vrp.visits, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size

      ['kg', 'qte', 'l'].each{ |unit_id|
        # Route quantities
        problem_quantities = vrp.services.sum{ |service|
          service.quantities.find{ |qte| qte[:unit][:id] == unit_id }.value * service.visits_number
        }.round(3)

        route_quantities = result[:routes].sum{ |route|
          route[:activities].sum{ |activity|
            (activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
              qte[:unit] == unit_id
            }[:value]).to_f
          }
        }

        unassigned_quantities = result[:unassigned].sum{ |activity|
          (activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
            qte[:unit] == unit_id
          }[:value]).to_f
        }

        assert_in_delta problem_quantities, (route_quantities + unassigned_quantities).round(3), 1e-3

        # Route capacities
        result[:routes].each{ |route|
          route_quantity = route[:activities].sum{ |activity|
            (activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte| qte[:unit] == unit_id }[:value]).to_f
          }
          route_capacity = vrp[:vehicles].find{ |vehicle|
            vehicle[:id] == route[:vehicle_id].split('_').first
          }.capacities.find{ |cap| cap.unit_id == unit_id }.limit

          assert_operator route_quantity, :<=, route_capacity + 1e-5
        }
      }

      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_instance_same_point_day
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal vrp.visits, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size

      ['kg', 'qte', 'l'].each{ |unit_id|
        # Route quantities
        problem_quantities = vrp.services.sum{ |service|
          service.quantities.find{ |qte| qte[:unit][:id] == unit_id }.value * service.visits_number
        }.round(3)

        route_quantities = result[:routes].sum{ |route|
          route[:activities].sum{ |activity|
            (activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
              qte[:unit] == unit_id
            }[:value]).to_f
          }
        }

        unassigned_quantities = result[:unassigned].sum{ |activity|
          (activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
            qte[:unit] == unit_id
          }[:value]).to_f
        }

        assert_in_delta problem_quantities, (route_quantities + unassigned_quantities).round(3), 1e-3

        # Route capacities
        result[:routes].each{ |route|
          route_quantity = route[:activities].sum{ |activity|
            (activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte| qte[:unit] == unit_id }[:value]).to_f
          }
          route_capacity = vrp[:vehicles].find{ |vehicle|
            vehicle[:id] == route[:vehicle_id].split('_').first
          }.capacities.find{ |cap| cap.unit_id == unit_id }.limit

          assert_operator route_quantity, :<=, route_capacity + 1e-5
        }
      }

      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }
      service_ids.flatten!
      service_ids.compact!
      assert_nil service_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_vrp_allow_partial_assigment_false
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      unassigned = result[:unassigned].collect{ |un| un[:service_id] }
      original_ids = unassigned.collect{ |id| id.split('_').slice(0, 4).join('_') }
      assert(unassigned.all?{ |id|
        nb_visits = id.split('_').last.to_i
        original_id = id.split('_').slice(0, 4).join('_')
        original_ids.count(original_id) == nb_visits
      })

      result[:routes].each{ |route|
        route[:activities].each_with_index{ |activity, index|
          next if index.zero? || index > route[:activities].size - 3

          next if route[:activities][index + 1][:begin_time] == route[:activities][index + 1][:detail][:timewindows].first[:start] + route[:activities][index + 1][:detail][:setup_duration] # the same location

          assert_operator(
            route[:activities][index + 1][:begin_time],
            :>=,
            activity[:departure_time] + route[:activities][index + 1][:travel_time] + route[:activities][index + 1][:detail][:setup_duration],
          )
        }
      }
    end

    def test_two_phases_clustering_sched_with_freq_and_same_point_day_5veh
      # about 3 minutes
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      assert_equal(
        vrp.visits,
        result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size,
        "Found #{result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size} instead of #{vrp.visits} expected"
      )

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].collect{ |r| r[:activities].count{ |stop| stop[:point_id] == point_id } }.count(&:positive?)
        assert days_used <= expected_number_of_days, "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }

      limit = ENV['TRAVIS'] ? vrp.visits * 7.5 / 100.0 : vrp.visits * 6 / 100.0
      assert result[:unassigned].size < limit, "#{result[:unassigned].size}(#{result[:unassigned].size * 100.0 / vrp.visits}%) unassigned instead of #{limit}(#{limit * 100.0 / vrp.visits}%) authorized"
      assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') }, 'Some services could not be assigned to a vehicle'
    end

    def test_performance_12vl
      vrps = TestHelper.load_vrps(self)

      unassigned_visits = []
      expected = vrps.sum(&:visits)
      seen = 0
      vrps.each_with_index{ |vrp, vrp_i|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}..."
        vrp.preprocessing_partitions = nil
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        unassigned_visits << result[:unassigned].size
        seen += result[:unassigned].size + result[:routes].sum{ |r| r[:activities].count{ |a| a[:service_id] } }
      }

      # voluntarily equal to watch evolution of scheduling algorithm performance
      assert_equal expected, seen, "Should have #{expected} visits in result, only has #{seen}"
      assert_equal 244, unassigned_visits.sum, "Expecting 244 unassigned visits, have #{unassigned_visits.sum}"
    end

    def test_minimum_stop_in_route
      vrp = TestHelper.load_vrps(self, fixture_file: 'performance_13vl')[25]
      vrp.resolution_allow_partial_assignment = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes].any?{ |r| r[:activities].size - 2 < 5 }, "Expecting any of #{result[:routes].collect{ |r| r[:activities].size - 2 }} to be less than 10, this test is useless otherwise"
      should_remain_assigned = result[:routes].sum{ |r| r[:activities].size - 2 >= 5 ? r[:activities].size - 2 : 0 }

      # one vehicle should have at least 5 stops :
      vrp.vehicles.each{ |v| v.cost_fixed = 5 }
      vrp.services.each{ |s| s.exclusion_cost = 1 }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes].all?{ |r| (r[:activities].size - 2).zero? || r[:activities].size - 2 >= 5 }, 'Expecting no route with less than 5 stops unless it is empty'
      assert_operator(should_remain_assigned, :<=, result[:routes].sum{ |r| r[:activities].size - 2 })
      assert_equal 19, result[:unassigned].size
      assert_equal vrp.visits, result[:routes].sum{ |r| r[:activities].count{ |a| a[:service_id] } } + result[:unassigned].size

      all_ids = result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] } } + result[:unassigned].collect{ |un| un[:service_id] }
      all_ids.flatten!
      all_ids.compact!
      assert_equal vrp.visits, all_ids.size
      assert_nil all_ids.uniq!, 'There should not be any duplicate services'
    end

    def test_performance_13vl
      vrps = TestHelper.load_vrps(self)

      unassigned_visits = []
      expected = vrps.sum(&:visits)
      seen = 0
      vrps.each_with_index{ |vrp, vrp_i|
        puts "solving problem #{vrp_i + 1}/#{vrps.size}"
        vrp.preprocessing_partitions = nil
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        unassigned_visits << result[:unassigned].size
        seen += result[:unassigned].size + result[:routes].sum{ |r| r[:activities].count{ |a| a[:service_id] } }
      }

      # voluntarily equal to watch evolution of scheduling algorithm performance
      assert_equal expected, seen, "Should have #{expected} visits in result, only has #{seen}"
      assert_equal 278, unassigned_visits.sum, "Expecting 278 unassigned visits, have #{unassigned_visits.sum}"
    end

    def test_fill_days_and_post_processing
      # checks performance on instance calling post_processing
      vrp = TestHelper.load_vrp(self, fixture_file: 'scheduling_with_post_process')
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_equal 37, result[:unassigned].size
      assert_equal vrp.visits, result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size,
                   "Found #{result[:routes].sum{ |route| route[:activities].count{ |stop| stop[:service_id] } } + result[:unassigned].size} instead of #{vrp.visits} expected"
    end

    def test_treatment_site
      # treatment site
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_empty result[:unassigned]
      assert_equal(262, result[:routes].count{ |r| r[:activities].any?{ |a| a[:service_id]&.include? 'service_0_' } && r[:vehicle_id] }) # one treatment site per day
      assert(result[:routes].all?{ |r| r[:activities][-2][:service_id].include? 'service_0_' })

      vrp = TestHelper.load_vrp(self)
      vrp[:services].each{ |s|
        next if s[:id] == 'service_0' || s[:visits_number] == 1

        days_used = result[:routes].select{ |r| r[:activities].any?{ |a| a[:service_id]&.include? "#{s[:id]}_" } }.collect!{ |r| r[:vehicle_id].split('_').last.to_i }.sort!
        assert_equal s[:visits_number], days_used.size
        (1..days_used.size - 1).each{ |index|
          assert days_used[index] - days_used[index - 1] >= s[:minimum_lapse]
        }
      }
    end

    def test_route_initialisation
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_empty result[:unassigned]
      assert(result[:routes].select{ |r| r[:activities].any?{ |a| a[:point_id] == '1000023' } }.all?{ |r| r[:activities].any?{ |a| a[:point_id] == '1000007' } })
      assert(result[:routes].select{ |r| r[:activities].any?{ |a| a[:point_id] == '1000023' } }.all?{ |r| r[:activities].any?{ |a| a[:point_id] == '1000008' } })
    end

    def test_quality_with_minimum_stops_in_route
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_operator result[:unassigned].size, :<=, 10
    end
  end
end
