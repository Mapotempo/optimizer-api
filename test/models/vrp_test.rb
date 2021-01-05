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

    def test_deduce_sticky_vehicles_if_route_and_clustering
      vrp = VRP.basic
      vrp[:routes] = [{ mission_ids: ['service_1', 'service_3'], vehicle_id: 'vehicle_0' }]
      vrp[:configuration][:preprocessing] = { partitions: [{ entity: :vehicle }] }
      generated_vrp = TestHelper.create(vrp)
      refute_empty generated_vrp.services[0].sticky_vehicles
      assert_empty generated_vrp.services[1].sticky_vehicles
      refute_empty generated_vrp.services[2].sticky_vehicles
    end

    def test_solver_parameter_retrocompatibility
      vrp = VRP.basic
      generated_vrp = TestHelper.create(vrp)
      assert generated_vrp.resolution_solver
      assert_nil generated_vrp.preprocessing_first_solution_strategy

      vrp[:configuration][:resolution][:solver_parameter] = -1
      generated_vrp = TestHelper.create(vrp)
      refute generated_vrp.resolution_solver
      assert_nil generated_vrp.preprocessing_first_solution_strategy

      ['path_cheapest_arc', 'global_cheapest_arc', 'local_cheapest_insertion', 'savings', 'parallel_cheapest_insertion', 'first_unbound', 'christofides'].each_with_index{ |heuristic, heuristic_reference|
        vrp = VRP.basic
        vrp[:configuration][:resolution][:solver_parameter] = heuristic_reference
        generated_vrp = TestHelper.create(vrp)
        assert generated_vrp.resolution_solver
        assert_equal [heuristic], generated_vrp.preprocessing_first_solution_strategy
      }
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

    def test_remove_unecessary_units
      vrp = TestHelper.load_vrp(self)
      assert_empty vrp.units
      vrp.vehicles.all?{ |v| v.capacities.empty? }
      vrp.services.all?{ |s| s.quantities.empty? }
    end

    def test_remove_unecessary_units_one_needed
      vrp = TestHelper.load_vrp(self)
      assert_equal 1, vrp.units.size
      assert_operator vrp.vehicles.collect{ |v| v.capacities.collect(&:unit_id) }.flatten!.uniq!,
                      :==,
                      vrp.services.collect{ |s| s.quantities.collect(&:unit_id) }.flatten!.uniq!
    end

    def test_vrp_creation_if_route_and_partitions
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:routes] = [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1']
      }, {
        vehicle_id: 'vehicle_1',
        mission_ids: ['service_7']
      }]
      vrp[:configuration][:preprocessing] = {
        partitions: TestHelper.vehicle_and_days_partitions
      }

      vrp = TestHelper.create(vrp)
      assert_equal 2, (vrp.services.count{ |s| !s.sticky_vehicles.empty? })
      assert_equal 'vehicle_0', vrp.services.find{ |s| s.id == 'service_1' }.sticky_vehicles.first.id
      assert_equal 'vehicle_1', vrp.services.find{ |s| s.id == 'service_7' }.sticky_vehicles.first.id
    end

    def test_transform_route_indice_into_index
      original_vrp = VRP.lat_lon_scheduling_two_vehicles
      original_vrp[:routes] = [{
        vehicle_id: 'vehicle_0',
        mission_ids: ['service_1'],
        indice: 10
      }]
      original_vrp[:configuration][:preprocessing] = {
        partitions: TestHelper.vehicle_and_days_partitions
      }

      vrp = TestHelper.create(original_vrp)
      assert_raises NoMethodError do
        vrp.routes.first.indice
      end
      assert vrp.routes.first.day_index
      assert_equal 10, vrp.routes.first.day_index
    end

    def test_reject_if_several_visits_but_no_schedule_provided
      # If this test fail then it probably returns 'Wrong number of visits returned in result'
      # This makes sense, since we do not expand the problem if no schedule is provided,
      # therefore there is a gap between expected and returned number of visits
      vrp = VRP.toy
      vrp[:services][0][:visits_number] = 10

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 10 } }
      assert TestHelper.create(vrp) # no raise when schedule is provided

      vrp = VRP.pud
      vrp[:shipments][0][:visits_number] = 10

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 10 } }
      assert TestHelper.create(vrp) # no raise when no schedule is provided
    end
  end
end
