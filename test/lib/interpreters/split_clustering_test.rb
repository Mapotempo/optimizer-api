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

  def test_cluster_one_phase
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
    },{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'work_day'
    }]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal generated_services_vrps.size, 10

    vrp[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration',
      entity: 'work_day'
    }]
    service_vrp = {vrp: FCT.create(vrp), service: :demo}
    generated_services_vrps = Interpreters::SplitClustering.split_clusters([service_vrp]).flatten.compact
    assert_equal generated_services_vrps.size, 10
  end
end
