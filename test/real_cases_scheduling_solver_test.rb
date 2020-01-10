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
    def test_scheduling_and_ortools
      vrps = TestHelper.load_vrps(self)
      TestHelper.multipe_matrices_required(vrps, self)
      vrps.each{ |vrp|
        vrp.preprocessing_partitions = nil
        vrp.name = nil
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil) # marshal dump needed, otherwise we create relations (min/maximum lapse)
        unassigned = result[:unassigned].size

        vrp.resolution_solver = true
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        assert unassigned >= result[:unassigned].size, "Increased number of unassigned with ORtools : had #{unassigned}, has #{result[:unassigned].size} now"
      }
    end

    def test_two_phases_clustering_sched_with_freq_and_same_point_day_5veh_with_solver
      vrp = TestHelper.load_vrp(self, fixture_file: 'two_phases_clustering_sched_with_freq_and_same_point_day_5veh')
      vrp.resolution_solver = true
      vrp.preprocessing_partitions.each{ |p| p.restarts = 1 }
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      assert_equal vrp.visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size,
                   "Found #{result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size} instead of #{vrp.visits} expected"

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].collect{ |r| r[:activities].select{ |stop| stop[:point_id] == point_id }.size }.select(&:positive?).size
        assert days_used <= expected_number_of_days, "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }

      limit = ENV['TRAVIS'] ? vrp.visits * 6.8 / 100.0 : vrp.visits * 6 / 100.0
      assert result[:unassigned].size < limit, "#{result[:unassigned].size * 100.0 / vrp.visits}% unassigned instead of #{limit}% authorized"
      assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') }, 'Some services could not be assigned to a vehicle'
    end

    def test_performance_12vl_with_solver
      vrps = TestHelper.load_vrps(self, fixture_file: 'performance_12vl')
      TestHelper.multipe_matrices_required(vrps, self)

      assigned_visits = []
      unassigned_visits = []
      vrps.each_with_index{ |vrp, vrp_i|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}..."
        vrp.preprocessing_partitions = nil
        vrp.name = nil
        vrp.resolution_solver = true
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
        assigned_visits << result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum
        unassigned_visits << result[:unassigned].size
      }
      assert_equal vrps.collect(&:visits).sum + vrps.collect{ |vrp| vrp.services.select{ |s| s[:visits_number].zero? }.size }.sum, assigned_visits.sum + unassigned_visits.sum,
                   "Expecting #{vrps.collect(&:visits).sum} visits, only have #{vrps.collect(&:visits).sum}"
      assert unassigned_visits.sum <= 441, "Expecting less than 441 unassigned visits, have #{unassigned_visits.sum}"
    end
  end
end
