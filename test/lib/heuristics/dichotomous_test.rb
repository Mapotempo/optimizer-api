# Copyright © Mapotempo, 2018
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

class DichotomousTest < Minitest::Test
  if !ENV['SKIP_DICHO']
    def test_dichotomous_approach
      vrp = TestHelper.load_vrp(self)

      vrp.configuration.resolution.dicho_algorithm_service_limit = 457 # There are 458 services in the instance.

      vrp.configuration.resolution.minimum_duration = 60000 # instead of the original 480 and 540 seconds
      vrp.configuration.resolution.duration = 120000

      t1 = Time.now
      solution = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)[0]
      t2 = Time.now

      active_route_size = solution.routes.count{ |route| route.count_services.positive? }

      # Check solution quality
      soln_quality_assert_message =
        "Too many unassigned services (#{solution.unassigned_stops.size}) for #{active_route_size} routes"
      if active_route_size > 12
        assert solution.unassigned_stops.size <= 13, soln_quality_assert_message
      elsif active_route_size == 12
        assert solution.unassigned_stops.size <= 21, soln_quality_assert_message
      elsif active_route_size == 11
        assert solution.unassigned_stops.size <= 31, soln_quality_assert_message
      else
        assert solution.unassigned_stops.size <= 40, soln_quality_assert_message
      end

      # Check elapsed time
      max_dur = vrp.configuration.resolution.duration / 1000.0
      min_dur = vrp.configuration.resolution.minimum_duration / 1000.0

      assert solution.elapsed / 1000 < max_dur * 1.01, # Should never be violated!
             "Time spent in optimization (#{solution.elapsed / 1000}) is greater than " \
             "the maximum duration asked (#{max_dur})."
      # Due to "no remaining jobs" in end_stage, it can be violated (randomly but very rarely).
      assert solution.elapsed / 1000 > min_dur * 0.99,
             "Time spent in optimization (#{solution.elapsed / 1000}) is less than " \
             "the minimum duration asked (#{min_dur})."
      assert t2 - t1 < max_dur * 2, # Due to API overhead, it can be violated (randomly but very rarely).
                                    # Since the optimisation time is short the relative overhead is big.
             "Time spend in the API (#{t2 - t1}) is too big compared to maximum " \
             "optimization duration asked (#{max_dur})."
    end

    def test_dichotomous_condition_limits
      # Currently dicho limit is set to 500 which is less than the default max_split_size.
      # That is, one needs to manually set max_split_size to a higher value to use dicho.
      # If the dicho limits are changed the test needs to be corrected with new values.

      limits = { service: 500, vehicle: 10 } # Do not replace with class values, correct manually.

      limit_vrp = VRP.toy

      limit_vrp[:services] = []
      limits[:service].times{ |i|
        limit_vrp[:services] << { id: "s#{i + 1}", activity: { point_id: 'p1' }}
      }

      limit_vrp[:vehicles] = []
      limits[:vehicle].times{ |i|
        limit_vrp[:vehicles] << { id: "v#{i + 1}", router_mode: 'car', router_dimension: 'time', skills: [[]] }
      }

      refute Interpreters::Dichotomous.dichotomous_candidate?(vrp: TestHelper.create(limit_vrp), service: :demo, dicho_level: 0)

      vrp = limit_vrp.dup
      vrp[:vehicles] = limit_vrp[:vehicles].dup
      vrp[:vehicles] << { id: "v#{limits[:vehicle] + 1}", router_mode: 'car', router_dimension: 'time', skills: [[]] }
      refute Interpreters::Dichotomous.dichotomous_candidate?(vrp: TestHelper.create(vrp), service: :demo, dicho_level: 0)

      vrp = limit_vrp.dup
      vrp[:services] = limit_vrp[:services].dup
      vrp[:services] << { id: "s#{limits[:service] + 1}", activity: { point_id: 'p1' }}
      refute Interpreters::Dichotomous.dichotomous_candidate?(vrp: TestHelper.create(vrp), service: :demo, dicho_level: 0)

      vrp = limit_vrp.dup
      vrp[:services] << { id: "s#{limits[:service] + 1}", activity: { point_id: 'p1' }}
      vrp[:vehicles] << { id: "v#{limits[:vehicle] + 1}", router_mode: 'car', router_dimension: 'time', skills: [[]] }
      assert Interpreters::Dichotomous.dichotomous_candidate?(vrp: TestHelper.create(vrp), service: :demo, dicho_level: 0)
    end

    def test_infinite_loop_due_to_impossible_to_cluster
      vrp = VRP.lat_lon
      vrp[:configuration][:resolution][:duration] = 20
      vrp[:points].each{ |p| p[:location] = { lat: 45, lon: 5 } } # all at the same location (impossible to cluster)

      vrp[:matrices][0][:time] = Array.new(7){ Array.new(7, 1) }
      vrp[:matrices][0][:time].each_with_index{ |row, i| row[i] = 0 }
      vrp[:matrices][0][:distance] = vrp[:matrices][0][:time]

      vrp[:services].each{ |s| s[:activity][:duration] = 500 }

      vrp[:vehicles].first[:duration] = 3600
      vrp[:vehicles] << vrp[:vehicles].first.dup
      vrp[:vehicles].last[:id] = 'v_1'

      problem = TestHelper.create(vrp)

      problem.configuration.resolution.dicho_algorithm_vehicle_limit = 1
      problem.configuration.resolution.dicho_division_vehicle_limit = 1
      problem.configuration.resolution.dicho_algorithm_service_limit = 5
      problem.configuration.resolution.dicho_division_service_limit = 5

      counter = 0
      level = nil
      Interpreters::Dichotomous.stub(:split, lambda{ |vrpi, cut_symbol|
        assert_operator counter, :<, 3, 'Interpreters::Dichotomous::split is called too many times. Either there is an infinite loop due to imposible clustering or dicho split logic is altered.'

        if vrpi[:dicho_level] != level
          level = vrpi[:dicho_level]
          counter = 1
        else
          counter += 1
        end

        Interpreters::Dichotomous.send(:__minitest_stub__split, vrpi, cut_symbol)
      }) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, problem, nil)
      end
    end

    def test_cluster_dichotomous_heuristic
      # Warning: This test is not enough to ensure that two services at the same point will
      # not end up in two different routes because after clustering there is tsp_simple.
      # In fact this check is too limiting because for this test to pass we deactivate
      # balancing in dicho_split at the last iteration.

      # TODO: Instead of deactivating balancing we can implement
      # clique like preprocessing inside clustering that way it would be impossible for
      # two very close service ending up in two different routes.
      # Moreover, it would increase the performance of clustering.
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_dichotomous')
      vrp.vehicles = vrp.vehicles[0..60] # no need for all vehicles
      service_vrp = { vrp: vrp, service: :demo, dicho_level: 0, dicho_denominators: [1], dicho_sides: [0] }
      while service_vrp[:vrp].services.size > 100
        services_vrps_dicho = Interpreters::Dichotomous.split(service_vrp, nil)
        assert_equal 2, services_vrps_dicho.size

        locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.first.data_items.map{ |d| [d[0], d[1]] }
        locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.second.data_items.map{ |d| [d[0], d[1]] }
        # split is done by vehicle + by representative_vrp so this might lead to some points get split between sides
        # but this should not be an issue because the optimisation should handle such points if they can be performed
        # on the same vehicle.
        # The solution is to improve the vehicle_compatibility logic and using it inside collect_data
        assert_operator 3, :>=, (locations_one & locations_two).size, 'There should not be too many "split" points'

        durations = []
        services_vrps_dicho.each{ |service_vrp_dicho|
          durations << service_vrp_dicho[:vrp].services_duration
        }
        assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i
        assert services_vrps_dicho[0][:vrp].vehicles.size >= services_vrps_dicho[1][:vrp].vehicles.size, 'Dicho should start solving the side with more vehicles first'

        average_duration = durations.sum / durations.size
        # Clusters should be balanced but the priority is the geometry
        range = 0.6
        min_duration = (1.0 - range) * average_duration
        max_duration = (1.0 + range) * average_duration
        durations.each_with_index{ |duration, index|
          assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
        }

        service_vrp = services_vrps_dicho.min_by{ |sv| sv[:vrp].services_duration }
      end
    end

    def test_no_dichotomous_when_no_location
      problem = VRP.basic
      problem[:vehicles] << problem[:vehicles].first.merge({ id: 'another_vehicle' })
      problem[:configuration][:resolution][:dicho_algorithm_service_limit] = 0
      vrp = TestHelper.create(problem)
      service_vrp = { vrp: vrp, service: :demo }

      vrp.configuration.resolution.dicho_algorithm_vehicle_limit = 0

      refute Interpreters::Dichotomous.dichotomous_candidate?(service_vrp), 'no dicho if no location'

      location = Models::Location.new(lat: 0, lon: 0)
      vrp.points.map!{ |point| point.tap{ |p| p.location = location } }

      assert Interpreters::Dichotomous.dichotomous_candidate?(service_vrp), 'dicho if all has location'
    end

    def test_split_function_with_services_at_same_location
      vrp = TestHelper.load_vrp(self, fixture_file: 'two_phases_clustering_sched_with_freq_and_same_point_day_5veh')
      assert vrp.services.group_by{ |s| s.activity.point_id }.any?{ |_pt_id, set| set.size > 1 }, 'This test is useless if there are not several services with same point_id'
      split = Interpreters::Dichotomous.send(:split, { vrp: vrp, dicho_sides: [], dicho_denominators: [], dicho_level: 0 })
      assert_equal 2, split.size
      assert_equal vrp.services.size, split.sum{ |s| s[:vrp].services.size }, 'Wrong number of services returned'
    end

    def test_rest_cannot_appear_as_a_mission_in_the_initial_route
      rest = Models::Rest.new(id: 'id')
      route_rest = Models::Solution::Stop.new(rest)
      solution_route = Models::Solution::Route.new(stops: [route_rest])
      initial_solution = Models::Solution.new(routes: [solution_route])
      assert_empty Interpreters::Dichotomous.send(:build_initial_routes, [initial_solution])
    end

    def test_dichotomous_approach_transfer_unused_vehicles_transfers_points_correctly
      vrp = VRP.lat_lon
      vrp[:configuration][:resolution][:duration] = 6
      vrp[:vehicles].first[:duration] = 1 # no need to plan the services
      vrp[:vehicles] << vrp[:vehicles].first.dup
      vrp[:vehicles].last[:id] = 'v_1'

      Interpreters::Dichotomous.stub(:dichotomous_candidate?, lambda{ |service_vrp|
        # modify limits so that the vrp will be dicho_split one and only one time
        service_vrp[:vrp].configuration.resolution.dicho_division_service_limit = 5
        service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit = 1
        true
      }) do
        Interpreters::Dichotomous.stub(:transfer_unused_vehicles, lambda{ |result, sub_service_vrps|
          sub_service_vrps[0][:vrp].vehicles << Helper.deep_copy(
            sub_service_vrps[0][:vrp].vehicles.last,
            override: { id: 'extra_unused_vehicle' },
            shallow_copy: [:start_point] # regenerate end_point to check
          )
          sub_service_vrps[0][:vrp].points << sub_service_vrps[0][:vrp].vehicles.last.end_point

          Interpreters::Dichotomous.send(:__minitest_stub__transfer_unused_vehicles, result, sub_service_vrps)

          sv_one = sub_service_vrps[1][:vrp]
          transferred_vehicle = sv_one.vehicles.last
          assert_equal 'extra_unused_vehicle', transferred_vehicle.id, 'transfer_unused_vehicles should have transfer the extra vehicle'

          point_ids = sv_one.points.map(&:id)
          assert_equal point_ids.size, point_ids.uniq.size, 'There are duplicate points after transfer_unused_vehicles'
          assert sv_one.points.any?{ |p| p.object_id == transferred_vehicle.start_point.object_id }, "transferred vehicle's start_point doesn't exist in points"
          assert sv_one.points.any?{ |p| p.object_id == transferred_vehicle.end_point.object_id }, "transferred vehicle's end_point doesn't exist in points"
        }) do
          OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
        end
      end
    end
  end
end
