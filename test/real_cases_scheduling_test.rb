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

  if !ENV['SKIP_REAL_SCHEDULING']

    def test_instance_baleares2
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert result[:unassigned].size <= 3
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_baleares2_with_priority
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert result[:unassigned].none?{ |service| service[:service_id].include?('3359') }
      assert result[:unassigned].none?{ |service| service[:service_id].include?('0110') }
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_andalucia2
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal 11, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.size, (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.uniq.size
    end

    def test_instance_andalucia1_two_vehicles
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal 0, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0] ? activity[:detail][:quantities][0][:value] : 0 }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0] ? unassigned[:detail][:quantities][0][:value] : 0 }.sum, vrp.services.collect{ |service| service[:quantities][0] ? service[:quantities][0][:value] : 0 }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_800unaffected_clustered
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal vrp[:services].collect{ |service| service[:visits_number] }.sum.to_i, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.flatten.compact.sum).round(3)
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'kg' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'qte' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'l' }[:limit]}
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_800unaffected_clustered_same_point
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal vrp[:services].collect{ |service| service[:visits_number] }.sum.to_i, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size

      %w[kg qte l].each{ |unit|
        expected_value = vrp.services.collect{ |service| service[:quantities].find{ |quan| quan[:unit][:id] == unit }[:value] * service[:visits_number] }.sum

        actual_value = result[:routes].collect{ |route|
          route[:activities].collect{ |stop|
            stop[:service_id] && !stop[:detail][:quantities].empty? && stop[:detail][:quantities].find{ |quan|
              quan[:unit][:id] == unit
            }[:value]
          }
        }.flatten.compact.sum

        actual_value += result[:unassigned].collect{ |service|
          !service[:detail][:quantities].empty? && service[:detail][:quantities].find{ |quan|
            quan[:unit][:id] == unit
          }[:value]
        }.flatten.compact.sum

        assert_in_delta expected_value, actual_value, 1e-3

        result[:routes].each{ |route|
          vehicle_capacity = vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == unit }[:limit]

          vehicle_load = route[:activities].reject{ |stop|
            stop[:detail][:quantities].empty?
          }.collect{ |stop|
            stop[:detail][:quantities].find{ |quan|
              quan[:unit][:id] == unit
            }[:value]
          }.sum

          assert vehicle_load <= vehicle_capacity
        }
      }

      allocated_service_ids = result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact

      assert_equal allocated_service_ids.size, allocated_service_ids.uniq.size
    end

    def test_vrp_allow_partial_assigment_false
      vrp = FCT.load_vrp(self)
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
  end

  def test_two_phases_clustering_sched_with_freq_and_same_point_day_5veh
    # about 3 minutes
    vrp = FCT.load_vrp(self)
    total_visits = vrp[:services].collect{ |s| s[:visits_number] }.sum
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    assert result
    assert result[:unassigned].size < total_visits * 5 / 100, "#{result[:unassigned].size * 100 / total_visits}% unassigned instead of 5% authorized"
    assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') }, 'Some services could not be assigned to a vehicle'
    assert_equal total_visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size,
      "Found #{result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size} instead of #{total_visits} expected"
  end

  def test_improve_routes_with_ortools
    # TDD
    visits_unassigned = []
    services_unassigned = []

    vrp = FCT.load_vrp(self)
    result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] } }, vrp, nil)
    visits_unassigned << result[:unassigned].size
    services_unassigned << result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }.uniq.size
  end
end
