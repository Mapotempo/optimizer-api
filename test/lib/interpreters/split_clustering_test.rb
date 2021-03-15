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

    def test_same_location_different_clusters
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_dichotomious')
      service_vrp = { vrp: vrp, service: :demo }
      vrp.services.each{ |s| s.skills = [] } # The instance has old "Pas X" style day skills, we purposely ignore them otherwise balance is not possible
      while service_vrp[:vrp].services.size > 100
        total = Hash.new(0)
        service_vrp[:vrp].services.each{ |s| s.quantities.each{ |q| total[q.unit.id] += q.value } }
        service_vrp[:vrp].vehicles.each{ |v|
          v.capacities = []
          service_vrp[:vrp].units.each{ |u|
            v.capacities << Models::Capacity.new(unit: u, limit: total[u.id] * 0.65)
          }
        }

        # entity: `vehicle` setting only works if the number of clusters is equal to the number of vehicles.
        original = service_vrp[:vrp].vehicles.first
        service_vrp[:vrp].vehicles = [original]
        service_vrp[:vrp].vehicles << Models::Vehicle.new(
          id: "#{original.id}_copy",
          duration: original.duration,
          matrix_id: original.matrix_id,
          skills: original.skills,
          timewindow: original.timewindow,
          start_point: original.start_point,
          end_point: original.end_point,
          capacities: original.capacities
        )

        services_vrps_dicho = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 2, cut_symbol: :duration, entity: :vehicle, restarts: @split_restarts)

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
      services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 80, cut_symbol: :duration, entity: :work_day, restarts: @split_restarts)
      assert_equal 80, services_vrps_days.size

      durations = []
      services_vrps_days.each{ |service_vrp_day|
        durations << service_vrp_day[:vrp].services_duration
      }

      average_duration = durations.sum / durations.size
      min_duration = average_duration - 0.5 * average_duration
      max_duration = average_duration + 0.5 * average_duration
      o = durations.map{ |duration|
        # assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
        duration < max_duration && duration > min_duration
      }
      assert o.count{ |i| i } > 0.9 * o.size, "Cluster durations are not balanced: #{durations.inspect}" # TODO: All clusters should be balanced -- i.e., not just 90% of them
    end

    def test_cluster_one_phase_vehicle
      vrp = TestHelper.load_vrp(self, fixture_file: 'cluster_one_phase')

      service_vrp = { vrp: vrp, service: :demo }

      total_durations = vrp.services_duration
      services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, cut_symbol: :duration, entity: :vehicle, restarts: @split_restarts)
      assert_equal 5, services_vrps_vehicles.size

      durations = []
      services_vrps_vehicles.each{ |service_vrp_vehicle|
        durations << service_vrp_vehicle[:vrp].services_duration
      }
      # First balanced duration should be the smallest according vehicle data
      assert 0, durations.index(durations.min)

      cluster_weight_sum = vrp.vehicles.sum{ |vehicle| vehicle.sequence_timewindows.size }
      minimum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.min
      # maximum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.max
      durations.each_with_index{ |duration, index|
        # assert duration < (maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be less than #{(maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum}"
        assert duration > (minimum_sequence_timewindows - 1.1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be more than #{((minimum_sequence_timewindows - 1.1) * total_durations / cluster_weight_sum).round(1)}"
      }
    end

    def test_if_duration_from_and_to_depot_is_filled_correctly
      problem = VRP.lat_lon
      problem[:matrices] = []
      problem[:points].each{ |p| p.delete(:matrix_index) }
      problem[:vehicles][0].delete(:matrix_id)
      problem[:vehicles] << problem[:vehicles].first.dup
      problem[:vehicles].last[:id] += '_dup'

      OptimizerWrapper.router.stub(:matrix, ->(_url, _router_mode, _router_dimension, src, dst){ return [Array.new(src.size){ |i| Array.new(dst.size){ (i + 1) * 100 } }] }) do
        mock = MiniTest::Mock.new
        mock.expect(:call, nil, [])
        Interpreters::SplitClustering.stub(:add_duration_from_and_to_depot, lambda{ |vrp, data_items|
          mock.call
          Interpreters::SplitClustering.send(:__minitest_stub__add_duration_from_and_to_depot, vrp, data_items)
        }) do
          assert Interpreters::SplitClustering.split_balanced_kmeans({ vrp: TestHelper.create(problem), service: :demo }, problem[:vehicles].size, cut_symbol: :duration, entity: :vehicle, restarts: 1)
        end
        mock.verify # check if it is called

        data_items, _cumulated_metrics, _linked_objects = Interpreters::SplitClustering.send(:collect_data_items_metrics, TestHelper.create(problem), Hash.new(0), { basic_split: false, group_points: true})
        assert_equal [200.0, 300.0, 400.0, 500.0], (data_items.flat_map{ |d_i| d_i[4][:duration_from_and_to_depot].uniq }) # check the values are correct
      end
    end

    def test_cluster_two_phases
      vrp = TestHelper.load_vrp(self)

      service_vrp = { vrp: vrp, service: :demo }
      services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 16, cut_symbol: :duration, entity: :vehicle, restarts: @split_restarts)
      assert_equal 16, services_vrps_vehicles.size

      durations = []
      services_vrps_vehicles.each{ |service_vrp_vehicle|
        durations << service_vrp_vehicle[:vrp].services_duration
      }
      average_duration = durations.sum / durations.size
      min_duration = average_duration - 0.5 * average_duration
      max_duration = average_duration + 0.5 * average_duration

      durations.each_with_index{ |duration, index|
        assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration.round(2)}) should be between #{min_duration.round(2)} and #{max_duration.round(2)}. All durations #{durations.inspect}"
      }

      overall_min_duration = average_duration
      overall_max_duration = 0.0

      services_vrps_vehicles.each{ |services_vrps|
        durations = []
        vehicle_dump = Marshal.dump(services_vrps[:vrp][:vehicles].first)
        vehicles = (0..4).collect{ |v_i|
          vehicle = Marshal.load(vehicle_dump) # rubocop: disable Security/MarshalLoad
          vehicle[:sequence_timewindows] = [vehicle[:sequence_timewindows][v_i]]
          vehicle
        }
        services_vrps[:vrp][:vehicles] = vehicles
        services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(services_vrps, 5, cut_symbol: :duration, entity: :work_day, restarts: @split_restarts)
        assert_equal 5, services_vrps.size
        services_vrps.each{ |service_vrp_day|
          next if service_vrp_day[:vrp].points.size < 10

          durations << service_vrp_day[:vrp].services_duration
        }
        next if durations.empty?

        average_duration = durations.sum / durations.size
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

      services_vrps = Interpreters::SplitClustering.generate_split_vrps({ vrp: vrp, service: :demo }, nil, nil)
      assert services_vrps
      assert_equal 2, services_vrps.size
    end

    def test_work_day_without_vehicle_entity_small
      vrp = VRP.lat_lon_scheduling
      vrp[:vehicles].each{ |v|
        v[:sequence_timewindows] = []
      }
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :vehicle
      }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      assert_equal 1, generated_services_vrps.size

      vrp[:vehicles] << {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_mode: 'car',
        router_dimension: 'distance',
        sequence_timewindows: [
          { start: 0, end: 20, day_index: 0 },
          { start: 0, end: 20, day_index: 1 },
          { start: 0, end: 20, day_index: 2 },
          { start: 0, end: 20, day_index: 3 },
          { start: 0, end: 20, day_index: 4 }
        ]
      }
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      assert_equal 2, generated_services_vrps.size
    end

    def test_work_day_without_vehicle_entity
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      vrp[:configuration][:preprocessing][:partitions].each{ |partition|
        partition[:metric] = :visits
      }
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      # 2 vehicles available from monday to friday
      # but schedule from monday to thursday : 4 days
      assert_equal 8, generated_services_vrps.size

      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: :visits,
        entity: :work_day
      }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      assert_equal 8, generated_services_vrps.size
    end

    def test_unavailable_days_taken_into_account_work_day
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :work_day
      }]

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [1, 2]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      refute_equal only_monday_cluster, only_tuesday_cluster

      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [9, 10]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      refute_equal only_monday_cluster, only_tuesday_cluster
    end

    def test_unavailable_days_taken_into_account_vehicle_work_day
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [0, 2]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      refute_equal only_monday_cluster, only_tuesday_cluster

      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:services][3][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 1 }]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [9, 10]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
      refute_equal only_monday_cluster, only_tuesday_cluster
    end

    def test_skills_taken_into_account
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions

      vrp[:vehicles][0][:skills] = [['hot']]
      vrp[:vehicles][1][:skills] = [['cold']]

      vrp[:services][0][:skills] = ['cold']
      vrp[:services][1][:skills] = ['hot']

      # even though they are at the same lat/lon, they should be in different clusters
      vrp[:points][1][:location] = vrp[:points][0][:location]
      vrp[:points][1][:matrix_index] = vrp[:points][0][:matrix_index]

      assert_raises ArgumentError do # initialising centroids with incompatible services should raise an error
        vrp[:configuration][:preprocessing][:kmeans_centroids] = [0, 1]
        Interpreters::SplitClustering.generate_split_vrps(vrp: TestHelper.create(vrp), service: :demo)
      end

      vrp[:configuration][:preprocessing][:kmeans_centroids] = [2, 3] # initialising the with other services should be okay
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(vrp: TestHelper.create(vrp), service: :demo)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!

      # but service 1 and 0 should be served by different vehicles
      cold_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      hot_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][1][:id] } }
      refute_equal cold_cluster, hot_cluster
    end

    def test_good_vehicle_assignment
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :work_day
      }]
      vrp[:services][0][:activity][:timewindows] = [{ start: 0, end: 10, day_index: 0 }]
      vrp[:vehicles].first[:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? }
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [1, 2]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      only_monday_cluster = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      assert(only_monday_cluster[:vrp].vehicles.any?{ |vehicle| vehicle.timewindow.day_index.zero? })
    end

    def test_good_vehicle_assignment_two_phases
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions

      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [9, 10]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      # Each generated_services_vrps should have a different vehicle :
      assert_nil generated_services_vrps.collect{ |service| [service[:vrp].vehicles.first.id, service[:vrp].vehicles.first.timewindow] }.uniq!, 'Each generated_services_vrps should have a different vehicle'
    end

    def test_good_vehicle_assignment_skills
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :work_day
      }]
      vrp[:services].first[:skills] = ['skill']
      vrp[:vehicles][0][:skills] = [['skill']]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [1, 2]
      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(service_vrp)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      cluster_with_skill = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
      assert(cluster_with_skill[:vrp].vehicles.any?{ |v| v.skills.any?{ |skill_set| skill_set.include?('skill') } })
    end

    def test_no_doubles_3000
      vrp = TestHelper.load_vrp(self)

      generated_services_vrps = Interpreters::SplitClustering.generate_split_vrps(vrp: vrp, service: :demo)
      generated_services_vrps.flatten!
      generated_services_vrps.compact!
      assert_equal 15, generated_services_vrps.size
      generated_services_vrps.each{ |service|
        vehicle_day = service[:vrp].vehicles.first.timewindow.day_index
        services_timewindows_day_index = service[:vrp].services.collect{ |s| s.activity.timewindows.collect(&:day_index) }
        assert(services_timewindows_day_index.all?{ |days_set| days_set.empty? || days_set.include?(vehicle_day) })
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
      assert_equal 2, result[:solvers].size
      assert_equal([nil, 'service_1', 'service_2'], result[:routes][0][:activities].collect{ |activity| activity[:service_id] })
      assert_equal([nil, 'service_3', 'service_4'], result[:routes][1][:activities].collect{ |activity| activity[:service_id] })
    end

    def test_correct_number_of_visits_when_concurrent_split_independent_and_max_split
      # A small instance that is split_independent by skills
      # and then max_split again during solution process
      # should not raise "Wrong number of visits returned in result" error
      vrp = VRP.independent_skills
      vrp[:points] = VRP.lat_lon_scheduling[:points]
      vrp[:services].first[:skills] = ['D']
      vrp[:configuration][:preprocessing] = {
        max_split_size: 4
      }

      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
    end

    def test_avoid_capacities_overlap
      vrp = TestHelper.load_vrp(self, fixture_file: 'results_regularity')
      vrp.vehicles.first.capacities.delete_if{ |cap| cap[:unit_id] == 'l' }
      vrp.schedule_range_indices = { start: 0, end: 13 }
      vrp.vehicles = Interpreters::SplitClustering.list_vehicles(vrp.schedule_range_indices, vrp.vehicles, :work_day)

      service_vrp = { vrp: vrp, service: :demo }
      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, cut_symbol: :duration, entity: :work_day, restarts: @split_restarts)

      assert_equal 5, services_vrps.size

      %w[kg qte].each{ |unit|
        assert_operator services_vrps.count{ |s_v|
          limit = 2 * s_v[:vrp].vehicles.first.capacities.find{ |cap| cap[:unit_id] == unit }[:limit]
          s_v[:vrp].services.sum{ |service| service.quantities.find{ |qty| qty[:unit_id] == unit }[:value] * service[:visits_number] } > limit
        }, :<=, 1
      }
    end

    def test_fail_when_alternative_skills
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :work_day
      }]
      vrp[:services].first[:skills] = ['skill']
      vrp[:vehicles][0][:skills] = [['skill'], ['other_skill']]
      service_vrp = { vrp: TestHelper.create(vrp), service: :demo }
      service_vrp[:vrp][:preprocessing_kmeans_centroids] = [1, 2]

      assert_raises OptimizerWrapper::UnsupportedProblemError do
        Interpreters::SplitClustering.generate_split_vrps(service_vrp)
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
      assert_equal check_vrp_services_size, problem.services.size
      assert_equal problem.services.size, result[:unassigned].count{ |s| s[:service_id] } + result[:routes].sum{ |r| r[:activities].count{ |a| a[:service_id] } }
    end

    def test_max_split_poorly_populated_route_limit_result
      vrp = TestHelper.load_vrp(self, fixture_file: 'max_split_functionality')
      result = Marshal.load(File.binread('test/fixtures/max_split_poorly_populated_route_limit_result.bindump')) # rubocop: disable Security/MarshalLoad
      Interpreters::SplitClustering.remove_poor_routes(vrp, result)

      assert_equal 0, result[:unassigned].size, 'remove_poor_routes should not remove any services from this result'
    end

    def test_max_split_functionality
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_duration = 120000

      Interpreters::Dichotomious.stub(:dichotomious_candidate?, ->(_service_vrp){ return false }) do # stub dicho so that it doesn't pass trough it
        result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, vrp, nil)

        assert result[:routes].size <= 7, "There shouldn't be more than 7 routes -- it is #{result[:routes].size}"
        assert_equal [], result[:unassigned], 'There should be no unassigned services.'
        return
      end
    end

    def test_max_split_respects_initial_solutions
      problem = VRP.lat_lon
      problem[:vehicles] << problem[:vehicles].first.dup
      problem[:vehicles].last[:id] = 'vehicle_1'
      problem[:routes] = [
        # (1, 2) and (4, 5) are at the same locations without initial routes, they would be in the same vehicles
        # we are forcing them apart with initial routes and check if they stay as such after the split
        { vehicle_id: 'vehicle_0', mission_ids: [1, 4].map{ |s| "service_#{s}" } },
        { vehicle_id: 'vehicle_1', mission_ids: [2, 5].map{ |s| "service_#{s}" } }
      ]
      problem[:configuration][:preprocessing][:max_split_size] = 1

      called = false
      Interpreters::SplitClustering.stub(:split_solve_core, lambda{ |service_vrp, _job|
        split = service_vrp[:split_solve_data][:service_vehicle_assignments].transform_values!{ |v| v.collect(&:id) }
        [1, 4].each{ |s| assert_includes split['vehicle_0'], "service_#{s}", "service_#{s} should stay on vehicle_0" }
        [2, 5].each{ |s| assert_includes split['vehicle_1'], "service_#{s}", "service_#{s} should stay on vehicle_1" }
        called = true
        return
      }) do
        vrp = TestHelper.create(problem)
        Interpreters::SplitClustering.split_solve({ service: :ortools, vrp: vrp, dicho_level: 0 })
      end
      assert called, 'split_solve_core should have been called'
    end

    def test_max_split_can_handle_empty_vehicles # fail
      # Due to initial solutions, 4 services are on 2 vehicles which leaves 2 services to the remaining 3 vehicles.
      problem = VRP.lat_lon
      (1..4).each{ |i|
        problem[:vehicles] << problem[:vehicles].first.dup
        problem[:vehicles].last[:id] = "vehicle_#{i}"
      }
      problem[:routes] = [
        { vehicle_id: 'vehicle_0', mission_ids: [1, 4].map{ |s| "service_#{s}" } },
        { vehicle_id: 'vehicle_1', mission_ids: [2, 5].map{ |s| "service_#{s}" } }
      ]
      problem[:configuration][:preprocessing][:max_split_size] = 1

      called = false
      Interpreters::SplitClustering.stub(:split_solve_core, lambda{ |service_vrp, _job|
        refute_nil service_vrp[:split_level], 'split_level should have been defined before split_solve_core'
        assert_operator service_vrp[:split_level], :<, 3, "split_level shouldn't reach 3. Grouping of vehicle points might be the reason"
        assert service_vrp[:split_solve_data][:representative_vrp].points.none?{ |p| p.location.lat.nan? }, "Empty vehicles shouldn't reach split_solve_core"
        called = true
        Interpreters::SplitClustering.send(:__minitest_stub__split_solve_core, service_vrp) # call original function
      }) do
        OptimizerWrapper.stub(:solve, lambda{ |service_vrp, _job, _block| # stub with empty solution
          vrp = service_vrp[:vrp]
          service = service_vrp[:service]
          OptimizerWrapper.config[:services][service].detect_unfeasible_services(vrp)
          OptimizerWrapper.config[:services][service].empty_result(service.to_s, vrp)
        }) do
          vrp = TestHelper.create(problem)
          Interpreters::SplitClustering.split_solve({ service: :ortools, vrp: vrp, dicho_level: 0 })
        end
      end
      assert called, 'split_solve_core should have been called'
    end

    def test_ignore_debug_parameter_if_no_coordinates
      vrp = TestHelper.load_vrp(self)
      tmp_output_clusters = OptimizerWrapper.config[:debug][:output_clusters]
      OptimizerWrapper.config[:debug][:output_clusters] = true

      # just checks that function does not produce an error
      Interpreters::SplitClustering.generate_split_vrps(vrp: vrp)
    ensure
      OptimizerWrapper.config[:debug][:output_clusters] = tmp_output_clusters
    end

    def test_results_regularity
      visits_unassigned = []
      services_unassigned = []
      reason_unassigned = []
      vrp = Marshal.dump(TestHelper.load_vrp(self)) # call load_vrp only once to not to dump for each restart
      (1..@regularity_restarts).each{ |trial|
        puts "Regularity trial: #{trial}/#{@regularity_restarts}"
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(vrp), nil) # rubocop: disable Security/MarshalLoad
        visits_unassigned << result[:unassigned].size
        unassigned_service_ids = result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }
        unassigned_service_ids.uniq!
        services_unassigned << unassigned_service_ids.size
        reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.transform_values(&:length)
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

      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans({ vrp: vrp, service: :demo }, vrp.vehicles.size, cut_symbol: :duration, entity: :vehicle, restarts: 1)

      assert (services_vrps[1][:vrp][:services].size - services_vrps[0][:vrp][:services].size).abs.to_f / vrp.services.size < 0.93, 'Split should be more balanced. Possible regression in day/skill management in clustering -- when services and vehicles have non-uniform timewindows.'
    end

    def test_results_regularity_2
      visits_unassigned = []
      services_unassigned = []
      reason_unassigned = []
      vrp = Marshal.dump(TestHelper.load_vrp(self)) # call load_vrp only once to not to dump for each restart
      (1..@regularity_restarts).each{ |trial|
        OptimizerLogger.log "Regularity trial: #{trial}/#{@regularity_restarts}"
        result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(vrp), nil) # rubocop: disable Security/MarshalLoad
        visits_unassigned << result[:unassigned].size
        unassigned_service_ids = result[:unassigned].collect{ |unassigned| unassigned[:original_service_id] }
        unassigned_service_ids.uniq!
        services_unassigned << unassigned_service_ids.size
        reason_unassigned << result[:unassigned].map{ |unass| unass[:reason].slice(0, 8) }.group_by{ |e| e }.transform_values(&:length)
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

    def test_basic_from_depots_shipments_split
      problem = VRP.lat_lon_pud
      problem[:configuration][:preprocessing][:max_split_size] = 4
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

    def test_scheduling_partitions_without_recurrence
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_baleares2')
      vrp.preprocessing_first_solution_strategy = nil

      vrp.preprocessing_partitions = [
        {
          method: 'balanced_kmeans',
          metric: 'duration',
          entity: 'work_day'
        }
      ]

      vrp.resolution_solver = true

      vrp.services.each{ |service|
        service.visits_number = 1
        service.minimum_lapse = nil
        service.maximum_lapse = nil
      }

      vrp.schedule_range_indices = {
        start: 0,
        end: 6
      }
      Interpreters::PeriodicVisits.stub_any_instance(:generate_routes, ->(_vrp){ raise 'Should not enter here' }) do
        result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
        assert result
      end
    end

    def test_clustering_with_sticky_vehicles # fail
      vrp = VRP.lat_lon_two_vehicles
      vrp[:services].find{ |s| s[:id] == 'service_1' }[:sticky_vehicle_ids] = ['vehicle_0']
      vrp[:services].find{ |s| s[:id] == 'service_5' }[:sticky_vehicle_ids] = ['vehicle_0']
      vrp[:services].find{ |s| s[:id] == 'service_12' }[:sticky_vehicle_ids] = ['vehicle_1']
      vrp[:configuration][:preprocessing] = {
        partitions: [{ method: 'balanced_kmeans', metric: 'duration', entity: :vehicle }]
      }
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, TestHelper.create(vrp), nil)
      assert_equal 2, (result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_0' }[:activities].collect{ |a| a[:service_id] } & ['service_1', 'service_5']).size
      assert_equal 1, (result[:routes].find{ |r| r[:vehicle_id] == 'vehicle_1' }[:activities].collect{ |a| a[:service_id] } & ['service_12']).size
    end

    def test_list_vehicles
      # with timewindow
      vrp = TestHelper.create(VRP.basic)
      vrp.vehicles.first.timewindow = Models::Timewindow.new(start: 0, end: 10)
      # one vehicle with no day index : we should generate one vehicle per week_day :
      assert_equal 7, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 6 }, vrp.vehicles, :work_day).size
      assert_equal 7, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 10 }, vrp.vehicles, :work_day).size
      assert_equal 7, Interpreters::SplitClustering.list_vehicles({ start: 1, end: 7 }, vrp.vehicles, :work_day).size
      # or one vehicle per day, if schedule is less than one week
      assert_equal 5, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 4 }, vrp.vehicles, :work_day).size

      vrp.vehicles.first.timewindow[:day_index] = 0
      # if vehicle is only available at one week day then we should generate one cluster only
      assert_equal 1, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 4 }, vrp.vehicles, :work_day).size

      # with sequence_timewindows
      vrp = TestHelper.create(VRP.basic)
      vrp.vehicles.first.sequence_timewindows = [
        Models::Timewindow.new(start: 0, end: 10),
        Models::Timewindow.new(start: 15, end: 35)
      ]
      # we generate one cluster per week day, for each vehicle sequence timewindow
      assert_equal 14, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 6 }, vrp.vehicles, :work_day).size
      # or one cluster per schedule day, for each vehicle sequence timewindow
      # if schedule is less than a week
      assert_equal 8, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 3 }, vrp.vehicles, :work_day).size

      vrp.vehicles.first.sequence_timewindows = [
        Models::Timewindow.new(start: 0, end: 10, day_index: 0),
        Models::Timewindow.new(start: 15, end: 35, day_index: 1)
      ]
      assert_equal 2, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 6 }, vrp.vehicles, :work_day).size
      assert_equal 1, Interpreters::SplitClustering.list_vehicles({ start: 1, end: 6 }, vrp.vehicles, :work_day).size

      vrp.vehicles.first.sequence_timewindows = [
        Models::Timewindow.new(start: 0, end: 10, day_index: 0),
        Models::Timewindow.new(start: 15, end: 35)
      ]
      assert_equal 8, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 6 }, vrp.vehicles, :work_day).size

      vrp.vehicles.first.sequence_timewindows = [
        Models::Timewindow.new(start: 0, end: 10, day_index: 0),
        Models::Timewindow.new(start: 15, end: 35, day_index: 0)
      ]
      assert_equal 2, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 7 }, vrp.vehicles, :work_day).size

      # with no timewindow
      vrp = TestHelper.create(VRP.basic)
      # if a vehicle has no timewindow it is similar to having a vehicle with one timewindow but not day_index
      # we generate one cluster per vehicle per week day
      assert_equal 7, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 6 }, vrp.vehicles, :work_day).size
      # if schedule is less than a week, we generate one cluster per vehicle per day
      assert_equal 5, Interpreters::SplitClustering.list_vehicles({ start: 0, end: 4 }, vrp.vehicles, :work_day).size
    end
  end
end
