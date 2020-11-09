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

module Models
  class VrpTest < Minitest::Test
    include Rack::Test::Methods

    def test_deduced_range_indices
      vrp = VRP.scheduling
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2020, 1, 1), # wednesday
          end: Date.new(2020, 1, 6) # saturday
        }
      }

      new_vrp = TestHelper.create(vrp)
      assert_equal({ start: 2, end: 7 }, new_vrp.schedule_range_indices)

      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2019, 12, 30), # wednesday
          end: Date.new(2020, 1, 6) # saturday
        }
      }
      new_vrp = TestHelper.create(vrp)
      assert_equal({ start: 0, end: 7 }, new_vrp.schedule_range_indices)
    end

    def test_visits_computation
      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)

      assert_equal vrp.services.size, vrp.visits

      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)
      vrp.services.each{ |service| service[:visits_number] *= 2 }

      assert_equal 2 * vrp.services.size, vrp.visits

      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_clustered')
      assert_equal vrp.services.sum{ |s| s[:visits_number] }, vrp.visits
    end

    def test_vrp_scheduling
      vrp = VRP.toy
      vrp = TestHelper.create(vrp)
      refute vrp.schedule_range_indices

      vrp = VRP.scheduling_seq_timewindows
      vrp = TestHelper.create(vrp)
      assert vrp.schedule_range_indices
    end

    def test_month_indice_generation
      problem = VRP.basic
      problem[:relations] = [{
        type: 'vehicle_group_duration_on_months',
        linked_vehicle_ids: ['vehicle_0'],
        lapse: 2,
        periodicity: 1
      }]
      problem[:configuration][:preprocessing]
      problem[:configuration][:schedule] = {
        range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
      }

      vrp = TestHelper.create(problem)
      assert_equal [[4], [5]], vrp.schedule_months_indices
    end

    def test_unavailable_visit_day_date_transformed_into_indice
      vrp = VRP.basic
      vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 2) }}
      vrp[:services][0][:unavailable_visit_day_date] = [Date.new(2020, 1, 1)]
      vrp[:services][1][:unavailable_visit_day_date] = [Date.new(2020, 1, 2)]
      created_vrp = TestHelper.create(vrp)
      assert_equal [2], created_vrp.services[0].unavailable_visit_day_indices
      assert_equal [3], created_vrp.services[1].unavailable_visit_day_indices
    end

    def test_reject_work_day_partition
      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 1
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 3
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      TestHelper.create(vrp) # no raise

      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 2
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      TestHelper.create(vrp) # no raise

      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 3
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 7
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      TestHelper.create(vrp) # no raise
    end

    def test_reject_routes_with_activities
      vrp = VRP.scheduling
      vrp[:services].first[:activities] = [vrp[:services].first[:activity]]
      vrp[:services].first.delete(:activity)
      vrp[:routes] = [{ mission_ids: ['service_1'] }]
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_deduce_sticky_vehicles_if_route_and_clustering
      vrp = VRP.basic
      vrp[:routes] = [{ mission_ids: ['service_1', 'service_3'], vehicle_id: 'vehicle_0' }]
      vrp[:configuration][:preprocessing] = { partitions: [{ entity: :vehicle }] }
      generated_vrp = TestHelper.create(vrp)
      refute_empty generated_vrp.services[0].sticky_vehicles
      assert_empty generated_vrp.services[1].sticky_vehicles
      refute_empty generated_vrp.services[2].sticky_vehicles
    end

    def test_reject_if_shipments_and_periodic_heuristic
      vrp = VRP.scheduling
      vrp[:shipments] = [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_1'
        }
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_if_rests_and_periodic_heuristic
      vrp = VRP.scheduling
      vrp[:rests] = [{
        id: 'rest_0',
        duration: 1,
        timewindows: [{
          day_index: 0
        }]
      }]
      vrp[:vehicles].first[:rests] = ['rest_0']

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_deduce_consistent_relations
      vrp = VRP.pud

      ['minimum_duration_lapse', 'maximum_duration_lapse'].each{ |relation_type|
        vrp[:relations] = [{
          type: relation_type,
          linked_ids: ['shipment_0', 'shipment_1'],
          lapse: 3
        }]

        generated_vrp = TestHelper.create(vrp)
        assert_equal 1, generated_vrp.relations.size
        assert_equal 2, generated_vrp.relations.first.linked_ids.size
        assert_includes generated_vrp.relations.first.linked_ids, 'shipment_0delivery'
        assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1pickup'
      }

      vrp[:services] = [{
        id: 'service',
        activity: { point_id: 'point_1' }
      }]
      vrp[:relations] = [{
        type: 'minimum_duration_lapse',
        linked_ids: ['service', 'shipment_1'],
        lapse: 3
      }]
      generated_vrp = TestHelper.create(vrp)
      assert_includes generated_vrp.relations.first.linked_ids, 'service'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1pickup'

      vrp[:relations] = [{
        type: 'same_route',
        linked_ids: ['service', 'shipment_0', 'shipment_1'],
        lapse: 3
      }]
      generated_vrp = TestHelper.create(vrp)
      assert_includes generated_vrp.relations.first.linked_ids, 'service'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_0pickup'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1pickup'

      %w[sequence order].each{ |relation_type|
        vrp[:relations].first[:type] = relation_type
        vrp[:relations].first[:linked_ids] = ['service', 'shipment_1']
        assert_raises OptimizerWrapper::DiscordantProblemError do
          TestHelper.create(vrp)
        end
      }

      vrp[:relations].first[:linked_ids] = ['service']
      %w[sequence order].each{ |relation_type|
        vrp[:relations].first[:type] = relation_type
        TestHelper.create(vrp) # check no error provided
      }
    end

    def test_vehicle_unavailable_days_consideration
      problem = VRP.toy
      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      problem[:configuration][:schedule] = { range_indices: { start: 0, end: 7 }}

      vrp = TestHelper.create(problem)
      assert_equal [5, 6], vrp.vehicles.first.unavailable_work_day_indices

      problem[:vehicles].first[:timewindow] = { start: 0, end: 1000 }
      vrp = TestHelper.create(problem)
      assert_equal [5, 6], vrp.vehicles.first.unavailable_work_day_indices

      problem[:vehicles].first.delete(:timewindow)
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 1000 }]
      vrp = TestHelper.create(problem)
      assert_equal [5, 6], vrp.vehicles.first.unavailable_work_day_indices

      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 1000, day_index: 0 }]
      vrp = TestHelper.create(problem)
      assert_empty vrp.vehicles.first.unavailable_work_day_indices, 'This vehicle is only available on mondays, we can ignore unavailable_work_days_indices that are week-end days'

      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      problem[:vehicles].first.delete(:timewindow)
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 1000, day_index: 0 }, { start: 0, end: 1000, day_index: 5 }, { start: 0, end: 1000, day_index: 6 }]
      vrp = TestHelper.create(problem)
      assert_equal [5, 6], vrp.vehicles.first.unavailable_work_day_indices
    end
  end
end
