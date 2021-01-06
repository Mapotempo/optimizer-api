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

module Models
  class VrpConsistencyTest < Minitest::Test
    include Rack::Test::Methods

    def test_reject_if_service_with_activities_in_position_relation
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:services].first[:activities] = [vrp[:services].first[:activity]]
      vrp[:services].first.delete(:activity)
      vrp[:relations] = [{
          id: 'force_first',
          type: 'force_first',
          linked_ids: [vrp[:services].first[:id]]
      }]

      assert_raises OptimizerWrapper::DiscordantProblemError do
          TestHelper.create(vrp)
      end
    end

    def test_reject_if_periodic_with_any_relation
      vrp = VRP.scheduling
      ['shipment', 'meetup',
       'same_route', 'sequence', 'order',
       'minimum_day_lapse', 'maximum_day_lapse', 'minimum_duration_lapse', 'maximum_duration_lapse',
       'vehicle_group_duration', 'vehicle_group_duration_on_weeks', 'vehicle_group_duration_on_months'].each{ |relation_type|
        vrp[:relations] = [{
            type: relation_type,
            linked_ids: ['service_1', 'service_2']
        }]

        assert_raises OptimizerWrapper::DiscordantProblemError do
            TestHelper.create(vrp)
        end
      }
    end

    def test_reject_if_pickup_position_uncompatible_with_delivery
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
      vrp = VRP.scheduling
      vrp[:services].first[:activities] = [vrp[:services].first[:activity]]
      vrp[:services].first.delete(:activity)
      vrp[:routes] = [{ mission_ids: ['service_1'] }]
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        TestHelper.create(vrp)
      end
    end

    def test_reject_work_day_partition_with_unconsistent_lapses
      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 1
        s[:minimum_lapse] = 2
        s[:maximum_lapse] = 3
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      TestHelper.create(vrp) # no raise because if only one visit then lapse is not a problem

      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 2 # he now have more than one visit
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
      vrp[:configuration][:schedule][:range_indices][:end] = 14
      TestHelper.create(vrp) # no raise because it is possible to find a lapse multiple of 7

      vrp = VRP.scheduling
      vrp[:services].each{ |s|
        s[:visits_number] = 2
        s[:minimum_lapse] = 8
        s[:maximum_lapse] = 15
      }
      vrp[:configuration][:preprocessing][:partitions] = [{ entity: :work_day }]
      vrp[:configuration][:schedule][:range_indices][:end] = 21
      TestHelper.create(vrp) # no raise because it is possible to find a lapse multiple of 7

      vrp = VRP.scheduling
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
      assert_equal('Couldn\'t find Models::Point with ID=missing_point_id', exception.message)
    end

    def test_same_point_day_authorized
      vrp = VRP.scheduling
      reference_point = vrp[:services].first[:activity][:point_id]
      vrp[:services].first[:visits_number] = 3
      vrp[:services].first[:minimum_lapse] = 3
      vrp[:services].first[:maximum_lapse] = 3
      vrp[:services] << {
        id: 'last_service',
        visits_number: 2,
        minimum_lapse: 6,
        maximum_lapse: 6,
        activity: {
          point_id: reference_point
        }
      }
      vrp[:configuration][:resolution][:same_point_day] = true
      vrp[:configuration][:schedule][:range_indices][:end] = 10
      result = OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      assert result # there exist a common_divisor

      vrp[:services].last[:minimum_lapse] = vrp[:services].last[:maximum_lapse] = 7
      assert_raises OptimizerWrapper::UnsupportedProblemError do
        OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, TestHelper.create(vrp), nil)
      end
    end

    def test_reject_if_shipments_and_periodic_heuristic
      vrp = VRP.pud
      vrp[:configuration][:preprocessing][:first_solution_strategy] = 'periodic'
      vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }}

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
  end
end
