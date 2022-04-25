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
      # TODO: Remove it once the dicho contions are stabilized
      vrp.configuration.resolution.dicho_algorithm_service_limit = 457 # There are 458 services in the instance.

      t1 = Time.now
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      t2 = Time.now
      active_route_size = solutions[0].routes.count{ |route| route.count_services.positive? }
      # Check stops
      activity_assert_message =
        "Too many unassigned services (#{solutions[0].unassigned_stops.size}) for #{active_route_size} routes"
      if active_route_size > 12
        assert solutions[0].unassigned_stops.size <= 27, activity_assert_message
      elsif active_route_size == 12
        assert solutions[0].unassigned_stops.size <= 37, activity_assert_message
      elsif active_route_size == 11
        assert solutions[0].unassigned_stops.size <= 57, activity_assert_message
      else
        assert solutions[0].unassigned_stops.size <= 78, activity_assert_message
      end

      # Check routes
      route_assert_message =
        "Too many routes (#{active_route_size}) to have #{solutions[0].unassigned_stops.size} unassigned services"
      if solutions[0].unassigned_stops.size > 30
        assert active_route_size < 12, route_assert_message
      elsif solutions[0].unassigned_stops.size > 15
        assert active_route_size < 13, route_assert_message
      elsif solutions[0].unassigned_stops.size > 5
        assert active_route_size < 14, route_assert_message
      else
        assert active_route_size < 15, route_assert_message
      end

      # Check elapsed time
      min_dur = vrp.configuration.resolution.minimum_duration / 1000.0
      max_dur = vrp.configuration.resolution.duration / 1000.0

      assert solutions[0].elapsed / 1000 < max_dur, # Should never be violated!
             "Time spent in optimization (#{solutions[0].elapsed / 1000}) is greater than " \
             "the maximum duration asked (#{max_dur})."
      # Due to "no remaining jobs" in end_stage, it can be violated (randomly).
      assert solutions[0].elapsed / 1000 > min_dur * 0.95,
             "Time spent in optimization (#{solutions[0].elapsed / 1000}) is less than " \
             "the minimum duration asked (#{min_dur})."
      assert t2 - t1 > min_dur, "Too short elapsed time: #{t2 - t1}"
      assert t2 - t1 < max_dur * 1.35, # Due to API overhead, it can be violated (randomly).
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
      Interpreters::Dichotomous.stub(:kmeans, lambda{ |vrpi, cut_symbol|
        assert_operator counter, :<, 3, 'Interpreters::Dichotomous::kmeans is called too many times. Either there is an infinite loop due to imposible clustering or dicho split logic is altered.'
        counter += 1
        Interpreters::Dichotomous.send(:__minitest_stub__kmeans, vrpi, cut_symbol)
      }) do
        OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, problem, nil)
      end
    end

    def test_cluster_dichotomous_heuristic
      # Warning: This test is not enough to ensure that two services at the same point will
      # not end up in two different routes because after clustering there is tsp_simple.
      # In fact this check is too limiting because for this test to pass we disactivate
      # balancing in dicho_split at the last iteration.

      # TODO: Instead of disactivating balancing we can implement
      # clicque like preprocessing inside clustering that way it would be impossible for
      # two very close service ending up in two different routes.
      # Moreover, it would increase the performance of clustering.
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_dichotomous')
      service_vrp = { vrp: vrp, service: :demo, dicho_level: 0 }
      while service_vrp[:vrp].services.size > 100
        services_vrps_dicho = Interpreters::Dichotomous.split(service_vrp, nil)
        assert_equal 2, services_vrps_dicho.size

        locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.first.data_items.map{ |d| [d[0], d[1]] }
        locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.second.data_items.map{ |d| [d[0], d[1]] }
        assert_equal 0, (locations_one & locations_two).size

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

    def test_split_matrix
      vrp = TestHelper.load_vrp(self, fixture_file: 'dichotomous_approach')
      vrp.configuration.resolution.dicho_algorithm_service_limit = 457 # There are 458 services in the instance. TODO: Remove it once the dicho contions are stabilized
      service_vrp = { vrp: vrp, service: :demo, dicho_level: 0 }

      services_vrps = Interpreters::Dichotomous.split(service_vrp)
      services_vrps.each{ |service_vrp_in|
        assert_equal service_vrp_in[:vrp].points.size, service_vrp_in[:vrp].matrices.first.time.size
        assert_equal service_vrp_in[:vrp].points.size, service_vrp_in[:vrp].matrices.first.distance.size
      }
    end

    def test_kmeans_function_with_services_at_same_location
      vrp = TestHelper.load_vrp(self, fixture_file: 'two_phases_clustering_sched_with_freq_and_same_point_day_5veh')
      assert vrp.services.group_by{ |s| s.activity.point_id }.any?{ |_pt_id, set| set.size > 1 }, 'This test is useless if there are not several services with same point_id'
      split = Interpreters::Dichotomous.send(:kmeans, vrp, :duration)
      assert_equal 2, split.size
      assert_equal vrp.services.size, split.collect(&:size).sum, 'Wrong number of services will be returned'
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
        Interpreters::Dichotomous.stub(:transfer_unused_vehicles, lambda{ |service_vrp, result, sub_service_vrps|
          sub_service_vrps[0][:vrp].vehicles << Helper.deep_copy(
            sub_service_vrps[0][:vrp].vehicles.last,
            override: { id: 'extra_unused_vehicle' },
            shallow_copy: [:start_point] # regenerate end_point to check
          )
          service_vrp[:vrp].points << sub_service_vrps[0][:vrp].vehicles.last.end_point
          sub_service_vrps[0][:vrp].points << sub_service_vrps[0][:vrp].vehicles.last.end_point

          Interpreters::Dichotomous.send(:__minitest_stub__transfer_unused_vehicles, service_vrp, result, sub_service_vrps)

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