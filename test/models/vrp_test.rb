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
      vrp = VRP.periodic
      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2020, 1, 1), # wednesday
          end: Date.new(2020, 1, 6) # saturday
        }
      }

      new_vrp = TestHelper.create(vrp)
      assert_equal({ start: 2, end: 7 }, new_vrp.configuration.schedule.range_indices)

      vrp[:configuration][:schedule] = {
        range_date: {
          start: Date.new(2019, 12, 30), # wednesday
          end: Date.new(2020, 1, 6) # saturday
        }
      }
      new_vrp = TestHelper.create(vrp)
      assert_equal({ start: 0, end: 7 }, new_vrp.configuration.schedule.range_indices)
    end

    def test_visits_computation
      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      assert_equal vrp.services.size, vrp.visits

      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.services.each{ |service| service.visits_number *= 2 }
      assert_equal 2 * vrp.services.size, vrp.visits

      vrp = TestHelper.create(VRP.periodic_seq_timewindows)
      vrp.services.each{ |service| service.visits_number = rand(100) }
      assert_equal vrp.services.sum(&:visits_number), vrp.visits
    end

    def test_vrp_periodic
      vrp = VRP.toy
      vrp = TestHelper.create(vrp)
      refute vrp.configuration.schedule&.range_indices

      vrp = VRP.periodic_seq_timewindows
      vrp = TestHelper.create(vrp)
      assert vrp.configuration.schedule&.range_indices
    end

    def test_month_indice_generation
      problem = VRP.basic
      problem[:relations] = [{
        type: :vehicle_group_duration_on_months,
        linked_vehicle_ids: ['vehicle_0'],
        lapse: 2,
        periodicity: 1
      }]
      problem[:configuration][:preprocessing]
      problem[:configuration][:schedule] = {
        range_date: { start: Date.new(2020, 1, 31), end: Date.new(2020, 2, 1) }
      }

      vrp = TestHelper.create(problem)
      assert_equal [[4], [5]], vrp.configuration.schedule.months_indices
    end

    def test_unavailable_visit_day_date_transformed_into_indice
      vrp = VRP.basic
      vrp[:configuration][:schedule] = { range_date: { start: Date.new(2020, 1, 1), end: Date.new(2020, 1, 2) }}
      vrp[:services][0][:unavailable_visit_day_date] = [Date.new(2020, 1, 1)]
      vrp[:services][1][:unavailable_visit_day_date] = [Date.new(2020, 1, 2)]
      created_vrp = TestHelper.create(vrp)
      assert_equal Set[2], created_vrp.services[0].unavailable_days
      assert_equal Set[3], created_vrp.services[1].unavailable_days
    end

    def test_deduce_sticky_vehicles_if_route_and_clustering
      vrp = VRP.basic
      vrp[:routes] = [{ mission_ids: ['service_1', 'service_3'], vehicle_id: 'vehicle_0' }]
      vrp[:configuration][:preprocessing] = { partitions: [{ entity: :vehicle }] }
      generated_vrp = TestHelper.create(vrp)

      assert(generated_vrp.services[0].sticky_vehicle_ids.any?)
      assert(generated_vrp.services[2].sticky_vehicle_ids.any?)

      assert(generated_vrp.services[1].sticky_vehicle_ids.empty?)
    end

    def test_solver_parameter_retrocompatibility
      vrp = VRP.basic
      generated_vrp = TestHelper.create(vrp)
      assert generated_vrp.configuration.resolution.solver
      assert_empty generated_vrp.configuration.preprocessing.first_solution_strategy, 'first_solution_strategy'

      vrp[:configuration][:resolution][:solver_parameter] = -1
      generated_vrp = TestHelper.create(vrp)
      refute generated_vrp.configuration.resolution.solver
      assert_empty generated_vrp.configuration.preprocessing.first_solution_strategy, 'first_solution_strategy'

      ['path_cheapest_arc', 'global_cheapest_arc', 'local_cheapest_insertion', 'savings', 'parallel_cheapest_insertion', 'first_unbound', 'christofides'].each_with_index{ |heuristic, heuristic_reference|
        vrp = VRP.basic
        vrp[:configuration][:resolution][:solver_parameter] = heuristic_reference
        generated_vrp = TestHelper.create(vrp)
        assert generated_vrp.configuration.resolution.solver
        assert_equal [heuristic], generated_vrp.configuration.preprocessing.first_solution_strategy
      }
    end

    def test_shipment_conversion_into_services
      vrp = VRP.pud
      generated_vrp = TestHelper.create(vrp)

      refute_respond_to generated_vrp, :shipments
      assert_equal 4, generated_vrp.services.size
      assert_equal(
        2, generated_vrp.relations.count{ |relation| relation.type == :shipment && relation.linked_services.size == 2 }
      )
    end

    def test_deduce_consistent_relations
      vrp = VRP.pud

      %i[minimum_duration_lapse maximum_duration_lapse].each{ |relation_type|
        vrp[:relations] = [{
          type: relation_type,
          linked_ids: ['shipment_0', 'shipment_1'],
          lapse: 3
        }]

        generated_vrp = TestHelper.create(vrp)
        assert_equal 3, generated_vrp.relations.size
        assert_equal 2, generated_vrp.relations.first.linked_ids.size
        assert_includes generated_vrp.relations.first.linked_ids, 'shipment_0_delivery'
        assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1_pickup'
      }

      vrp[:services] = [{
        id: 'service',
        activity: { point_id: 'point_1' }
      }]
      vrp[:relations] = [{
        type: :minimum_duration_lapse,
        linked_ids: ['service', 'shipment_1'],
        lapse: 3
      }]
      generated_vrp = TestHelper.create(vrp)
      assert_includes generated_vrp.relations.first.linked_ids, 'service'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1_pickup'

      vrp[:relations] = [{
        type: :same_route,
        linked_ids: ['service', 'shipment_0', 'shipment_1']
      }]
      generated_vrp = TestHelper.create(vrp)
      assert_includes generated_vrp.relations.first.linked_ids, 'service'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_0_pickup'
      assert_includes generated_vrp.relations.first.linked_ids, 'shipment_1_pickup'

      %i[sequence order].each{ |relation_type|
        vrp[:relations].first[:type] = relation_type
        vrp[:relations].first[:linked_ids] = ['service', 'shipment_1']
        assert_raises OptimizerWrapper::DiscordantProblemError do
          TestHelper.create(vrp)
        end
      }

      vrp[:relations].first[:linked_ids] = ['service']
      %i[sequence order].each{ |relation_type|
        vrp[:relations].first[:type] = relation_type
        TestHelper.create(vrp) # check no error provided
      }
    end

    def test_vehicle_unavailable_days_consideration
      problem = VRP.toy
      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      problem[:configuration][:schedule] = { range_indices: { start: 0, end: 7 }}

      vrp = TestHelper.create(problem)
      assert_equal Set[5, 6], vrp.vehicles.first.unavailable_days

      problem[:vehicles].first[:timewindow] = { start: 0, end: 1000 }
      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      vrp = TestHelper.create(problem)
      assert_equal Set[5, 6], vrp.vehicles.first.unavailable_days

      problem[:vehicles].first.delete(:timewindow)
      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 1000 }]
      vrp = TestHelper.create(problem)
      assert_equal Set[5, 6], vrp.vehicles.first.unavailable_days

      problem[:vehicles].first[:sequence_timewindows] = [{ start: 0, end: 1000, day_index: 0 }]
      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      vrp = TestHelper.create(problem)
      assert_empty vrp.vehicles.first.unavailable_days,
                   'This vehicle is only available on mondays, we can ignore weekd-end unavailable_days'

      problem[:vehicles].first[:unavailable_work_day_indices] = [5, 6]
      problem[:vehicles].first.delete(:timewindow)
      problem[:vehicles].first[:sequence_timewindows] =
        [0, 5, 6].collect{ |day_index| { start: 0, end: 1000, day_index: day_index } }
      vrp = TestHelper.create(problem)
      assert_equal Set[5, 6], vrp.vehicles.first.unavailable_days
    end

    def test_remove_unnecessary_units
      vrp = TestHelper.load_vrp(self)
      assert_empty vrp.units
      vrp.vehicles.all?{ |v| v.capacities.empty? }
      vrp.services.all?{ |s| s.quantities.empty? }
    end

    def test_remove_unnecessary_units_one_needed
      vrp = TestHelper.load_vrp(self)
      assert_equal 1, vrp.units.size
      assert_operator vrp.vehicles.collect{ |v| v.capacities.collect(&:unit_id) }.flatten!.uniq!,
                      :==,
                      vrp.services.collect{ |s| s.quantities.collect(&:unit_id) }.flatten!.uniq!
    end

    def test_vrp_creation_if_route_and_partitions
      vrp = VRP.lat_lon_periodic_two_vehicles
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
      assert_equal 2, (vrp.services.count{ |s| s.sticky_vehicle_ids.any? })
      assert(vrp.services.find{ |s| s.id == 'service_1' }.sticky_vehicle_ids.include?(vrp.vehicles.first.id))
      assert(vrp.services.find{ |s| s.id == 'service_7' }.sticky_vehicle_ids.include?(vrp.vehicles.last.id))
    end

    def test_transform_route_indice_into_index
      original_vrp = VRP.lat_lon_periodic_two_vehicles
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

    def test_available_interval
      vrp = VRP.periodic
      vrp[:configuration][:schedule] = { range_date: { start: Date.new(2021, 2, 5),
                                                       end: Date.new(2021, 2, 11)}}
      vrp[:services].first[:unavailable_visit_day_indices] = [9]
      vrp[:services].first[:unavailable_date_ranges] = [{ start: Date.new(2021, 2, 6),
                                                          end: Date.new(2021, 2, 8)}]

      assert_equal [5, 6, 7, 9], TestHelper.create(vrp).services.first.unavailable_days.sort
    end

    def test_no_lapse_in_relation
      vrp = VRP.basic
      vrp[:relations] = [{
        type: :vehicle_group_duration_on_months,
        linked_vehicle_ids: ['vehicle_0'],
        lapse: 2
      }]
      Models::Vrp.filter(vrp)
      refute_empty vrp[:relations]

      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [{
        type: :vehicle_trips,
        linked_vehicle_ids: vrp[:vehicles].collect{ |v| v[:id] }
      }]
      Models::Vrp.filter(vrp)
      refute_empty vrp[:relations] # do not reject even if no lapse, lapse is not mandatory
    end

    def test_original_skills_and_skills_are_equal_after_create
      vrp = VRP.basic
      vrp[:vehicles].first[:skills] = [['skill_to_output']]
      vrp[:services].first[:skills] = ['skill_to_output']

      created_vrp = TestHelper.create(vrp)
      assert_equal 1, created_vrp.services.first.skills.size
      assert_equal created_vrp.services.first.original_skills.size, created_vrp.services.first.skills.size
    end

    def test_filter_duplicated_relations
      vrp = VRP.basic
      vrp[:relations] = [{
        type: :shipment,
        linked_ids: ['service_1', 'service_2']
      }]
      Models::Vrp.filter(vrp)
      assert_equal 1, vrp[:relations].size

      vrp[:relations] << vrp[:relations].first
      assert_equal 2, vrp[:relations].size
      Models::Vrp.filter(vrp)
      assert_equal 1, vrp[:relations].size
    end

    def test_same_vehicle_relation_converted_into_same_route_if_no_vehicle_partition
      problem = VRP.lat_lon_two_vehicles
      problem[:relations] = [{ type: :same_vehicle, linked_ids: ['service_1', 'service_2'] }]

      created_vrp = Models::Vrp.create(problem)
      assert(created_vrp.relations.none?{ |relation| relation.type == :same_vehicle })
      assert(created_vrp.relations.any?{ |relation| relation.type == :same_route })

      problem[:relations] = [{ type: :same_vehicle, linked_ids: ['service_1', 'service_2'] }]
      problem[:configuration][:preprocessing] = { partitions: TestHelper.vehicle_and_days_partitions }
      created_vrp = Models::Vrp.create(problem)
      assert(created_vrp.relations.any?{ |relation| relation.type == :same_vehicle })
      assert(created_vrp.relations.none?{ |relation| relation.type == :same_route })
    end

    def test_lapse_converted_into_lapses
      problem = VRP.lat_lon_two_vehicles
      problem[:relations] = [TestHelper.vehicle_trips_relation(problem[:vehicles])]
      problem[:relations].first[:lapse] = 2

      created_vrp = Models::Vrp.create(problem)
      assert_nil problem[:relations].first[:lapse]
      assert_equal [2], created_vrp.relations.first.lapses

      problem[:vehicles] << problem[:vehicles].first.dup
      problem[:vehicles].last[:id] += '_dup'
      problem[:relations] = [TestHelper.vehicle_trips_relation(problem[:vehicles])]
      problem[:relations].first[:lapse] = 2

      created_vrp = Models::Vrp.create(problem)
      assert_nil problem[:relations].first[:lapse]
      assert_equal [2, 2], created_vrp.relations.first.lapses
    end

    def test_creating_possible_days
      problem = VRP.periodic
      problem[:services][0][:first_possible_day_indices] = [0]
      problem[:services][1][:first_possible_dates] = [Date.new(2021, 7, 23)]
      problem[:services][0][:last_possible_day_indices] = [1]
      problem[:services][1][:last_possible_dates] = [Date.new(2021, 7, 24)]
      problem[:services][2][:first_possible_day_indices] = [1, 2]
      problem[:services] << problem[:services].last.dup
      problem[:services][3][:id] += '_dup'
      problem[:services][3][:visits_number] = 3
      problem[:services][3][:first_possible_day_indices] = [1, 2, 4, 5]
      problem[:services] << problem[:services].last.dup
      problem[:services][4][:id] += '_dup'
      problem[:services][4][:visits_number] = 4
      problem[:services][4][:first_possible_day_indices] = [1, 2, 4, 5]
      problem[:configuration][:schedule] = { range_date: { start: Date.new(2021, 7, 20), end: Date.new(2021, 7, 29) }}

      created_vrp = TestHelper.create(problem)
      assert_equal [0], created_vrp.services[0].first_possible_days
      assert_equal [4], created_vrp.services[1].first_possible_days # July 23rd corresponds to first Friday in period
      assert_equal [1], created_vrp.services[0].last_possible_days
      assert_equal [5], created_vrp.services[1].last_possible_days # July 23rd corresponds to first Saturday in period
      # We should keep as many values as the number visits
      assert_equal [1], created_vrp.services[2].first_possible_days
      assert_equal [1, 2, 4], created_vrp.services[3].first_possible_days
      assert_equal [1, 2, 4, 5], created_vrp.services[4].first_possible_days
    end

    def test_validate_rest_timewindows
      problem = VRP.basic
      problem[:rests] = [{
        id: 'rest',
        timewindows: [{ start: 0, end: 10 }, {start: 20, end: 15 }]
      }]

      TestHelper.create(problem) # this should not raise because no vehicle has this rest

      problem[:vehicles].first[:rest_ids] = ['rest']
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(problem)
      end

      problem[:rests].first[:timewindows] = [{ start: 0, end: 10 }]
      TestHelper.create(problem) # this should not raise because there is only one timewindow for this rest

      problem[:vehicles].first[:rest_ids] = ['unknown_rest']
      assert_raises ActiveHash::RecordNotFound do
        TestHelper.create(problem)
      end
    end

    def test_to_json
      problem = VRP.lat_lon_capacitated
      vrp = Models::Vrp.create(problem)
      vrp_hash = JSON.parse(vrp.to_json, symbolize_names: true)
      # Verify that an JSON dumped vrp may be imported again
      re_vrp = Models::Vrp.create(vrp_hash)

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:ortools] }}, re_vrp, nil)

      # Populate again the active hash base
      Models::Vrp.create(vrp_hash)
      solution_hash = JSON.parse(solutions[0].to_json, symbolize_names: true)
      # Verify that a JSON dumped solution may be imported again
      Models::Solution.new(solution_hash)
    end
  end
end
