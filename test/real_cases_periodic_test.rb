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
  if !ENV['SKIP_REAL_PERIODIC'] && !ENV['SKIP_PERIODIC']
    def check_quantities(vrp, solution)
      unit_ids = vrp.units.collect(&:id)

      unit_ids.each{ |unit_id|
        assigned_quantities = 0
        solution.routes.each{ |route|
          route_capacity = route.vehicle.capacities.find{ |cap| cap.unit_id == unit_id }.limit + 1e-5
          route_quantities = route.stops.sum{ |act|
            qty = act.loads.find{ |l| l.quantity.unit.id == unit_id }
            qty ? qty.quantity.value : 0
          }
          assigned_quantities += route_quantities
          assert_operator route_quantities, :<=, route_capacity
        }
        unassigned_quantities =
          solution.unassigned.sum{ |un| un.loads.find{ |l| l.quantity.unit.id == unit_id }&.quantity&.value || 0 }
        assert_in_delta vrp.services.sum{ |service|
                          (service.quantities.find{ |qty| qty.unit_id == unit_id }&.value || 0) * service.visits_number
                        }, (assigned_quantities + unassigned_quantities).round(3), 1e-3
      }
    end

    def test_instance_baleares2
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0].unassigned.size <= 3

      check_quantities(vrp, solutions[0])

      assigned_service_ids = solutions[0][:routes].flat_map{ |route|
        route.stops.map(&:service_id)
      }.compact
      assert_nil assigned_service_ids.uniq!,
                 'There should not be any duplicate service ID because there are no duplicated IDs in instance'
      assert_equal vrp.services.map(&:id).sort, (assigned_service_ids + solutions[0].unassigned.map(&:service_id) ).sort

      # add priority
      assert(solutions[0].unassigned.any?{ |service| service.service_id.include?('3359') })

      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      vrp.services.find{ |s| s.id == '3359' }.priority = 0
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert(solutions[0].unassigned.none?{ |service| service.service_id.include?('3359') })
      assert(solutions[0].unassigned.none?{ |service| service.service_id.include?('0110') })
    end

    def test_instance_andalucia2
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      # voluntarily equal to watch evolution of periodic algorithm performance :
      assert_equal 25, solutions[0].unassigned.size, 'Do not have the expected number of unassigned visits'
      check_quantities(vrp, solutions[0])
    end

    def test_instance_andalucia1_two_vehicles
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_empty solutions[0].unassigned
      check_quantities(vrp, solutions[0])
    end

    def test_instance_same_point_day
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_operator solutions[0].unassigned.size, :<=, 800
      check_quantities(vrp, solutions[0])
    end

    def test_vrp_allow_partial_assigment_false
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.preprocessing.partitions.each{ |p| p.restarts = 3 }
      # make sure there will be unassigned visits
      vrp.vehicles.each{ |v| v.sequence_timewindows.each{ |tw| tw.end -= ((tw.end - tw.start) / 2.75).round } }
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      refute_empty solutions[0].unassigned, 'If unassigned set is empty this test becomes useless'
      solutions[0].unassigned.group_by(&:id).each{ |id, set|
        expected_visits = vrp.services.select{ |s| s.original_id == id }.sum(&:visits_number)
        assert_equal expected_visits, set.size
      }

      solutions[0].routes.each{ |route|
        route.stops.each_with_index{ |activity, index|
          next if index.zero? || index > route.stops.size - 3

          next if route.stops[index + 1].info.begin_time ==
                  route.stops[index + 1].activity.timewindows.first.start +
                  (route.stops[index + 1].info.travel_time.positive? &&
                  route.stops[index + 1].activity.setup_duration || 0) # the same location

          assert_operator(
            route.stops[index + 1].info.begin_time,
            :>=,
            activity.info.departure_time +
              route.stops[index + 1].info.travel_time +
              (route.stops[index + 1].info.travel_time.positive? &&
                  route.stops[index + 1].activity.setup_duration || 0),
          )
        }
      }
    end

    def test_minimum_stop_in_route
      vrp = TestHelper.load_vrps(self, fixture_file: 'performance_13vl')[25]
      vrp.configuration.resolution.allow_partial_assignment = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }},  Marshal.load(Marshal.dump(vrp)), nil)
      assert solutions[0].routes.any?{ |r| r.stops.size - 2 < 5 },
             'We expect at least one route with less than 5 services, this test is useless otherwise'
      should_remain_assigned = solutions[0].routes.sum{ |r| r.stops.size - 2 >= 5 ? r.stops.size - 2 : 0 }
      should_remain_unassigned = solutions[0].unassigned.size

      # one vehicle should have at least 5 stops :
      vrp.vehicles.each{ |v| v.cost_fixed = 5 }
      vrp.services.each{ |s| s.exclusion_cost = 1 }
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0].routes.all?{ |r| (r.stops.size - 2).zero? || r.stops.size - 2 >= 5 },
             'Expecting no route with less than 5 stops unless it is an empty route'
      assert_operator should_remain_assigned, :<=, (solutions[0].routes.sum{ |r| r.stops.size - 2 })
      assert_operator solutions[0].unassigned.size, :>=, should_remain_unassigned

      all_ids = solutions[0].routes.flat_map{ |route| route.stops.map(&:service_id) }.compact +
                solutions[0].unassigned.map(&:service_id).uniq
      assert_equal vrp.visits, all_ids.size
    end

    def test_performance_13vl
      vrps = TestHelper.load_vrps(self)

      unassigned_visits = []
      expected = vrps.sum(&:visits)
      seen = 0
      vrps.each{ |vrp|
        vrp.configuration.preprocessing.partitions = nil
        solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        unassigned_visits << solutions[0].unassigned.size
        seen += solutions[0].unassigned.size + solutions[0].routes.sum{ |r| r.stops.count(&:service_id) }
      }

      # voluntarily equal to watch evolution of periodic algorithm performance
      assert_equal expected, seen, 'Do not have the expected number of total visits'
      assert_equal 301, unassigned_visits.sum, 'Do not have the expected number of unassigned visits'
    end

    def test_fill_days_and_post_processing
      # checks performance on instance calling post_processing
      vrp = TestHelper.load_vrp(self, fixture_file: 'periodic_with_post_process')
      vrp.configuration.resolution.minimize_days_worked = true
      found_uninserted_visits = nil
      Wrappers::PeriodicHeuristic.stub_any_instance(
        :compute_initial_solution,
        lambda { |vrp_in|
          @starting_time = Time.now
          @candidate_routes = Marshal.load(File.binread('test/fixtures/fill_days_and_post_processing_candidate_routes.bindump')) # rubocop: disable Security/MarshalLoad
          @candidate_routes.each_value{ |vehicle_routes|
            vehicle_routes.each_value{ |day_route| day_route[:matrix_id] = vrp.vehicles.first.matrix_id }
          }
          @services_assignment = Marshal.load(File.binread('test/fixtures/fill_days_and_post_processing_services_assignment.bindump')) # rubocop: disable Security/MarshalLoad
          # We still have 1000 unassigned visits in this dumped solution

          refine_solution
          found_uninserted_visits = @services_assignment.sum{ |_id, data| data[:missing_visits] }
          prepare_output_and_collect_routes(vrp_in)
        }
      ) do
        periodic = Interpreters::PeriodicVisits.new(vrp)
        periodic.send(:expand, vrp, nil)
      end

      # voluntarily equal to watch evolution of periodic algorithm performance
      assert_equal 63, found_uninserted_visits, 'We started end_phase with 1000 unassigned, we should only have 74 left now'
    end

    def test_treatment_site
      # treatment site
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_empty solutions[0].unassigned
      assert_equal(262, solutions[0].routes.count{ |r|
        r.stops.any?{ |a| a.service_id&.include? 'service_0_' } && r.vehicle.id
      }) # one treatment site per day
      assert(solutions[0].routes.all?{ |r| r.stops[-2].service_id.include? 'service_0_' })

      vrp = TestHelper.load_vrp(self)
      vrp[:services].each{ |s|
        next if s[:id] == 'service_0' || s[:visits_number] == 1

        days_used = solutions[0].routes.select{ |r|
          r.stops.any?{ |a| a.service_id&.include? "#{s.id}_" }
        }.collect!{ |r| r.vehicle.id.split('_').last.to_i }.sort!
        assert_equal s[:visits_number], days_used.size
        (1..days_used.size - 1).each{ |index|
          assert days_used[index] - days_used[index - 1] >= s[:minimum_lapse]
        }
      }
    end

    def test_route_initialisation
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      assert_empty solutions[0].unassigned
      assert(solutions[0].routes.select{ |r|
        r.stops.any?{ |a| a.activity.point.id == '1000023' }
      }.all?{ |r| r.stops.any?{ |a| a.activity.point.id == '1000007' } })
      assert(solutions[0].routes.select{ |r|
        r.stops.any?{ |a| a.activity.point.id == '1000023' }
      }.all?{ |r| r.stops.any?{ |a| a.activity.point.id == '1000008' } })
    end

    def test_quality_with_minimum_stops_in_route
      vrp = TestHelper.load_vrp(self)
      vrp.configuration.resolution.minimize_days_worked = true
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert_operator solutions[0].unassigned.size, :<=, 10
    end
  end
end
