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
require './lib/interpreters/split_clustering.rb'

class SplitClusteringTest < Minitest::Test
  if !ENV['SKIP_SPLIT_CLUSTERING']
    def setup
      @split_restarts = ENV['INTENSIVE_TEST'] ? 20 : 5
      @regularity_restarts = ENV['INTENSIVE_TEST'] ? 20 : 5
    end

    def test_cluster_balance
      # Clusters should be well balanced
      # The test is done dicho-style (but not for dicho). A vrp is split into two sub-vrps
      # then one of the sub-vrps replace the current vrp and it is split into two sub-vrps.
      # The routine continues until the current vrp is too small.
      # During this process max balance deviation is recorded and the process is restarted
      # @regularity_restarts times so that clustering irregularity does not effect the results.
      # Basically, we want the balance violations to be as small as possible.

      balance_deviations = []
      (1..@regularity_restarts).each{ |trial|
        puts "Regularity trial: #{trial}/#{@regularity_restarts}"
        max_balance_deviation = 0

        service_vrp = { vrp: TestHelper.load_vrp(self, fixture_file: 'cluster_dichotomious'), service: :demo }
        service_vrp[:vrp].services.each{ |s| s.skills = [] }         # The instance has "Pas X" style day skills, we purposely ignore them otherwise balance is not possible
        service_vrp[:vrp].vehicles = [service_vrp[:vrp].vehicles[0]] # entity: `vehicle` settting only makes sense if the number of clusters is equal to the number of vehicles.
        service_vrp[:vrp].vehicles *= 2

        while service_vrp[:vrp].services.size > 100
          total_load_by_units = Hash.new(0)
          service_vrp[:vrp].services.each{ |s| s.quantities.each{ |q| total_load_by_units[q.unit.id] += q.value } }

          # Correct the capacity of the vehicles wrt the services in the sub_vrp
          service_vrp[:vrp][:vehicles].each{ |v|
            v.capacities = []
            service_vrp[:vrp].units.each{ |u|
              v.capacities << Models::Capacity.new(unit: u, limit: total_load_by_units[u.id] * 0.65)
            }
          }

          services_vrps_dicho = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 2, cut_symbol: :duration, entity: 'vehicle', restarts: 2) # Do not use @split_restarts it changes the stats
          assert_equal 2, services_vrps_dicho.size, 'The number of clusters is not correct'

          durations = services_vrps_dicho.collect{ |s| s[:vrp].services_duration }
          assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i, 'The sum of service durations is not correct'

          max_balance_deviation = [max_balance_deviation, durations.max.to_f / durations.sum * 2 - 1].max

          service_vrp = services_vrps_dicho.first
        end

        balance_deviations << max_balance_deviation
      }

      # The limits of max_dev and the RHS of the asserts represent the current performance of the clustering algorighm.
      # The limit values are tightest possible to ensure that any degredation would trip the assert.
      # False negative are rare, once every ~10 runs on local and once every ~30 runs on Travis.
      # That is, if the test fails there probably is a performance degredation.
      asserts = [
        {
          condition: balance_deviations.count{ |max_dev| max_dev > 0.25 } <= (@regularity_restarts * 0.02).ceil,
          message: 'The maximum balance deviation can be larger than 25% only very rarely -- <2% of the trials.'
        }, {
          condition: balance_deviations.count{ |max_dev| max_dev > 0.21 } <= (@regularity_restarts * 0.20).ceil,
          message: 'The maximum balance deviation sould not be larger than 21% for more than 20% of the trials.'
        }, {
          condition: balance_deviations.count{ |max_dev| max_dev > 0.17 } <= (@regularity_restarts * 0.35).ceil,
          message: 'The maximum balance deviation sould not be larger than 17% for more than 35% of the trials.'
        }, {
          condition: balance_deviations.count{ |max_dev| max_dev <= 0.135 } >= (@regularity_restarts * 0.45).floor,
          message: 'The maximum balance deviation sould be less than 13.5% most of the time -- >45% of the trials.'
        }
      ]

      log balance_deviations.collect{ |i| i.round(3) }, level: :fatal if asserts.any?{ |assert| !assert[:condition] }

      asserts.each { |assert|
        assert assert[:condition], assert[:message]
      }
    end

    def test_same_location_different_clusters
      skip "This test fails. It is created for Test-Driven Development.
            The functionality is not ready yet, it is skipped for devs not working on the functionality.
            Basically, we want to be able to cluster with balancing (i.e., rate_balance != 0) but
            we expect that the services of same lat/lng end up in the same cluster.
            To achieve this,
            either the duplicate points need to be eliminated (data_set is created by points)
            or data_set needs to be created by lat/lon instead of by points (eliminates the possiblity of two items of the same lat/lon)
            or balanced_kmeans can have a preprocessing (which uses compatibility function to check if points can be merged)."

      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_dichotomious')
      service_vrp = { vrp: vrp, service: :demo }
      vrp.services.each{ |s| s.skills = [] }                 # The instance has old "Pas X" style day skills, we purposely ignore them otherwise balance is not possible
      original_vehicles = service_vrp[:vrp][:vehicles][0..1] # entity: `vehicle` settting only works if the number of clusters is equal to the number of vehicles.
      while service_vrp[:vrp].services.size > 100
        total = Hash.new(0)
        service_vrp[:vrp].services.each{ |s| s.quantities.each{ |q| total[q.unit.id] += q.value } }
        original_vehicles.each{ |v|
          v.capacities = []
          service_vrp[:vrp].units.each{ |u|
            v.capacities << Models::Capacity.new(unit: u, limit: total[u.id] * 0.65)
          }
        }
        service_vrp[:vrp][:vehicles] = original_vehicles
        services_vrps_dicho = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 2, cut_symbol: :duration, entity: 'vehicle', restarts: @split_restarts)

        ## TODO: with rate_balance != 0 there is risk to get services of same lat/lng in different clusters
        locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.first.data_items.map{ |d| [d[0], d[1]] }
        locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] } # clusters.second.data_items.map{ |d| [d[0], d[1]] }
        (locations_one & locations_two).each{ |loc|
          point_id_first = services_vrps_dicho.first[:vrp].points.find{ |p| p.location.lat == loc[0] && p.location.lon == loc[1] }.id
          puts "service from #{point_id_first} in cluster #0" + services_vrps_dicho.first[:vrp].services.select{ |s| s.activity.point_id == point_id_first }.to_s
          point_id_second = services_vrps_dicho.second[:vrp].points.find{ |p| p.location.lat == loc[0] && p.location.lon == loc[1] }.id
          puts "service from #{point_id_second} in cluster #1" + services_vrps_dicho.second[:vrp].services.select{ |s| s.activity.point_id == point_id_second }.to_s
        }
        assert_equal 0, (locations_one & locations_two).size

        service_vrp = services_vrps_dicho.first
      end
    end

    def test_cluster_one_phase_work_day
      skip "This test fails. The test is created for Test-Driven Development.
            The functionality is not ready yet, it is skipped for devs not working on the functionality.
            Basically, we want to be able to cluster in one single step (instead of by-vehicle and then by-day) and
            we expect that the clusters are balanced. However, currently it takes too long and the results are not balanced."
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_two_phases')
      service_vrp = { vrp: vrp, service: :demo }
      services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 80, cut_symbol: :duration, entity: 'work_day', restarts: @split_restarts)
      assert_equal 80, services_vrps_days.size

      durations = []
      services_vrps_days.each{ |service_vrp_day|
        durations << service_vrp_day[:vrp].services_duration
      }

      average_duration = durations.inject(0, :+) / durations.size
      min_duration = average_duration - 0.5 * average_duration
      max_duration = average_duration + 0.5 * average_duration
      o = durations.map{ |duration|
        # assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
        duration < max_duration && duration > min_duration
      }
      assert o.select{ |i| i }.size > 0.9 * o.size, "Cluster durations are not balanced: #{durations.inspect}" # TODO: All clusters should be balanced -- i.e., not just 90% of them
    end

    def test_cluster_one_phase_vehicle
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_one_phase')
      TestHelper.matrix_required(vrp)
      service_vrp = { vrp: vrp, service: :demo }

      total_durations = vrp.services_duration
      services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, cut_symbol: :duration, entity: 'vehicle', restarts: @split_restarts)
      assert_equal 5, services_vrps_vehicles.size

      durations = []
      services_vrps_vehicles.each{ |service_vrp_vehicle|
        durations << service_vrp_vehicle[:vrp].services_duration
      }
      # First balanced duration should be the smallest according vehicle data
      assert 0, durations.index(durations.min)

      cluster_weight_sum = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.sum
      minimum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.min
      # maximum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.max
      durations.each_with_index{ |duration, index|
        # assert duration < (maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be less than #{(maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum}"
        assert duration > (minimum_sequence_timewindows - 1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be more than #{(minimum_sequence_timewindows - 1) * total_durations / cluster_weight_sum}"
      }
    end

    def test_cluster_two_phases
      vrp = TestHelper.load_vrp(self)
      TestHelper.matrix_required(vrp)
      service_vrp = { vrp: vrp, service: :demo }
      services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 16, cut_symbol: :duration, entity: 'vehicle', restarts: @split_restarts)
      assert_equal 16, services_vrps_vehicles.size

      durations = []
      services_vrps_vehicles.each{ |service_vrp_vehicle|
        durations << service_vrp_vehicle[:vrp].services_duration
      }
      average_duration = durations.inject(0, :+) / durations.size
      min_duration = average_duration - 0.5 * average_duration
      max_duration = average_duration + 0.5 * average_duration

      durations.each_with_index{ |duration, index|
        assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration.round(2)}) should be between #{min_duration.round(2)} and #{max_duration.round(2)}. All durations #{durations.inspect}"
      }

      overall_min_duration = average_duration
      overall_max_duration = 0.0

      services_vrps_vehicles.each{ |services_vrps|
        durations = []
        vehicles = (0..4).collect{ |v_i|
          vehicle = Marshal.load(Marshal.dump(services_vrps[:vrp][:vehicles].first))
          vehicle[:sequence_timewindows] = [vehicle[:sequence_timewindows][v_i]]
          vehicle
        }
        services_vrps[:vrp][:vehicles] = vehicles
        services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(services_vrps, 5, cut_symbol: :duration, entity: 'work_day', restarts: @split_restarts)
        assert_equal 5, services_vrps.size
        services_vrps.each{ |service_vrp_day|
          next if service_vrp_day[:vrp].points.size < 10

          durations << service_vrp_day[:vrp].services_duration
        }
        next if durations.empty?

        average_duration = durations.inject(0, :+) / durations.size
        min_duration = average_duration - 0.7 * average_duration
        max_duration = average_duration + 0.7 * average_duration
        durations.each_with_index{ |duration, index|
          assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration.round(2)}) should be between #{min_duration.round(2)} and #{max_duration.round(2)}"
        }
        overall_min_duration = [overall_min_duration, durations.min].min
        overall_max_duration = [overall_max_duration, durations.max].max
      }
      assert overall_max_duration / overall_min_duration < 3.5, "Difference between overall (over all vehicles and all days) min and max duration is too much (#{overall_min_duration.round(2)} and #{overall_max_duration.round(2)})."
    end

    def test_length_centroid
      vrp = TestHelper.load_vrp(self)
      TestHelper.matrix_required(vrp)
      service_vrp = { vrp: vrp, service: :demo }

      services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp, nil, nil)
      assert services_vrps
      assert_equal services_vrps.size, 2
    end

    def test_work_day_without_vehicle_entity_small
      vrp = VRP.lat_lon_scheduling
      vrp[:vehicles].each{ |v|
        v[:sequence_timewindows] = []
      }
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal 1, generated_services_vrps.size

      vrp[:vehicles] << {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_mode: 'car',
        router_dimension: 'distance',
        sequence_timewindows: [{
          start: 0,
          end: 20,
          day_index: 0
        }, {
          start: 0,
          end: 20,
          day_index: 1
        }, {
          start: 0,
          end: 20,
          day_index: 2
        }, {
          start: 0,
          end: 20,
          day_index: 3
        }, {
          start: 0,
          end: 20,
          day_index: 4
        }]
      }
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal generated_services_vrps.size, 2
    end

    def test_work_day_without_vehicle_entity
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: :visits,
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: :visits,
        entity: 'work_day'
      }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal 10, generated_services_vrps.size

      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: :visits,
        entity: 'work_day'
      }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal 10, generated_services_vrps.size
    end

    def test_unavailable_days_taken_into_account_work_day
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      vrp[:preprocessing_kmeans_centroids] = [1, 2]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert only_monday_cluster != only_tuesday_cluster

      vrp[:preprocessing_kmeans_centroids] = [9, 10]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert only_monday_cluster != only_tuesday_cluster
    end

    def test_unavailable_days_taken_into_account_vehicle_work_day
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      vrp[:preprocessing_kmeans_centroids] = [0, 2]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert only_monday_cluster != only_tuesday_cluster

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      vrp[:preprocessing_kmeans_centroids] = [9, 10]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert only_monday_cluster != only_tuesday_cluster
    end

    def test_skills_taken_into_account
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]

      vrp[:services][0][:skills] = ['cold']
      vrp[:services][3][:skills] = ['hot']
      vrp[:preprocessing_kmeans_centroids] = [0, 2]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      cold_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      hot_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert cold_cluster != hot_cluster

      vrp[:services][0][:skills] = ['cold']
      vrp[:services][3][:skills] = ['hot']
      vrp[:preprocessing_kmeans_centroids] = [9, 10]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      cold_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      hot_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      assert cold_cluster != hot_cluster
    end

    def test_good_vehicle_assignment
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
      vrp[:preprocessing_kmeans_centroids] = [1, 2]
      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:vehicles].first[:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? }
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      only_monday_cluster = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      assert(only_monday_cluster[:vrp][:vehicles].any?{ |vehicle| vehicle[:sequence_timewindows].any?{ |tw| tw[:day_index].zero? } })
    end

    def test_good_vehicle_assignment_two_phases
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'vehicle'
      }, {
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
      vrp[:preprocessing_kmeans_centroids] = [9, 10]

      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal generated_services_vrps.collect{ |service| [service[:vrp][:vehicles].first[:id], service[:vrp][:vehicles].first[:global_day_index]] }.uniq.size, generated_services_vrps.size
    end

    def test_good_vehicle_assignment_skills
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
      vrp[:services].first[:skills] = ['skill']
      vrp[:vehicles][0][:skills] = [['skill']]
      vrp[:preprocessing_kmeans_centroids] = [1, 2]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      cluster_with_skill = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      assert(cluster_with_skill[:vrp][:vehicles].any?{ |v| v[:skills].include?(['skill']) })
    end

    def test_no_doubles_3000
      vrp = TestHelper.load_vrp(self)
      TestHelper.matrix_required(vrp)
      service_vrp = { vrp: vrp, service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      assert_equal generated_services_vrps.size, 15
      generated_services_vrps.each{ |service|
        vehicle_day = service[:vrp][:vehicles].first[:sequence_timewindows].first[:day_index]
        assert(service[:vrp][:services].all?{ |s| s[:activity][:timewindows].empty? || s[:activity][:timewindows].collect{ |tw| tw[:day_index] }.include?(vehicle_day) })
      }
    end

    def test_split_problem_based_on_skills
      vrp = VRP.basic
      vrp[:services][0][:skills] = ['skill_a', 'skill_c']
      vrp[:services][1][:skills] = ['skill_a', 'skill_c']
      vrp[:services][2][:skills] = ['skill_b']
      vrp[:services][3] = {
        id: 'service_4',
        skills: ['skill_b'],
        activity: {
          point_id: 'point_3'
        }
      }
      vrp[:vehicles][0] = {
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        skills: [['skill_a', 'skill_c']]
      }
      vrp[:vehicles][1] = {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        skills: [['skill_b']]
      }
      vrp[:vehicles][2] = {
        id: 'vehicle_2',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        skills: [['skill_b']]
      }

      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal result[:solvers].size, 2
      assert_equal result[:routes][0][:activities].collect{ |activity| activity[:service_id] }.compact, ['service_1', 'service_2']
      assert_equal result[:routes][1][:activities].collect{ |activity| activity[:service_id] }.compact, ['service_3', 'service_4']
    end

    def test_max_split_size
      vrp = VRP.lat_lon
      vrp[:vehicles][0][:router_dimension] = 'time'
      vrp[:vehicles][0][:timewindow] = {}
      vrp[:vehicles][1] = {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        router_dimension: 'time',
        timewindow: {}
      }
      vrp[:vehicles][2] = {
        id: 'vehicle_2',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        router_dimension: 'time',
        timewindow: {}
      }
      vrp[:configuration][:preprocessing][:max_split_size] = 2

      results = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)

      assert  results[:solvers].size >= 2
      results[:routes].each{ |route|
        assert route[:activities].collect{ |activity| activity[:service_id] }.compact.size <= 2
      }
    end

    def test_avoid_capacities_overlap
      vrp = TestHelper.load_vrp(self, fixture_file: 'results_regularity')
      vrp.vehicles.first.capacities.delete_if{ |cap| cap[:unit_id] == 'l' }
      vrp.vehicles = Interpreters::SplitClustering.list_vehicles(vrp.vehicles)
      vrp.schedule_range_indices = { start: 0, end: 13 }
      service_vrp = { vrp: vrp, service: :demo }
      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, cut_symbol: :duration, entity: 'work_day', restarts: @split_restarts)

      assert_equal 5, services_vrps.size
      kg_limit = services_vrps.collect{ |s_v| 2 * s_v[:vrp].vehicles.first.capacities.find{ |cap| cap[:unit_id] == 'kg' }[:limit] }
      qte_limit = services_vrps.collect{ |s_v| 2 * s_v[:vrp].vehicles.first.capacities.find{ |cap| cap[:unit_id] == 'qte' }[:limit] }

      assert services_vrps.collect{ |s_v| s_v[:vrp].services.collect{ |service|
        service.quantities.find{ |qty| qty[:unit_id] == 'kg' }[:value] * service[:visits_number] }.sum
      }.select.with_index{ |value, i| value > kg_limit[i] }.size <= 1

      assert services_vrps.collect{ |s_v| s_v[:vrp].services.collect{ |service|
        service.quantities.find{ |qty| qty[:unit_id] == 'qte' }[:value] * service[:visits_number] }.sum
      }.select.with_index{ |value, i| value > qte_limit[i] }.size <= 1
    end

    def test_fail_when_alternative_skills
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: 'work_day'
      }]
      vrp[:services].first[:skills] = ['skill']
      vrp[:vehicles][0][:skills] = [['skill'],['other_skill']]
      vrp[:preprocessing_kmeans_centroids] = [1, 2]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }

      begin
        Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
      rescue StandardError => e
        assert e.is_a?(OptimizerWrapper::UnsupportedProblemError)
      end
    end

    def test_max_split_size_with_empty_fill
      vrp = VRP.lat_lon
      vrp[:units] = [{
        id: 'unit_0',
      }]
      vrp[:configuration][:preprocessing][:max_split_size] = 3
      vrp[:services].first[:quantities] = [{
        unit_id: 'unit_0',
        value: 8,
        fill: true
      }]
      vrp[:vehicles][0][:timewindow] = {
        start: 36000,
        end: 900000
      }
      vrp[:vehicles][1] = {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_dimension: 'distance',
        timewindow: {
          start: 36000,
          end: 900000
        }
      }
      vrp[:name] = 'max_split_size_with_empty_fill'

      problem = TestHelper.create(vrp)
      check_vrp_services_size = problem.services.size
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, problem, nil)
      assert_equal problem.services.size, result[:unassigned].map{ |s| s[:service_id] }.compact.size + result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size
      assert_equal problem.services.size, check_vrp_services_size
    end

    def test_max_split_poorly_populated_route_limit_result
      vrp = TestHelper.load_vrp(self, fixture_file: 'max_split_functionality')
      result = Marshal.load(Base64.decode64(File.read('test/fixtures/max_split_poorly_populated_route_limit_result.dump')))
      Interpreters::SplitClustering.remove_poor_routes(vrp, result)

      assert_equal result[:unassigned], [], "remove_poor_routes shouldn't remove too many services"
    end

    def test_max_split_functionality
      vrp = TestHelper.load_vrp(self)
      TestHelper.matrix_required(vrp)

      Interpreters::Dichotomious.stub(:dichotomious_candidate?, ->(_service_vrp){ return false }) do # stub dicho so that it doesn't pass trough it
        result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)

        assert_equal result[:unassigned], [], 'There should be no unassigned services.'
        assert result[:routes].size <= 7, "There shouldn't be more than 7 routes -- it is #{result[:routes].size}"
        return
      end
    end

    def test_ignore_debug_parameter_if_no_coordinates
      vrp = TestHelper.load_vrp(self)

      begin
        OptimizerWrapper.config[:debug][:output_clusters] = true

        # barely checks that function does not produce an error
        Interpreters::SplitClustering.split_clusters([{ vrp: vrp }])
      ensure
        OptimizerWrapper.config[:debug][:output_clusters] == false
      end
    end

    def test_results_regularity
      visits_unassigned = []
      services_unassigned = []
      reason_unassigned = []
      vrp = Marshal.dump(TestHelper.load_vrp(self)) # call load_vrp only once to not to dump for each restart
      (1..@regularity_restarts).each{ |trial|
        puts "Regularity trial: #{trial}/#{@regularity_restarts}"
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(vrp), nil)
        visits_unassigned << result[:unassigned].size
        services_unassigned << result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }.uniq.size
        reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.map{ |k, v| [k, v.length] }.to_h
      }

      if services_unassigned.max - services_unassigned.min.to_f >= 2 || visits_unassigned.max >= 5
        reason_unassigned.each_with_index{ |reason, index|
          puts "unassigned visits ##{index} reason:\n#{reason}"
        }
        puts "unassigned services #{services_unassigned}"
        puts "unassigned visits   #{visits_unassigned}"
      end

      # visits_unassigned:
      assert visits_unassigned.max - visits_unassigned.min <= 2, "unassigned services (#{visits_unassigned}) should be more regular" # easier to achieve
      assert visits_unassigned.max <= 2, "More than 2 unassigned visits shouldn't happen (#{visits_unassigned})"

      # 2 shouldn't happen more than once unless the test is repeated more than 100s of times.
      rate_limit_2_unassigned = (@regularity_restarts * 0.01).ceil
      assert visits_unassigned.count(2) <= rate_limit_2_unassigned, "2 unassigned visits shouldn't appear more than #{rate_limit_2_unassigned} times (#{visits_unassigned})"
    end

    def test_balanced_split_under_nonuniform_sq_timewindows
      # Regression test against a fixed bug in clustering skill/day implemetation
      # which leads to all (!) services with non-uniform sequence_timewindows being
      # assigned to the vehicles with non-uniform sequence_timewindows.
      vrp = TestHelper.load_vrp(self)

      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans({ vrp: vrp, service: :demo }, vrp.vehicles.size, cut_symbol: :duration, entity: 'vehicle', restarts: 1)

      assert (services_vrps[1][:vrp][:services].size - services_vrps[0][:vrp][:services].size).abs.to_f / vrp.services.size < 0.93, 'Split should be more balanced. Possible regression in day/skill management in clustering -- when services and vehicles have non-uniform timewindows.'
    end

    def test_results_regularity_2
      visits_unassigned = []
      services_unassigned = []
      reason_unassigned = []
      vrp = Marshal.dump(TestHelper.load_vrp(self)) # call load_vrp only once to not to dump for each restart
      (1..@regularity_restarts).each{ |trial|
        puts "Regularity trial: #{trial}/#{@regularity_restarts}"
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(vrp), nil)
        visits_unassigned << result[:unassigned].size
        services_unassigned << result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }.uniq.size
        reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.map{ |k, v| [k, v.length] }.to_h
      }

      if services_unassigned.max - services_unassigned.min.to_f >= 10 || visits_unassigned.max >= 15
        reason_unassigned.each_with_index{ |reason, index|
          puts "unassigned visits ##{index} reason:\n#{reason}"
        }
        puts "unassigned services #{services_unassigned.sort}"
        puts "unassigned visits   #{visits_unassigned.sort}"
      end

      # visits_unassigned:
      # TODO:  Current range for number of unassigned visits is [3-23]
      # with mean 10.54, median 10 and std dev 3.25.
      # The limits are calculated so that the test passes 80% of the time
      # both under intensive and non-intensive versions. Note that @regularity_restarts depends on ENV['INTENSIVE_TEST'].
      # However, the goal of the test is decrease the limit_range, limit_max and range_max values
      # to more acceptable levels -- e.g., 8, 12, and 18
      range_max = 23
      assert visits_unassigned.max <= range_max, "More than #{range_max} unassigned visits should never happen." # easy to achieve. If this is violated there probably is a degredation.

      limit_range = ENV['INTENSIVE_TEST'] ? 15 : 11
      assert visits_unassigned.max - visits_unassigned.min <= limit_range, "unassigned visits (#{visits_unassigned}) should be more regular (max - min <= #{limit_range})" # This check might fail once every 4 - 5 runs.

      limit_max = ENV['INTENSIVE_TEST'] ? 19 : 16
      assert visits_unassigned.max <= limit_max, "More than #{limit_max} unassigned visits shouldn't happen (#{visits_unassigned}) regularly --  i.e., it might happen once every 4-5 runs."
    end

    def test_basic_split
      problem = VRP.lat_lon
      problem[:configuration][:preprocessing][:max_split_size] = 2
      problem[:vehicles] << {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_dimension: 'distance',
      }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(problem), nil)
      assert result
    end
  end
end
