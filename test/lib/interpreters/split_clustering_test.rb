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
  def test_cluster_dichotomious
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    while service_vrp[:vrp].services.size > 100
      services_vrps_dicho = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 2, :duration, 'vehicle')
      assert_equal 2, services_vrps_dicho.size

      # TODO: with rate_balance != 0 there is risk to get services to same lat/lng in different clusters
      # locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.first.data_items.map{ |d| [d[0], d[1]] }
      # locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.second.data_items.map{ |d| [d[0], d[1]] }
      # (locations_one & locations_two).each{ |loc|
      #   point_id_first = services_vrps_dicho.first[:vrp].points.find{ |p| p.location.lat == loc[0] && p.location.lon == loc[1] }.id
      #   puts "service from #{point_id_first} in cluster #0" + services_vrps_dicho.first[:vrp].services.select{ |s| s.activity.point_id == point_id_first }.to_s
      #   point_id_second = services_vrps_dicho.second[:vrp].points.find{ |p| p.location.lat == loc[0] && p.location.lon == loc[1] }.id
      #   puts "service from #{point_id_second} in cluster #1" + services_vrps_dicho.second[:vrp].services.select{ |s| s.activity.point_id == point_id_second }.to_s
      # }
      # assert_equal 0, (locations_one & locations_two).size

      durations = []
      services_vrps_dicho.each{ |service_vrp_dicho|
        durations << service_vrp_dicho[:vrp].services_duration
      }
      assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i

      average_duration = durations.inject(0, :+) / durations.size
      # Clusters should be very well balanced
      min_duration = average_duration - 0.1 * average_duration
      max_duration = average_duration + 0.1 * average_duration
      durations.each_with_index{ |duration, index|
        assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
      }

      service_vrp = services_vrps_dicho.first
    end
  end

  def test_cluster_dichotomious_heuristic
    vrp = FCT.load_vrp(self, fixture_file: 'cluster_dichotomious.json')
    service_vrp = {vrp: vrp, service: :demo, level: 0}
    while service_vrp[:vrp].services.size > 100
      services_vrps_dicho = Interpreters::Dichotomious.split(service_vrp)
      assert_equal 2, services_vrps_dicho.size

      locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.first.data_items.map{ |d| [d[0], d[1]] }
      locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.second.data_items.map{ |d| [d[0], d[1]] }
      assert_equal 0, (locations_one & locations_two).size

      durations = []
      services_vrps_dicho.each{ |service_vrp_dicho|
        durations << service_vrp_dicho[:vrp].services_duration
      }
      assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i
      assert durations[0] >= durations[1]

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

  def test_cluster_one_phase_work_day
    vrp = FCT.load_vrp(self, fixture_file: 'cluster_one_phase.json')
    service_vrp = {vrp: vrp, service: :demo}
    services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 80, :duration, 'work_day')
    assert_equal 80, services_vrps_days.size

    durations = []
    services_vrps_days.each{ |service_vrp_day|
      durations << service_vrp_day[:vrp].services_duration
    }

    average_duration = durations.inject(0, :+) / durations.size
    min_duration = average_duration - 0.5 * average_duration
    max_duration = average_duration + 0.5 * average_duration
    o = durations.map.with_index{ |duration, index|
      # assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
      duration < max_duration && duration > min_duration
    }
    assert o.select{ |i| i }.size > 0.9 * o.size
  end

  def test_cluster_one_phase_vehicle
    vrp = FCT.load_vrp(self, fixture_file: 'cluster_one_phase.json')
    service_vrp = { vrp: vrp, service: :demo }

    total_durations = vrp.services_duration
    services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, :duration, 'vehicle')
    assert_equal 5, services_vrps_days.size

    durations = []
    services_vrps_days.each{ |service_vrp_vehicle|
      durations << service_vrp[:vrp].services_duration
    }
    # First balanced duration should be the smallest according vehicle data
    assert 0, durations.index(durations.min)

    cluster_weight_sum = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.sum
    minimum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.min
    maximum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.max
    durations.each_with_index{ |duration, index|
      # assert duration < (maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be less than #{(maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum}"
      assert duration > (minimum_sequence_timewindows - 1) * total_durations / cluster_weight_sum, "Duration ##{index} (#{duration}) should be more than #{(minimum_sequence_timewindows - 1) * total_durations / cluster_weight_sum}"
    }
  end

  def test_cluster_two_phases
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 16, :duration, 'vehicle')
    assert_equal 16, services_vrps_vehicles.size

    durations = []
    services_vrps_vehicles.each{ |service_vrp_vehicle|
      durations << service_vrp_vehicle[:vrp].services_duration
    }
    average_duration = durations.inject(0, :+) / durations.size
    min_duration = average_duration - 0.5 * average_duration
    max_duration = average_duration + 0.5 * average_duration
    durations.each_with_index{ |duration, index|
      assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
    }

    services_vrps_days = services_vrps_vehicles.each{ |services_vrps|
      durations = []
      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(services_vrps, 5, :duration, 'work_day')
      assert_equal 5, services_vrps.size
      services_vrps.each{ |service_vrp|
        next if service_vrp[:vrp].points.size < 10 # FIXME When number of services is too small balanced duration is very random
        durations << service_vrp[:vrp].services_duration
      }
      next if durations.empty?
      average_duration = durations.inject(0, :+) / durations.size
      min_duration = average_duration - 0.7 * average_duration
      max_duration = average_duration + 0.7 * average_duration
      durations.each_with_index{ |duration, index|
        assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
      }
    }
  end

  def test_length_centroid
    vrp = Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/length_centroid.json').to_a.join)['vrp']))

    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
  end

  def test_work_day_without_vehicle_entity_small
    vrp = VRP.lat_lon_scheduling
    vrp[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'vehicle'
    }]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal generated_services_vrps.size, 2
  end

  def test_work_day_without_vehicle_entity
    skip "This test fails. The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: 10 clusters generated both vehicle+work_day and just with work_day."
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
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal 9, generated_services_vrps.size

    vrp[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'work_day'
    }]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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

    vrp[:services][0][:activity][:timewindows] = [{start: 0, end: 10, day_index: 0}]
    vrp[:services][3][:activity][:timewindows] = [{start: 0, end: 10, day_index: 1}]
    vrp[:preprocessing_kmeans_centroids] = [1, 2]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
    only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
    assert only_monday_cluster != only_tuesday_cluster

    vrp[:preprocessing_kmeans_centroids] = [9, 10]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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

    vrp[:services][0][:activity][:timewindows] = [{start: 0, end: 10, day_index: 0}]
    vrp[:services][3][:activity][:timewindows] = [{start: 0, end: 10, day_index: 1}]
    vrp[:preprocessing_kmeans_centroids] = [0, 2]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    only_monday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
    only_tuesday_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
    assert only_monday_cluster != only_tuesday_cluster

    vrp[:services][0][:activity][:timewindows] = [{start: 0, end: 10, day_index: 0}]
    vrp[:services][3][:activity][:timewindows] = [{start: 0, end: 10, day_index: 1}]
    vrp[:preprocessing_kmeans_centroids] = [9, 10]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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

    vrp[:services][0][:activity][:skills] = ['cold']
    vrp[:services][3][:activity][:skills] = ['hot']
    vrp[:preprocessing_kmeans_centroids] = [0, 2]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    cold_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
    hot_cluster = generated_services_vrps.find_index{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][3][:id] } }
    assert cold_cluster != hot_cluster

    vrp[:services][0][:activity][:skills] = ['cold']
    vrp[:services][3][:activity][:skills] = ['hot']
    vrp[:preprocessing_kmeans_centroids] = [9, 10]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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
      entity: 'vehicles'
    }]
    vrp[:preprocessing_kmeans_centroids] = [1, 2]
    vrp[:services][0][:activity][:timewindows] = [{start: 0, end: 10, day_index: 0}]
    vrp[:vehicles].first[:sequence_timewindows].delete_if{ |tw| tw[:day_index].zero? }
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    only_monday_cluster = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
    assert only_monday_cluster[:vrp][:vehicles].any?{ |vehicle| vehicle[:sequence_timewindows].any?{ |tw| tw[:day_index] == 0 } }
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

    service_vrp = {vrp: FCT.create(vrp), service: :demo}
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
    vrp[:vehicles][0][:skills] = ['skill']
    vrp[:preprocessing_kmeans_centroids] = [1, 2]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    cluster_with_skill = generated_services_vrps.find{ |sub_vrp| sub_vrp[:vrp][:services].any?{ |s| s[:id] == vrp[:services][0][:id] } }
    assert cluster_with_skill[:vrp][:vehicles].any?{ |v| v[:skills].include?('skill') }
  end

  def test_no_doubles_3000
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal generated_services_vrps.size, 15
    generated_services_vrps.each{ |service|
      vehicle_day = service[:vrp][:vehicles].first[:sequence_timewindows].first[:day_index]
      assert service[:vrp][:services].all?{ |s| s[:activity][:timewindows].empty? || s[:activity][:timewindows].collect{ |tw| tw[:day_index] }.include?(vehicle_day) }
    }
  end

  def test_Mai17_AG10_12VL 
    # do not keep this test, too long
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal generated_services_vrps.size, 100
    (0..99).each{ |index|
      vrp = generated_services_vrps[index][:vrp]
      if vrp[:vehicles].first[:sequence_timewindows].first[:day_index] == 0
        assert vrp[:services].all?{ |s| s[:activity][:timewindows].empty? || s[:activity][:timewindows].collect{ |tw| tw[:day_index] }.include?(0) }
      end
      if vrp[:vehicles].first[:sequence_timewindows].first[:day_index] == 1
        assert vrp[:services].all?{ |s| s[:activity][:timewindows].empty? || s[:activity][:timewindows].collect{ |tw| tw[:day_index] }.include?(1) }
      end
      if vrp[:vehicles].first[:sequence_timewindows].first[:day_index] == 2
        assert vrp[:services].all?{ |s| s[:activity][:timewindows].empty? || s[:activity][:timewindows].collect{ |tw| tw[:day_index] }.include?(2) }
      end
    }
  end
end
