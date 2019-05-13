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

  def test_cluster_one_phase_to_edit
    skip 'Require changes into the entity and into the duration calculation'
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 80, :duration, 'vehicle')
    assert_equal 80, services_vrps_days.size

    durations = []
    services_vrps_days.each{ |service_vrp_vehicle|
      # TODO: durations should be sum of setup_duration & duration
      durations << service_vrp_vehicle[:vrp].services.collect{ |service| service[:activity][:duration] * service[:visits_number] }.sum
    }

    average_duration = durations.inject(0, :+) / durations.size
    durations.each{ |duration|
      assert (duration < (average_duration + 1/2 * average_duration)) && duration > (average_duration - 1/2 * average_duration)
    }
  end

  def test_cluster_one_phase
    vrp = FCT.load_vrp(self)
    service_vrp = { vrp: vrp, service: :demo }

    total_durations = vrp.points.collect{ |point|
      vrp.services.select{ |service| service.activity.point.id == point.id }.map.with_index{ |service, i|
        service.visits_number * (service.activity.duration + (i.zero? ? service.activity.setup_duration : 0))
      }.sum
    }.sum
    services_vrps_days = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 5, :duration, 'vehicle')
    assert_equal 5, services_vrps_days.size

    durations = []
    services_vrps_days.each{ |service_vrp_vehicle|
      durations << service_vrp[:vrp].points.collect{ |point|
        service_vrp_vehicle[:vrp].services.select{ |service| service.activity.point.id == point.id }.map.with_index{ |service, i|
          service.visits_number * (service.activity.duration + (i.zero? ? service.activity.setup_duration : 0))
        }.sum
      }.sum
    }
    cluster_weight_sum = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.sum
    minimum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.min
    maximum_sequence_timewindows = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows.size }.max
    durations.each{ |duration|
      assert duration < (maximum_sequence_timewindows + 1) * total_durations / cluster_weight_sum
      assert duration > (minimum_sequence_timewindows - 1) * total_durations / cluster_weight_sum
    }
  end

  def test_cluster_two_phases
    skip "This test fails. The test is created for Test-Driven Development.
          The functionality is not ready yet, it is skipped for devs not working on the functionality.
          Expectation: split_balanced_kmeans creates demanded number of clusters."
    vrp = FCT.load_vrp(self)
    service_vrp = {vrp: vrp, service: :demo}
    services_vrps_vehicles = Interpreters::SplitClustering.split_balanced_kmeans(service_vrp, 16, :duration, 'vehicle')
    assert_equal 16, services_vrps_vehicles.size

    durations = []
    services_vrps_vehicles.each{ |service_vrp_vehicle|
      # TODO: durations should be sum of setup_duration & duration
      durations << service_vrp_vehicle[:vrp].services.collect{ |service| service[:activity][:duration] * service[:visits_number] }.sum
    }

    services_vrps_days = services_vrps_vehicles.each{ |services_vrps|
      durations = []
      services_vrps = Interpreters::SplitClustering.split_balanced_kmeans(services_vrps, 5, :duration, 'work_day')
      assert_equal 5, services_vrps.size
      services_vrps.each{ |service_vrp|
        # TODO: durations should be sum of setup_duration & duration
        durations << service_vrp[:vrp].services.collect{ |service| service[:activity][:duration] * service[:visits_number] }.sum
      }
      average_duration = durations.inject(0, :+) / durations.size
      durations.each{ |duration|
        # assert (duration < (average_duration + 1/2 * average_duration)) && duration > (average_duration - 1/2 * average_duration)
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
end
