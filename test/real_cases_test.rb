# Copyright © Mapotempo, 2016
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

include Hashie::Extensions::SymbolizeKeys

class RealCasesTest < Minitest::Test

  if !ENV['SKIP_REAL_CASES']
    # ##################################
    # ########## TEST PATTERN
    # ##################################
    # def test_***
    #   vrp = FCT.load_vrp(self)
    #   result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
    #   assert result

    #   # Check routes
    #   assert_equal ***, result[:routes].size

    #   # Check activities
    #   assert_equal vrp.services.size + ***, result[:routes][0][:activities].size

    #   # Either check total travel time
    #   assert result[:routes][0][:total_travel_time] < ***, "Too long travel time: #{result[:routes][0][:total_travel_time]}"

    #   # Or check distance
    #   assert result[:total_distance] < ***, "Too long distance: #{result[:total_distance]}"
    # end

    # Bordeaux - 25 services with time window - dimension distance car - no late for vehicle
    def test_ortools_one_route_without_rest
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal check_vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total distance
      assert result[:total_distance] < 150000, "Too long distance: #{result[:total_distance]}"

      # Check elapsed time
      assert result[:elapsed] < 10000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Strasbourg - 107 services with few time windows - dimension distance car - late for services & vehicles
    def test_ortools_one_route_without_rest_2
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal check_vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total distance
      assert result[:total_distance] < 265000, "Too long distance: #{result[:total_distance]}"

      # Check elapsed time
      assert result[:elapsed] < 10000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Béziers - 203 services with time window - dimension time car - late for services & vehicles - force start and no wait cost
    def test_ortools_one_route_many_stops
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal check_vrp.services.size + 2, result[:routes][0][:activities].size

      # Check latest first activity
      assert result[:routes].collect{ |route| route[:activities][1][:begin_time] - route[:activities].first[:begin_time] }.max < 3400

      # Check total travel time
      assert result[:routes][0][:total_travel_time] < 23000, "Too long travel time: #{result[:routes][0][:total_travel_time]}"

      # Check elapsed time
      assert result[:elapsed] < 60000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lyon - 65 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_ortools_one_route_with_rest
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal check_vrp.services.size + 2 + 1, result[:routes][0][:activities].size

      # Check total travel time
      assert result[:routes][0][:total_travel_time] < 25000, "Too long travel time: #{result[:routes][0][:total_travel_time]}"

      # Check rest position
      rest_position = result[:routes][0][:activities].index{ |a| a[:rest_id] }
      assert rest_position > 10 && rest_position < vrp.services.size - 10, "Bad rest position: #{rest_position}"

      # Check elapsed time
      assert result[:elapsed] < 4000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Mont-de-Marsan - 61 services with time window + rest - dimension time car - late for services & vehicles
    def test_ortools_one_route_with_rest_and_waiting_time
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) < 5000, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"
      # Check activities
      assert_equal check_vrp.services.size + 2 + 1, result[:routes][0][:activities].size
      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lyon - 769 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_ortools_ten_routes_with_rest
      skip 'Test broken in one previous commit, to fix'
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }
      services_by_routes.each{ |k, v|
        assert_equal v.size, result[:routes].find{ |r| r[:vehicle_id] == k[0] }[:activities].select{ |a| a[:service_id] }.size
      }

      # Check routes
      assert_equal vrp.vehicles.size, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) < 42300, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 420000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lille - 141 services with time window and quantity - no late for services
    def test_ortools_global_six_routes_without_rest
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check routes
      assert_equal (vrp.vehicles.size), result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) <= 59180, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check activities
      activities = result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      assert 140 < activities, "Not enough activities: #{activities}"

      # Check elapsed time
      assert result[:elapsed] < 20000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Bordeaux - 81 services with time window - late for services & vehicles
    def test_ortools_global_ten_routes_without_rest
      skip 'Test broken in one previous commit, to fix'
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)

      # Check routes
      assert_equal 4, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) < 31700, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Angers - Route duration and vehicle timewindow are identical
    def test_ortools_global_with_identical_route_duration_and_vehicle_window
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result

      # Check activities
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service35' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service83' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service84' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service88' || unassigned[:service_id] == 'service89' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'R1169' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'R1183' }
      assert_equal check_vrp.services.size - 6, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)

      # Check routes
      assert_equal 29, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) < 176000, "Too long travel time:# {result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 8000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # La Roche-Sur-Yon - A single route with a single double timewindow
    def test_ortools_one_route_with_single_mtws
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+) + result[:unassigned].size
      assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      assert_equal 1, result[:unassigned].reject{ |u| u[:reason].nil? }.size
      services_by_routes = check_vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) <= 6305, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 7000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Haute-Savoie - A single route with a visit with 2 open timewindows (0 ; x] [y ; ∞)
    def test_ortools_open_timewindows
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = check_vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) <= 13225, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 5000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Nantes - A single route with an order defining the most part of the route
    def test_ortools_single_route_with_route_order
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }

      expected_ids = vrp.relations.first.linked_ids
      actual_route = result[:routes].first[:activities].collect{ |activity|
        activity[:service_id]
      }

      route_order = actual_route.select{ |service_id|
        expected_ids.include?(service_id)
      }
      # Check solution order
      assert_equal expected_ids, route_order

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) <= 12085, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 65000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Nice - A single route with an order defining the most part of the route, many stops
    def test_ortools_single_route_with_route_order_2
      skip 'Test broken in one previous commit, to fix'
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }

      expected_ids = vrp.relations.first.linked_ids
      actual_route = result[:routes].first[:activities].collect{ |activity|
        activity[:service_id]
      }

      route_order = actual_route.select{ |service_id|
        expected_ids.include?(service_id)
      }
      # Check solution order
      assert_equal expected_ids, route_order

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+) < 13500, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time] }.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Bordeaux - route  with transmodality point
    def test_ortools_multimodal_route
      skip "Multimodal implementation might be making a hard copy instead of a soft one.
            and it losses the connection between vrp.points and vrp.services[#].activity.point._blankslate_as_name.
            Gwen said he will fix it."
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools, :ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      assert 2 <= result[:routes].map{ |r| r[:activities].select{ |a| a[:point_id] == 'Park_eugene_leroy' }.size }.reduce(&:+)

      # Check total cost
      assert result[:cost] < 6800, "Cost is to high: #{result[:cost]}"

      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Bordeaux - route with transmodality point
    def test_ortools_multimodal_route2
      skip "Multimodal implementation might be making a hard copy instead of a soft one.
            and it losses the connection between vrp.points and vrp.services[#].activity.point._blankslate_as_name.
            Gwen said he will fix it."
      vrp = FCT.load_vrp(self)
      check_vrp = Marshal.load(Marshal.dump(vrp))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools, :ortools] }}, vrp, nil)
      assert result
      # Check activities
      assert_equal check_vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      assert 2 <= result[:routes].map{ |r| r[:activities].select{ |a| a[:point_id] == 'Park_thiers' }.size }.reduce(&:+)

      # Check total cost
      assert result[:cost] < 7850, "Cost is to high: #{result[:cost]}"

      # Check elapsed time
      assert result[:elapsed] < 10000, "Too long elapsed time: #{result[:elapsed]}"
    end

    def test_dichotomious_check_number_of_services
      # TODO: This test is an old test left here. It doesn't have enough vehicles. It just check if we lose or add services.
      vrp = FCT.load_vrp(self)
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      routes = result[:routes]
      unassigned = result[:unassigned]

      result_num = {}
      result_num[:points] = (routes.flat_map{ |route| route[:activities].collect{ |act| act[:point_id] } } + unassigned.collect{ |unass| unass[:point_id] }).compact.uniq.size
      result_num[:services] = (routes.flat_map{ |route| route[:activities].reject{ |act| act[:service_id].nil? } } + unassigned.reject{ |unass| unass[:service_id].nil? }).compact.uniq.size
      result_num[:shipments] = (routes.flat_map{ |route| route[:activities].reject{ |act| act[:delivery_shipment_id].nil? && act[:pickup_shipment_id].nil? } } + unassigned.reject{ |unass| unass[:shipment_id].nil? }).compact.uniq.size
      result_num[:rests] = (routes.flat_map{ |route| route[:activities].reject{ |act| act[:rest_id].nil? } } + unassigned.reject{ |unass| unass[:rest_id].nil? }).compact.uniq.size

      %i[services shipments rests].each { |type|
        if vrp[type].nil?
          assert result_num[type].zero?, "Created additional #{type}"
        else
          assert result_num[type] <= vrp[type].size, "Created additional #{type}"
          assert result_num[type] >= vrp[type].size, "Lost some #{type}"
        end
      }
      assert result_num[:points] <= vrp[:points].size, 'Created additional points'
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_g1g2
      vrp = Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp']))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert result[:total_distance] <= 85100
      assert result[:unassigned].size <= 8
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_hv11
      assert_equal 0, result[:unassigned].size
      vrp = Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp']))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert result[:total_distance] <= 183800
      assert_equal 0, result[:unassigned].size
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_tv1
      vrp = Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp']))
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert result[:total_distance] <= 97400
      assert_equal 0, result[:unassigned].size
    end

    # North West of France - at the fastest with distance minimization with vehicle returning at the depot
    def test_instance_fr_tv11
      vrp = Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-2] + '.json').to_a.join)['vrp']))
      vrp.vehicles.first.end_point = vrp.vehicles.first.start_point
      vrp.vehicles.first.end_point_id = vrp.vehicles.first.start_point_id
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert result
      assert result[:total_distance] <= 105700
      assert_equal 0, result[:unassigned].size
    end
  end
end
