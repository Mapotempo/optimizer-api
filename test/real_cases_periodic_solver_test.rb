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
    def test_periodic_and_ortools
      vrps = TestHelper.load_vrps(self)

      vrps.each{ |vrp|
        vrp.preprocessing_partitions = nil
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
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      vrp[:services].group_by{ |s| s[:activity][:point][:id] }.each{ |point_id, services_set|
        expected_number_of_days = services_set.collect{ |service| service[:visits_number] }.max
        days_used = result[:routes].count{ |r| r[:activities].count{ |stop| stop[:point_id] == point_id } > 0 }
        assert_operator days_used, :<=, expected_number_of_days,
                        "Used #{days_used} for point #{point_id} instead of #{expected_number_of_days} expected."
      }

      # check performance :
      limit = vrp.visits * 6 / 100.0
      assert_operator result[:unassigned].size, :<, limit,
                      "#{result[:unassigned].size * 100.0 / vrp.visits}% unassigned instead of #{limit}% authorized"
      assert result[:unassigned].none?{ |un| un[:reason].include?(' vehicle ') },
             'Some services could not be assigned to a vehicle'
    end

    def test_performance_12vl_with_solver
      vrps = TestHelper.load_vrps(self, fixture_file: 'performance_12vl')

      unassigned_visits = vrps.each.with_index.inject(0){ |unassigned_nb, (vrp, vrp_i)|
        puts "Solving problem #{vrp_i + 1}/#{vrps.size}..."
        vrp.preprocessing_partitions = nil
        vrp.resolution_solver = true
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        unassigned_nb + result[:unassigned].size
      }
      assert_operator unassigned_visits, :<=, 248, 'Expecting less unassigned visits'
    end

    def test_performance_britanny_with_solver
      unassigned_count = Array.new(3){
        vrp = TestHelper.load_vrp(self, fixture_file: 'performance_britanny')
        result = nil
        Interpreters::SplitClustering.stub(:kmeans_process, lambda{ |nb_clusters, data_items, related_item_indices, limits, options|
          options.delete(:distance_matrix)
          options[:restarts] = 4
          Interpreters::SplitClustering.send(:__minitest_stub__kmeans_process, nb_clusters, data_items, related_item_indices, limits, options) # call original method
        }) do
          result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
        end
        result[:unassigned].size
      }

      # should almost never violated (if happens twice, most probably there is a perf degredation)
      assert_operator unassigned_count.mean, :<=, 180, "#{unassigned_count}.mean should be smaller"
      assert_operator unassigned_count.min, :<=, 120, "#{unassigned_count}.min should be smaller"
      assert_operator unassigned_count.max, :<=, 240, "#{unassigned_count}.max should be smaller"
    end

    def test_without_same_point_day
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_solver = false
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      unassigned = result[:unassigned].size
      assert_equal 46, unassigned

      vrp = TestHelper.load_vrp(self)
      vrp.resolution_solver = true
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert unassigned >= result[:unassigned].size
    end
  end
end
