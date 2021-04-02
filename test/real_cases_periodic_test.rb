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
    def check_quantities(vrp, result)
      units = vrp.units.collect(&:id)

      units.each{ |unit|
        assigned_quantities = 0
        result[:routes].each{ |route|
          route_vehicle = vrp.vehicles.find{ |vehicle| vehicle.id == route[:vehicle_id] || route[:vehicle_id].start_with?("#{vehicle.id}_") }
          route_capacity = route_vehicle.capacities.find{ |cap| cap.unit_id == unit }[:limit] + 1e-5
          route_quantities = route[:activities].sum{ |stop|
            qty = stop[:detail][:quantities].to_a.find{ |q| q[:unit] == unit }
            qty ? qty[:value] : 0
          }
          assigned_quantities += route_quantities
          assert_operator route_quantities, :<=, route_capacity
        }
        unassigned_quantities =
          result[:unassigned].sum{ |un| un[:detail][:quantities].find{ |qty| qty[:unit] == unit }[:value] }
        assert_in_delta vrp.services.sum{ |service| (service.quantities.find{ |qty| qty.unit_id == unit }&.value || 0) * service.visits_number },
                        (assigned_quantities + unassigned_quantities).round(3), 1e-3
      }
    end

    def test_instance_baleares2
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimize_days_worked = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:unassigned].size <= 3

      check_quantities(vrp, result)

      assigned_service_ids = result[:routes].flat_map{ |route|
        route[:activities].collect{ |activity| activity[:service_id] }
      }.compact
      assert_nil assigned_service_ids.uniq!,
                 'There should not be any duplicate service ID because there are no duplicated IDs in instance'

      # add priority
      assert(result[:unassigned].any?{ |service| service[:service_id].include?('3359') })

      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimize_days_worked = true
      vrp.services.find{ |s| s.id == '3359' }.priority = 0
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('3359') })
      assert(result[:unassigned].none?{ |service| service[:service_id].include?('0110') })
    end

    def test_instance_andalucia2
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimize_days_worked = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      # voluntarily equal to watch evolution of scheduling algorithm performance :
      assert_equal 25, result[:unassigned].size, 'Do not have the expected number of unassigned visits'
      check_quantities(vrp, result)
    end

    def test_instance_andalucia1_two_vehicles
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimize_days_worked = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_empty result[:unassigned]
      check_quantities(vrp, result)
    end

    def test_instance_same_point_day
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_operator result[:unassigned].size, :<=, 800
      check_quantities(vrp, result)
    end

    def test_vrp_allow_partial_assigment_false
      vrp = TestHelper.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      refute_empty result[:unassigned], 'If unassigned set is empty this test becomes useless'
      result[:unassigned].group_by{ |un| un[:original_service_id] }.each{ |id, set|
        expected_visits = vrp.services.find{ |s| s.id == id }.visits_number
        assert_equal expected_visits, set.size
      }

      result[:routes].each{ |route|
        route[:activities].each_with_index{ |activity, index|
          next if index.zero? || index > route[:activities].size - 3

          next if route[:activities][index + 1][:begin_time] ==
                  route[:activities][index + 1][:detail][:timewindows].first[:start] +
                  route[:activities][index + 1][:detail][:setup_duration] # the same location

          assert_operator(
            route[:activities][index + 1][:begin_time],
            :>=,
            activity[:departure_time] +
              route[:activities][index + 1][:travel_time] +
              route[:activities][index + 1][:detail][:setup_duration],
          )
        }
      }
    end

    def test_minimum_stop_in_route
      vrp = TestHelper.load_vrps(self, fixture_file: 'performance_13vl')[25]
      vrp.resolution_allow_partial_assignment = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes].any?{ |r| r[:activities].size - 2 < 5 },
             'We expect at least one route with less than 5 services, this test is useless otherwise'
      should_remain_assigned = result[:routes].sum{ |r| r[:activities].size - 2 >= 5 ? r[:activities].size - 2 : 0 }

      # one vehicle should have at least 5 stops :
      vrp.vehicles.each{ |v| v.cost_fixed = 5 }
      vrp.services.each{ |s| s.exclusion_cost = 1 }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result[:routes].all?{ |r| (r[:activities].size - 2).zero? || r[:activities].size - 2 >= 5 },
             'Expecting no route with less than 5 stops unless it is an empty route'
      assert_operator should_remain_assigned, :<=, (result[:routes].sum{ |r| r[:activities].size - 2 })
      assert_equal 19, result[:unassigned].size

      all_ids = (result[:routes].flat_map{ |route| route[:activities].collect{ |stop| stop[:service_id] } }.compact +
                result[:unassigned].collect{ |un| un[:service_id] }).uniq
      assert_equal vrp.visits, all_ids.size
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

      # voluntarily equal to watch evolution of periodic algorithm performance
      assert_equal expected, seen, 'Do not have the expected number of total visits'
      assert_equal 294, unassigned_visits.sum, 'Do not have the expected number of unassigned visits'
    end

    def test_fill_days_and_post_processing
      # checks performance on instance calling post_processing
      vrp = TestHelper.load_vrp(self, fixture_file: 'periodic_with_post_process')
      vrp.resolution_minimize_days_worked = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      # voluntarily equal to watch evolution of periodic algorithm performance
      assert_equal 74, result[:unassigned].size, 'Do not have the expected number of unassigned visits'
    end

    def test_treatment_site
      # treatment site
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimize_days_worked = true
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
      vrp.resolution_minimize_days_worked = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_operator result[:unassigned].size, :<=, 10
    end
  end
end
