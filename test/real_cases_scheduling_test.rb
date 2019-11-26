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
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert result[:unassigned].size <= 3
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_baleares2_with_priority
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('3359') })
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('0110') })
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert(result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] })
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_andalucia2
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal 34, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.size, (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.uniq.size
    end

    def test_instance_andalucia1_two_vehicles
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal 0, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0] ? activity[:detail][:quantities][0][:value] : 0 }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0] ? unassigned[:detail][:quantities][0][:value] : 0 }.sum, vrp.services.collect{ |service| service[:quantities][0] ? service[:quantities][0][:value] : 0 }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_clustered
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal vrp.visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size

      ['kg', 'qte', 'l'].each{ |unit_id|
        # Route quantities
        problem_quantities = vrp.services.collect{ |service|
          service.quantities.find{ |qte| qte[:unit][:id] == unit_id }.value * service.visits_number
        }.sum.round(3)

        route_quantities = result[:routes].collect{ |route|
          route[:activities].collect{ |activity|
            activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
              qte[:unit] == unit_id
            }[:value]
          }
        }.flatten.compact.sum

        unassigned_quantities = result[:unassigned].collect{ |activity|
          activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
            qte[:unit] == unit_id
          }[:value]
        }.flatten.compact.sum

        assert_in_delta problem_quantities, (route_quantities + unassigned_quantities).round(3), 1e-3

        # Route capacities
        assert(result[:routes].none?{ |route|
          route_quantity = route[:activities].collect{ |activity|
            activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte| qte[:unit] == unit_id }[:value]
          }.compact.sum
          route_capacity = vrp[:vehicles].find{ |vehicle|
            vehicle[:id] == route[:vehicle_id].split('_').first
          }.capacities.find{ |cap| cap.unit_id == unit_id }.limit

          route_quantity > route_capacity
        })
      }

      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact
      uniq_services_ids = service_ids.uniq
      assert_equal service_ids.size, uniq_services_ids.size
    end

    def test_instance_same_point_day
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert_equal vrp.visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size

      ['kg', 'qte', 'l'].each{ |unit_id|
        # Route quantities
        problem_quantities = vrp.services.collect{ |service|
          service.quantities.find{ |qte| qte[:unit][:id] == unit_id }.value * service.visits_number
        }.sum.round(3)

        route_quantities = result[:routes].collect{ |route|
          route[:activities].collect{ |activity|
            activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
              qte[:unit] == unit_id
            }[:value]
          }
        }.flatten.compact.sum

        unassigned_quantities = result[:unassigned].collect{ |activity|
          activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte|
            qte[:unit] == unit_id
          }[:value]
        }.flatten.compact.sum

        assert_in_delta problem_quantities, (route_quantities + unassigned_quantities).round(3), 1e-3

        # Route capacities
        assert(result[:routes].none?{ |route|
          route_quantity = route[:activities].collect{ |activity|
            activity[:service_id] && activity[:detail][:quantities].size.positive? && activity[:detail][:quantities].find{ |qte| qte[:unit] == unit_id }[:value]
          }.compact.sum
          route_capacity = vrp[:vehicles].find{ |vehicle|
            vehicle[:id] == route[:vehicle_id].split('_').first
          }.capacities.find{ |cap| cap.unit_id == unit_id }.limit

          route_quantity > route_capacity
        })
      }

      service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact
      uniq_services_ids = service_ids.uniq
      assert_equal service_ids.size, uniq_services_ids.size
    end

    def test_vrp_allow_partial_assigment_false
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)

      unassigned = result[:unassigned].collect{ |un| un[:service_id] }
      original_ids = unassigned.collect{ |id| id.split('_').slice(0, 4).join('_') }
      assert(unassigned.all?{ |id|
        nb_visits = id.split('_').last.to_i
        original_id = id.split('_').slice(0, 4).join('_')
        original_ids.count(original_id) == nb_visits
      })

      result[:routes].each{ |route|
        route[:activities].each_with_index{ |activity, index|
          next if index == 0 || index > route[:activities].size - 3
          assert route[:activities][index + 1][:begin_time] == route[:activities][index + 1][:detail][:timewindows].first[:start] + route[:activities][index + 1][:detail][:setup_duration] ? true :
            (assert_equal route[:activities][index + 1][:begin_time], activity[:departure_time] + route[:activities][index + 1][:travel_time] + route[:activities][index + 1][:detail][:setup_duration])
        }
      }
    end

    def test_two_phases_clustering_sched_with_freq_and_same_point_day_5veh
      # about 3 minutes
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      assert_equal vrp.visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size,
        "Found #{result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size} instead of #{vrp.visits} expected"

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].collect{ |r| r[:activities].select{ |stop| stop[:point_id] == point_id }.size }.select(&:positive?).size
        assert days_used <= expected_number_of_days, "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }

      limit = ENV['TRAVIS'] ? vrp.visits * 7.5 / 100.0 : vrp.visits * 6 / 100.0
      assert result[:unassigned].size < limit, "#{result[:unassigned].size}(#{result[:unassigned].size * 100.0 / vrp.visits}%) unassigned instead of #{limit}(#{limit * 100.0 / vrp.visits}%) authorized"
      assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') }, 'Some services could not be assigned to a vehicle'
    end

    def test_performance_12vl
      vrps = TestHelper.load_vrps(self)

      unassigned_visits = []
      vrps.each_with_index{ |vrp, vrp_i|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}..."
        vrp.preprocessing_partitions = nil
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
        unassigned_visits << result[:unassigned].size
      }

      # voluntarily equal to watch evolution of scheduling algorithm performance
      assert_equal 441, unassigned_visits.sum, "Expecting 441 unassigned visits, have #{unassigned_visits.sum}"
    end

    def test_performance_13vl
      vrps = TestHelper.load_vrps(self)

      unassigned_visits = []
      vrps.each_with_index{ |vrp, vrp_i|
        puts "solving problem #{vrp_i + 1}/#{vrps.size}"
        vrp.preprocessing_partitions = nil
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
        unassigned_visits << result[:unassigned].size
      }

      # voluntarily equal to watch evolution of scheduling algorithm performance
      assert_equal 312, unassigned_visits.sum, "Expecting 312 unassigned visits, have #{unassigned_visits.sum}"
    end
  end
end
