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
      vrps = FCT.load_vrps(self)
      FCT.multipe_matrices_required(vrps, self)
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
      vrp = FCT.load_vrp(self, fixture_file: 'two_phases_clustering_sched_with_freq_and_same_point_day_5veh')
      vrp.resolution_solver = true
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      assert_equal vrp.visits, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size,
                   "Found #{result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size} instead of #{vrp.visits} expected"

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].collect{ |r| r[:activities].select{ |stop| stop[:point_id] == point_id }.size }.select(&:positive?).size
        assert days_used <= expected_number_of_days, "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }

      assert result[:unassigned].size < vrp.visits * 6 / 100.0, "#{(result[:unassigned].size * 100.0 / vrp.visits).round(2)}% unassigned instead of 6% authorized"
      assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') }, 'Some services could not be assigned to a vehicle'
    end

    def test_performance_12vl_with_solver
      vrps = FCT.load_vrps(self, fixture_file: 'performance_12vl')
      FCT.multipe_matrices_required(vrps, self)

      unassigned_visits = []
      unassigned_services = []
      vrps.each_with_index{ |vrp, vrp_i|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}..."
        vrp.preprocessing_partitions = nil
        vrp.name = nil
        vrp.resolution_solver = true
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
        unassigned_visits << result[:unassigned].size
        unassigned_services << result[:unassigned].collect{ |un| un[:service_id].split('_')[0..-3].join('_') }.uniq.size
      }

      assert unassigned_visits.sum <= 600, "Expecting 600 unassigned visits, have #{unassigned_visits.sum}"
    end

    def test_performance_13vl_with_solver # pb with this test at the end ! try with small restarts and splits
      vrps = FCT.load_vrps(self, fixture_file: 'performance_13vl')
      FCT.multipe_matrices_required(vrps, self)

      unassigned_visits = []
      unassigned_services = []
      vrps.each_with_index{ |vrp, vrp_i|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}"
        vrp.preprocessing_partitions = nil
        vrp.name = nil
        vrp.resolution_solver = true
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
        unassigned_visits << result[:unassigned].size
        unassigned_services << result[:unassigned].collect{ |un| un[:service_id].split('_')[0..-3].join('_') }.uniq.size
      }

      assert_equal unassigned_visits.sum <= 321, "Expecting 321 unassigned visits, have #{unassigned_visits.sum}"
    end
  end
end
