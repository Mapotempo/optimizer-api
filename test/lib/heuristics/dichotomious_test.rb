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

class DichotomiousTest < Minitest::Test
  if !ENV['SKIP_DICHO']
    def test_dichotomious_approach
      vrp = FCT.load_vrp(self)
      vrp.resolution_dicho_algorithm_service_limit = 457 # There are 458 services in the instance. TODO: Remove it once the dicho contions are stabilized

      if ENV['TRAVIS'] # Compansate for travis performance
        vrp[:configuration][:resolution][:minimum_duration] *= 1.50
        vrp[:configuration][:resolution][:duration] *= 1.50
        vrp.resolution_duration *= 1.50
        vrp.resolution_minimum_duration *= 1.50
      end

      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      t2 = Time.now
      assert result

      # Check activities
      if result[:routes].size > 11
        assert result[:unassigned].size < 25, "Too many unassigned services (#{result[:unassigned].size}) for #{result[:routes].size} routes"
      elsif result[:routes].size == 11
        assert result[:unassigned].size < 30, "Too many unassigned services (#{result[:unassigned].size}) for #{result[:routes].size} routes"
      else
        assert result[:unassigned].size < 55, "Too many unassigned services (#{result[:unassigned].size}) for #{result[:routes].size} routes"
      end

      # Check routes
      if result[:unassigned].size > 30
        assert result[:routes].size < 12, "Too many routes (#{result[:routes].size}) to have #{result[:unassigned].size} unassigned services"
      elsif result[:unassigned].size > 15
        assert result[:routes].size < 13, "Too many routes (#{result[:routes].size}) to have #{result[:unassigned].size} unassigned services"
      elsif result[:unassigned].size > 5
        assert result[:routes].size < 14, "Too many routes (#{result[:routes].size}) to have #{result[:unassigned].size} unassigned services"
      else
        assert result[:routes].size < 15, "Too many routes (#{result[:routes].size}) to have #{result[:unassigned].size} unassigned services"
      end

      # Check elapsed time
      min_dur = vrp[:configuration][:resolution][:minimum_duration] / 1000.0
      max_dur = vrp[:configuration][:resolution][:duration] / 1000.0

      assert result[:elapsed] / 1000 < max_dur, "Time spent in optimization (#{result[:elapsed] / 1000}) is greater than the maximum duration asked (#{max_dur})." # Should never be violated!
      assert result[:elapsed] / 1000 > min_dur, "Time spent in optimization (#{result[:elapsed] / 1000}) is less than the minimum duration asked (#{min_dur})." # Due to "no remaining jobs" in end_stage, it can be violated (randomly).
      assert t2 - t1 > min_dur, "Too short elapsed time: #{t2 - t1}"
      assert t2 - t1 < max_dur * 1.35, "Time spend in the API (#{t2 - t1}) is too big compared to maximum optimization duration asked (#{max_dur})." # Due to API overhead, it can be violated (randomly) .
    end

    def test_cluster_dichotomious_heuristic
      # Warning: This test is not enough to ensure that two services at the same point will
      # not end up in two different routes because after clustering there is tsp_simple.
      # In fact this check is too limiting because for this test to pass we disactivate
      # balancing in dicho_split at the last iteration.

      # TODO: Instead of disactivating balancing we can implement
      # clicque like preprocessing inside clustering that way it would be impossible for
      # two very close service ending up in two different routes.
      # Moreover, it would increase the performance of clustering.
      vrp = FCT.load_vrp(self, fixture_file: 'cluster_dichotomious')
      service_vrp = { vrp: vrp, service: :demo, level: 0 }
      while service_vrp[:vrp].services.size > 100
        services_vrps_dicho = Interpreters::Dichotomious.split(service_vrp, nil)
        assert_equal 2, services_vrps_dicho.size

        locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.first.data_items.map{ |d| [d[0], d[1]] }
        locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.second.data_items.map{ |d| [d[0], d[1]] }
        assert_equal 0, (locations_one & locations_two).size

        durations = []
        services_vrps_dicho.each{ |service_vrp_dicho|
          durations << service_vrp_dicho[:vrp].services_duration
        }
        assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i
        assert durations[0] <= durations[1]

        average_duration = durations.inject(0, :+) / durations.size
        # Clusters should be balanced but the priority is the geometry
        min_duration = average_duration - 0.5 * average_duration
        max_duration = average_duration + 0.5 * average_duration
        durations.each_with_index{ |duration, index|
          assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
        }

        service_vrp = services_vrps_dicho.first
      end
    end

    def test_no_dichotomious_when_no_location
      vrp = FCT.load_vrp(self)
      service_vrp = { vrp: vrp, service: :demo }

      assert !Interpreters::Dichotomious.dichotomious_candidate?(service_vrp)
    end

    def test_split_matrix
      vrp = FCT.load_vrp(self, fixture_file: "dichotomious_approach")
      vrp.resolution_dicho_algorithm_service_limit = 457 # There are 458 services in the instance. TODO: Remove it once the dicho contions are stabilized
      service_vrp = { vrp: vrp, service: :demo, level: 0 }

      services_vrps = Interpreters::Dichotomious.split(service_vrp)
      services_vrps.each{ |service_vrp|
        assert_equal service_vrp[:vrp].points.size, service_vrp[:vrp].matrices.first.time.size
        assert_equal service_vrp[:vrp].points.size, service_vrp[:vrp].matrices.first.distance.size
      }
    end
  end
end
