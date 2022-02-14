# Copyright © Mapotempo, 2021
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
require './models/concerns/validate_data'

module Models
  class VrpConsistencyTest < Minitest::Test
    include Rack::Test::Methods
    include ValidateData

    def test_reject_if_service_with_activities_in_position_relation
      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp[:services].first[:activities] = [vrp[:services].first[:activity]]
      vrp[:services].first.delete(:activity)
      vrp[:relations] = [{
          id: 'force_first',
          type: :force_first,
          linked_ids: [vrp[:services].first[:id]]
      }]

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_if_periodic_with_any_relation
      vrp = VRP.periodic
      vrp[:vehicles] << vrp[:vehicles].first.dup
      vrp[:vehicles].last[:id] += '_dup'
      vrp[:vehicles].first[:end_point_id] = 'point_0' # for vehicle_trips

      [Models::Relation::NO_LAPSE_TYPES,
       Models::Relation::ONE_LAPSE_TYPES,
       Models::Relation::SEVERAL_LAPSE_TYPES].each_with_index{ |types, index|
        lapses = index.zero? ? [] : [1]
        types.each{ |relation_type|
          next if %i[force_end force_first never_first].include?(relation_type) # those are supported with periodic heuristic

          linked_ids = ['service_1', 'service_2'] if Models::Relation::ON_SERVICES_TYPES.include?(relation_type)
          linked_vehicle_ids = ['vehicle_0', 'vehicle_0_dup'] if Models::Relation::ON_VEHICLES_TYPES.include?(relation_type)

          vrp[:relations] = [
            {
              type: relation_type,
              lapses: lapses,
              linked_ids: linked_ids,
              linked_vehicle_ids: linked_vehicle_ids
            }
          ]

          assert_raises OptimizerWrapper::UnsupportedProblemError do
            TestHelper.create(vrp)
          end
        }
      }
    end

    def test_reject_if_pickup_position_incompatible_with_delivery
      vrp = VRP.toy
      vrp[:shipments] = [{
          id: 'shipment_0',
          pickup: {
          point_id: 'point_0',
          position: :always_last
          },
          delivery: {
          point_id: 'point_1',
          position: :always_first
          }
      }]

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_routes_with_activities
      vrp = VRP.periodic
      vrp[:services].first[:activities] = [vrp[:services].first[:activity]]
      vrp[:services].first.delete(:activity)
      vrp[:routes] = [{ mission_ids: ['service_1'] }]
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_work_day_partition_with_inconsistent_lapses
      vrp = VRP.periodic
      vrp[:services].each{ |s|
        s[:visits_number] = 1
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 3
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      TestHelper.create(vrp) # no raise because if only one visit then lapse is not a problem

      vrp = VRP.periodic
      vrp[:services].each{ |s|
        s[:visits_number] = 2 # he now have more than one visit
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      vrp = VRP.periodic
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 7
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      vrp[:configuration][:schedule][:range_indices][:end] = 14
      TestHelper.create(vrp) # no raise because it is possible to find a lapse multiple of 7

      vrp = VRP.periodic
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 8
        s[:maximum_lapse] = 15
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      vrp[:configuration][:schedule][:range_indices][:end] = 21
      TestHelper.create(vrp) # no raise because it is possible to find a lapse multiple of 7

      vrp = VRP.periodic
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 8
        s[:maximum_lapse] = 12
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      vrp[:configuration][:schedule][:range_indices][:end] = 14
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp) # no lapse multiple of 7 is possible
      end
    end

    def test_split_independent_vrp_by_sticky_vehicle
      vrp = VRP.independent
      vrp[:services].last[:sticky_vehicle_ids] = ['missing_vehicle_id']

      assert_raises ActiveHash::RecordNotFound do
        TestHelper.create(vrp)
      end
    end

    def test_point_id_not_defined
      vrp = VRP.basic
      vrp[:services][0][:activity][:point_id] = 'missing_point_id'

      exception = assert_raises ActiveHash::RecordNotFound do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      end
      assert_equal("Couldn't find Models::Point with ID=#{vrp[:services][0][:activity][:point_id].inspect}", exception.message)
    end

    def test_reject_if_shipments_and_periodic_heuristic
      vrp = VRP.pud
      vrp[:configuration][:preprocessing][:first_solution_strategy] = 'periodic'
      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }}

      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_if_rests_and_periodic_heuristic
      vrp = VRP.periodic
      vrp[:rests] = [{
          id: 'rest_0',
          duration: 1,
          timewindows: [{
          day_index: 0
        }]
      }]
      vrp[:vehicles].first[:rests] = ['rest_0']

      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_assert_missions_in_route_exist
      problem = VRP.basic
      problem[:routes] = [{
        vehicle_id: 'vehicle_0',
        indice: 0,
        mission_ids: ['service_111', 'service_3']
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(problem)
      end
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

    def test_incorrect_matrix_indices
      problem = VRP.basic
      problem[:points].last[:matrix_index] = 4

      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(problem)
      end
    end

    def test_available_intervals_compatibility
      vrp = VRP.periodic
      vrp[:services].first[:unavailable_date_ranges] = [{ start: Date.new(2021, 2, 6),
                                                          end: Date.new(2021, 2, 8)}]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(vrp)
      end

      vrp = VRP.periodic
      vrp[:configuration][:schedule] = { range_indices: { start: 4, end: 7 } }
      vrp[:services].first[:unavailable_visit_day_indices] = [5]
      vrp[:services].first[:unavailable_index_ranges] = [{ start: 0, end: 7 }]
      vrp = TestHelper.create(vrp) # this should not raise
      assert_equal (4..7).to_a, vrp.services.first.unavailable_days.sort
    end

    def test_duplicated_ids_are_not_allowed
      vrp_base = VRP.basic
      # add missing fields so that they can be duplicated for the test
      vrp_base[:rests] = [{ id: 'rest', timewindows: [{ start: 1, end: 2 }], duration: 1 }]
      vrp_base[:shipments] = [{
        id: 'shipment',
        pickup: { point_id: 'point_3', duration: 3 },
        delivery: { point_id: 'point_2', duration: 3 },
        quantities: [{ unit_id: 'unit', value: 3 }]
      }]
      vrp_base[:zones] = [{ id: 'zone', polygon: { type: 'Polygon', coordinates: [[[0.5, 48.5], [1.5, 48.5]]] }}]
      vrp_base[:subtours] = [{ id: 'tour', time_bounds: 180 }]
      vrp_base[:units] = [{ id: 'unit' }]
      vrp_base[:vehicles].first[:capacities] = [{ unit_id: 'unit', limit: 10 }]
      vrp_base = Oj.dump(vrp_base)

      assert TestHelper.create(Oj.load(vrp_base)) # this should not produce any errors

      %i[
        matrices points rests services shipments units vehicles zones
      ].each{ |symbol|
        vrp = Oj.load(vrp_base)
        vrp[symbol] << { # Any object with the same id should raise IdError
          id: vrp[symbol].first[:id],
          activity: vrp[symbol].first[:activity],
          pickup: vrp[symbol].first[:pickup],
          delivery: vrp[symbol].first[:delivery],
        }.delete_if{ |_k, v| v.nil? }
        assert_raises ActiveHash::IdError do
          TestHelper.create(vrp)
        end
      }
    end

    def test_dates_cannot_be_mixed_with_indices
      vrp = VRP.periodic # contains schedule[:range_indices]
      vrp[:vehicles].first[:unavailable_work_date] = [Date.new(2021, 2, 11)]

      assert_raises OptimizerWrapper::DiscordantProblemError do
        Models::Vrp.filter(vrp)
      end
    end

    def test_switched_lapses_are_rejected
      vrp = VRP.periodic
      vrp[:services].first[:minimum_lapse] = 7
      vrp[:services].first[:maximum_lapse] = 14
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      check_consistency(vrp) # no raise

      vrp[:services].first[:visits_number] = 3
      vrp[:services].first[:minimum_lapse] = 14
      vrp[:services].first[:maximum_lapse] = 7
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
      assert_equal 'Minimum lapse can not be bigger than maximum lapse', error.message
    end

    def test_consistent_schedule
      vrp = VRP.periodic
      vrp[:configuration][:schedule] = {}
      assert_raises OptimizerWrapper::DiscordantProblemError do
        Models::Vrp.filter(vrp)
      end

      vrp[:configuration][:schedule] = { range_indices: { start: 3, end: 0 } }
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:configuration][:schedule] = { range_indices: { start: 7, end: 14 } }
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
    end

    def test_services_cannot_be_pickup_and_delivery_in_multiple_relations
      vrp = VRP.basic

      # complex shipment should be refused
      vrp[:relations] = [{ type: 'shipment', linked_ids: ['service_1', 'service_3'] },
                         { type: 'shipment', linked_ids: ['service_2', 'service_1'] }]
      error = assert_raises OptimizerWrapper::UnsupportedProblemError do
        check_consistency(TestHelper.coerce(vrp))
      end
      assert_equal 'A service cannot be both a delivery and a pickup in different relations. '\
                   'Following services appear in multiple shipment relations both as pickup and delivery: ',
                   error.message, 'Error message does not match'
    end

    def test_shipments_should_have_a_pickup_and_a_delivery
      vrp = VRP.basic
      # invalid shipments should be refused
      vrp[:relations] = [{ type: 'shipment', linked_ids: ['service_1', 'service_1'] },
                         { type: 'shipment', linked_ids: ['service_2'] },
                         { type: 'shipment', linked_ids: ['service_1', 'service_3'] }]
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        TestHelper.create(TestHelper.coerce(vrp))
      end
      assert_equal 'Shipment relations need to have two services -- a pickup and a delivery. ' \
                   'Relations of following services does not have exactly two linked_ids: ' \
                   'service_1, service_2',
                   error.message, 'Error message does not match'
    end

    def test_multi_pickup_or_multi_delivery_relations_are_accepted
      vrp = VRP.basic

      # multi-pickup single delivery
      vrp[:relations] = [{ type: 'shipment', linked_ids: ['service_1', 'service_3'] },
                         { type: 'shipment', linked_ids: ['service_2', 'service_3'] }]
      assert TestHelper.create(TestHelper.coerce(vrp)), 'Multi-pickup shipment should not be rejected'

      # single pickup multi-delivery
      vrp[:relations] = [{ type: 'shipment', linked_ids: ['service_1', 'service_3'] },
                         { type: 'shipment', linked_ids: ['service_1', 'service_2'] }]
      assert TestHelper.create(TestHelper.coerce(vrp)), 'Multi-delivery shipment should not be rejected'
    end

    def test_ensure_no_skill_matches_with_internal_skills_format
      vrp = VRP.basic
      vrp[:services].first[:skills] = ['vehicle_partition_for_test']
      error = assert_raises OptimizerWrapper::UnsupportedProblemError do
        check_consistency(vrp)
      end
      assert_equal "There are vehicles or services with 'vehicle_partition_*', 'work_day_partition_*' skills. These skill patterns are reserved for internal use and they would lead to unexpected behaviour.", error.message
    end

    def test_reject_when_duplicated_ids
      vrp = VRP.toy
      vrp[:services] << vrp[:services].first

      assert_raises ActiveHash::IdError do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      end
    end

    def test_vehicle_trips_relation_must_have_linked_vehicle_ids
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [{
        type: :vehicle_trips
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
    end

    def test_vehicles_store_consistency_with_vehicle_trips
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      check_consistency(vrp) # this should not raise

      vrp[:vehicles][1][:start_point_id] = 'point_1'
      # second trip should start where previous ended
      # at least until we implement a lapse between tours
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      first_vehicle_location = vrp[:points].find{ |pt| pt[:id] == 'point_0' }[:location]
      vrp[:points].find{ |pt| pt[:id] == 'point_1' }[:location] = first_vehicle_location
      check_consistency(vrp) # if ID is different but location is the same, nothing should be raised
    end

    def test_vehicle_timewindows_consistency_with_vehicle_trips
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      vrp[:vehicles][0][:timewindow] = { start: 10, end: 100 }
      vrp[:vehicles][1][:timewindow] = { start: 5, end: 7 }

      # next should be able to finish after previous
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][1][:timewindow] = { start: 5, end: 100 }
      check_consistency(vrp) # this should not raise
    end

    def test_compatible_days_availabilities_with_vehicle_trips
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      vrp[:vehicles][0][:timewindow] = { start: 0, end: 10 }
      check_consistency(vrp) # this should not raise

      vrp[:vehicles][0][:timewindow] = { start: 0, end: 10, day_index: 0 }
      # days are incompatible because first vehicle only works
      # on mondays while second vehicle is available everyday
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][1][:timewindow] = { start: 0, end: 10, day_index: 1 }
      # days are incompatible
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][1][:timewindow] = nil
      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 10 }}
      vrp[:vehicles][1][:sequence_timewindows] = [{ start: 0, end: 10, day_index: 0 }, { start: 0, end: 10, day_index: 1 }]
      # vehicles have common day index 0 but they are still not available at exact same days
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][0][:timewindow] = nil
      vrp[:vehicles][0][:sequence_timewindows] = [{ start: 0, end: 10, day_index: 0 }, { start: 0, end: 10, day_index: 1 }]
      check_consistency(vrp) # this should not raise
    end

    def test_compatible_days_availabilities_with_vehicle_trips_with_sequence_timewindows
      vrp = VRP.lat_lon_two_vehicles
      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }}
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      vrp[:vehicles][0][:sequence_timewindows] = [{ start: 0, end: 10, day_index: 0 },
                                                  { start: 20, end: 30, day_index: 1 }]
      vrp[:vehicles][1][:sequence_timewindows] = [{ start: 5, end: 15, day_index: 0 },
                                                  { start: 17, end: 45, day_index: 1 }]

      check_consistency(vrp) # this should not raise

      vrp[:vehicles][1][:sequence_timewindows] = [{ start: 5, end: 15, day_index: 0 }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][1][:sequence_timewindows] = [{ start: 5, end: 15 }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end

      vrp[:vehicles][1][:sequence_timewindows] = [{ start: 5, end: 15, day_index: 0 },
                                                  { start: 17, end: 19, day_index: 1 }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
    end

    def test_unavailable_days_with_vehicle_trips
      vrp = VRP.lat_lon_periodic_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      # vehicle trips are not available with periodic heuristic for now :
      vrp[:configuration][:preprocessing] = nil
      check_consistency(vrp) # this should not raise

      vrp[:vehicles][0][:unavailable_work_day_indices] = [0, 1]
      vrp[:vehicles][1][:unavailable_work_day_indices] = [2, 3]
      # no common day_index anymore
      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
    end

    def test_vehicle_in_vehicle_trips_does_not_exist
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      vrp[:relations].first[:linked_vehicle_ids] << 'unknown vehicle'

      assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
    end

    def test_vehicle_trips_incompatible_with_clustering
      vrp = VRP.lat_lon_two_vehicles
      vrp[:relations] = [TestHelper.vehicle_trips_relation(vrp[:vehicles])]
      vrp[:configuration][:preprocessing] = { partitions: TestHelper.vehicle_and_days_partitions }
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        check_consistency(vrp)
      end

      vrp[:configuration][:preprocessing] = nil
      check_consistency(vrp) # this should not raise
    end

    def test_reject_complex_vehicle_trips
      vrp = VRP.lat_lon_two_vehicles
      check_consistency(Oj.load(Oj.dump(vrp))) # this should not raise

      vrp[:vehicles] << Oj.load(Oj.dump(vrp[:vehicles].last)).deep_merge!({ id: 'vehicle_2' })
      # complex (overlapping) vehicle_trips relations
      vrp[:relations] = [
        TestHelper.vehicle_trips_relation(vrp[:vehicles][0..1]),
        TestHelper.vehicle_trips_relation(vrp[:vehicles][1..2]),
      ]
      error = assert_raises OptimizerWrapper::UnsupportedProblemError do
        check_consistency(vrp)
      end
      assert_equal 'A vehicle cannot appear in more than one vehicle_trips relation', error.message
    end

    def test_reject_when_unfeasible_vehicle_timewindows
      vrp = VRP.toy
      vrp[:vehicles].first[:timewindow] = { start: 10000, end: 0 }
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
      assert_equal 'Vehicle timewindows are infeasible',
                   error.message, 'Error message does not match'

      vrp[:vehicles].first[:timewindow] = nil
      vrp[:vehicles].first[:sequence_timewindows] = [{ start: 100, end: 200}, { start: 150, end: 100 }]
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
      assert_equal 'Vehicle timewindows are infeasible',
                   error.message, 'Error message does not match'
    end

    def test_pickup_timewindow_after_delivery_timewindow
      problem = VRP.pud

      problem[:shipments].first[:pickup][:timewindows] = [{ start: 6, end: 9}]
      problem[:shipments].first[:delivery][:timewindows] = [{ start: 1, end: 5}]

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem.dup), nil)

      reasons = solutions[0].unassigned_stops.flat_map{ |u| u[:reason].split(' && ') }

      assert_includes reasons, 'Inconsistent timewindows within relations of service', 'Expected an unfeasible shipment'

      problem[:shipments].first[:delivery][:timewindows] = [Models::Timewindow.create(start: 1, end: 9)]

      solutions = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem), nil)

      assert_empty solutions[0].unassigned_stops, 'There should be no unassigned services'
    end

    def test_uniqueness_of_provided_services_or_vehicles_in_relation
      problem = VRP.basic
      problem[:relations] = [{
        linked_ids: ['service_1', 'service_1'],
        type: :same_route
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem.dup), nil)
      end

      problem[:relations] = [{
        linked_vehicle_ids: ['service_1', 'service_1'],
        type: :vehicle_trips
      }]
      assert_raises OptimizerWrapper::DiscordantProblemError do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(problem.dup), nil)
      end
    end

    def test_relations_provided_lapse_consistency
      problem = VRP.basic
      service_ids = problem[:services].map{ |s| s[:id] }
      vehicle_ids = problem[:vehicles].map{ |v| v[:id] }

      Models::Relation::NO_LAPSE_TYPES.each{ |type|
        problem[:relations] = [{ type: type, lapse: 3 }]
        Models::Relation::ON_SERVICES_TYPES.include?(type) ?
          problem[:relations].first[:linked_ids] = service_ids :
          problem[:relations].first[:linked_vehicle_ids] = vehicle_ids
        assert_raises OptimizerWrapper::DiscordantProblemError do
          check_consistency(problem)
        end

        problem[:relations] = [{ type: type, lapses: [3, 4] }]
        Models::Relation::ON_SERVICES_TYPES.include?(type) ?
          problem[:relations].first[:linked_ids] = service_ids :
          problem[:relations].first[:linked_vehicle_ids] = vehicle_ids
        assert_raises OptimizerWrapper::DiscordantProblemError do
          check_consistency(problem)
        end
      }

      Models::Relation::ONE_LAPSE_TYPES.each{ |type|
        problem[:relations] = [{ type: type, lapse: 3 }]
        Models::Relation::ON_SERVICES_TYPES.include?(type) ?
          problem[:relations].first[:linked_ids] = service_ids :
          problem[:relations].first[:linked_vehicle_ids] = vehicle_ids
        check_consistency(problem)

        problem[:relations] = [{ type: type, lapses: [3, 4] }]
        Models::Relation::ON_SERVICES_TYPES.include?(type) ?
          problem[:relations].first[:linked_ids] = service_ids :
          problem[:relations].first[:linked_vehicle_ids] = vehicle_ids
        assert_raises OptimizerWrapper::DiscordantProblemError do
          check_consistency(problem)
        end
      }
    end

    def test_relations_number_of_lapses_consistency_when_authorized_lapses
      problem = VRP.lat_lon_two_vehicles

      Models::Relation::SEVERAL_LAPSE_TYPES.each{ |type|
        problem[:relations] = [{ type: type, lapse: 3 }]
        if Models::Relation::ON_SERVICES_TYPES.include?(type)
          problem[:relations].first[:linked_ids] = problem[:services].map{ |s| s[:id] }
        else
          problem[:relations].first[:linked_vehicle_ids] = [problem[:vehicles].first[:id]]
        end
        check_consistency(problem)

        case type
        when :vehicle_trips
          problem[:relations] = [TestHelper.vehicle_trips_relation(problem[:vehicles])]
          problem[:relations].first[:lapses] = [2]
          check_consistency(problem)

          problem[:relations].first[:lapses] = [2, 4]
        else
          problem[:relations] = [{ type: type, linked_ids: problem[:services][0..2].collect{ |s| s[:id] } }]
          problem[:relations].first[:lapses] = [2]
          check_consistency(problem)

          problem[:relations].first[:lapses] = [2, 2]
          check_consistency(problem)

          problem[:relations].first[:lapses] = [2, 3, 2]
        end

        assert_raises OptimizerWrapper::DiscordantProblemError do
          check_consistency(problem)
        end
      }
    end

    def test_reject_if_different_day_indices_without_schedule
      vrp = VRP.basic
      vrp[:vehicles][0][:timewindow] = { day_index: 0 }
      vrp[:services][0][:activity][:timewindows] = [{ day_index: 0 }]
      check_consistency(vrp) # no error expected because we can ignore day indices if they are all the same

      vrp[:services][1][:activity][:timewindows] = [{ day_index: 1 }]
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp)
      end
      assert_equal 'There cannot be different day indices if no schedule is provided', error.message
    end

    def test_reject_if_sequence_timewindows_without_schedule
      vrp = VRP.basic
      vrp[:vehicles][0].delete(:timewindow)
      vrp[:vehicles][0][:sequence_timewindows] = [{ start: 0, end: 10 }]
      error = assert_raises OptimizerWrapper::UnsupportedProblemError do
        check_consistency(vrp)
      end
      assert_equal 'Vehicle[:sequence_timewindows] are only available when a schedule is provided', error.message
    end

    def test_route_has_no_day_unless_schedule_or_one_route
      vrp = VRP.basic
      vrp[:routes] = [{ mission_ids: [], day_index: 0 }]
      check_consistency(vrp) # no error expected because we have one route and only one vehicle
      vrp[:vehicles][0][:timewindow] = { day_index: 1 }
      error = assert_raises OptimizerWrapper::DiscordantProblemError do
        check_consistency(vrp) # one route and only one vehicle, but day indices do not match
      end
      assert_equal 'There cannot be different day indices if no schedule is provided', error.message

      vrp[:configuration][:schedule] = { mission_ids: [], range_indices: { start: 0, end: 3 }}
      check_consistency(vrp) # no error expected because we do have a schedule now
    end
  end
end
