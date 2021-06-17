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

class RealCasesTest < Minitest::Test
  if !ENV['SKIP_REAL_CASES']
    # ##################################
    # ########## TEST PATTERN
    # ##################################
    # def test_***
    #   vrp = TestHelper.load_vrp(self)
    #   solutions = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
    #   assert solutions[0]

    #   # Check routes
    #   assert_equal ***, solutions[0].routes.size

    #   # Check activities
    #   assert_equal vrp.services.size + ***, solutions[0].routes[0].activities.size

    #   # Either check total travel time
    #   assert solutions[0].routes[0][:total_travel_time] < ***,
    #          "Too long travel time: #{solutions[0].routes[0][:total_travel_time]}"

    #   # Or check distance
    #   assert solutions[0].info.total_distance < ***, "Too long distance: #{solutions[0].info.total_distance}"
    # end

    # Bordeaux - 25 services with time window - dimension distance car - no late for vehicle
    def test_ortools_one_route_without_rest
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal 1, solutions[0].routes.size

      # Check stops
      assert_equal check_vrp_services_size + 2, solutions[0].routes[0].stops.size

      # Check total distance
      assert solutions[0].info.total_distance < 150000, "Too long distance: #{solutions[0].info.total_distance}"

      # Check elapsed time
      assert solutions[0].elapsed < 10000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Strasbourg - 107 services with few time windows - dimension distance car - late for services & vehicles
    def test_ortools_one_route_without_rest_2
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal 1, solutions[0].routes.size

      # Check stops
      assert_equal check_vrp_services_size + 2, solutions[0].routes[0].stops.size

      # Check total distance
      assert solutions[0].info.total_distance < 265000, "Too long distance: #{solutions[0].info.total_distance}"

      # Check elapsed time
      assert solutions[0].elapsed < 10000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Béziers - 203 services with time window - dimension time car
    # late for services & vehicles - force start and no wait cost
    def test_ortools_one_route_many_stops
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size

      # imitate old lateness functionality (i.e., there is no limit on the maximum lateness)
      # maximum_lateness of the vehicle is increased to have the result with the old functionality
      vrp.vehicles.each{ |v| v.timewindow.maximum_lateness = 7 * 60 * 60 }

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal 1, solutions[0].routes.size

      # Check stops
      assert_equal check_vrp_services_size + 2, solutions[0].routes[0].stops.size

      # Check latest first stop
      assert solutions[0].routes.collect{ |route|
        route.stops[1].info.begin_time - route.stops[0].info.begin_time
      }.max < 3400

      # Check total travel time
      assert solutions[0].routes[0].info.total_travel_time < 23000,
             "Too long travel time: #{solutions[0].routes[0].info.total_travel_time}"
    end

    # Lyon - 65 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_ortools_one_route_with_rest
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal 1, solutions[0].routes.size

      # Check stops
      assert_equal check_vrp_services_size + 2 + 1, solutions[0].routes[0].stops.size

      # Check total travel time
      assert solutions[0].routes[0].info.total_travel_time < 25000,
             "Too long travel time: #{solutions[0].routes[0].info.total_travel_time}"

      # Check rest position
      rest_position = solutions[0].routes[0].stops.index(&:rest_id)
      assert rest_position > 10 && rest_position < vrp.services.size - 10,
             "Bad rest position: #{rest_position}"

      # Check elapsed time
      assert solutions[0].elapsed < 4000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Mont-de-Marsan - 61 services with time window + rest - dimension time car - late for services & vehicles
    def test_ortools_one_route_with_rest_and_waiting_time
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal 1, solutions[0].routes.size

      # Check total travel time
      assert_operator solutions[0].routes.sum{ |r| r[:total_travel_time] }, :<=, 5394, 'Too long travel time'
      # Check stops
      assert_equal check_vrp_services_size + 2 + 1, solutions[0].routes[0].stops.size
      # Check elapsed time
      assert solutions[0].elapsed < 35000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Lyon - 769 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_vrp_ten_routes_with_rest
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size

      # imitate old lateness functionality (i.e., there is no limit on the maximum lateness)
      # maximum_lateness of the vehicle is increased to have the result with the old functionality
      vrp.vehicles.each{ |v| v.timewindow.maximum_lateness = 5 * 60 * 60 }

      # or-tools performance
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, Marshal.load(Marshal.dump(vrp)), nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }
      services_by_routes.each{ |k, v|
        assert_equal v.size, solutions[0].routes.find{ |r| r.vehicle.id == k[0] }.stops.count(&:service_id)
      }

      # Check routes
      assert_equal vrp.vehicles.size,
                   (solutions[0].routes.count{ |r| r.stops.count(&:service_id).positive? })

      # Check total travel time
      assert_operator solutions[0].routes.sum{ |r| r.info.total_travel_time }, :<=,
                      42587, 'Too long travel time'

      # Check elapsed time
      assert solutions[0].elapsed < 420000, "Too long elapsed time: #{solutions[0].elapsed}"

      # vroom performance
      vrp.vehicles.each{ |v|
        v.cost_late_multiplier = 0
        v.timewindow&.end += 5 * 60 * 60
      }
      solutions = OptimizerWrapper.wrapper_vrp('vroom', { services: { vrp: [:vroom] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size,
                   (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }
      services_by_routes.each{ |k, v|
        assert_equal v.size, solutions[0].routes.find{ |r| r.vehicle.id == k[0] }.stops.count(&:service_id)
      }

      # Check routes
      assert_equal vrp.vehicles.size,
                   (solutions[0].routes.count{ |r| r.stops.count(&:service_id).positive? })

      # Check total travel time
      assert_operator solutions[0].routes.sum{ |r| r.info.total_travel_time }, :<=,
                      42587, 'Too long travel time'

      # Check elapsed time
      assert solutions[0].elapsed < 6000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Lille - 141 services with time window and quantity - no late for services
    def test_ortools_global_six_routes_without_rest
      vrp = TestHelper.load_vrp(self)

      # imitate old lateness functionality (i.e., there is no limit on the maximum lateness)
      # maximum_lateness of the vehicle is increased to have the result with the old functionality
      vrp.vehicles.each{ |v| v.timewindow.maximum_lateness = 3 * 60 * 60 }

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check routes
      assert_equal vrp.vehicles.size,
                   (solutions[0].routes.count{ |r| r.stops.count{ |a| a[:service_id] }.positive? })

      # Check total travel time
      assert_operator solutions[0].routes.sum{ |r| r.info.total_travel_time }, :<=,
                      59959, 'Too long travel time'

      # Check stops
      stops = solutions[0].routes.sum{ |r| r.stops.count(&:service_id) }
      assert stops > 140, "Not enough stops: #{stops}"

      # Check elapsed time
      assert_operator solutions[0].elapsed, :<=, 26500, 'Too long elapsed time'
    end

    # Bordeaux - 81 services with time window - late for services & vehicles
    def test_ortools_global_ten_routes_without_rest
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size,
                   (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })

      # Check routes
      assert_operator solutions[0].routes.count{ |r| r.stops.count(&:service_id).positive? }, :<=, 4

      # Check total travel time
      assert solutions[0].routes.sum{ |r| r.info.total_travel_time } < 31700,
             "Too long travel time: #{solutions[0].routes.sum{ |r| r.info.total_travel_time }}"

      # Check elapsed time
      assert solutions[0].elapsed < 35000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Angers - Route duration and vehicle timewindow are identical
    def test_ortools_global_with_identical_route_duration_and_vehicle_window
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]

      # Check stops
      assert(solutions[0].unassigned.one? { |un| un.service_id == 'service35' })
      assert(solutions[0].unassigned.one? { |un| un.service_id == 'service83' })
      assert(solutions[0].unassigned.one? { |un| un.service_id == 'service84' })
      assert(solutions[0].unassigned.one? { |un| un.service_id == 'R1169' })
      assert(solutions[0].unassigned.one? { |un| un.service_id == 'R1183' })
      assert_operator solutions[0].unassigned.size, :<=, 6

      assert_equal check_vrp_services_size,
                   (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) } + solutions[0].unassigned.size)

      # Check routes
      assert_equal 29, (solutions[0].routes.count{ |r| r.stops.count(&:service_id).positive? })

      # Check total times
      assert_operator solutions[0].routes.sum{ |r| r.info.total_travel_time }, :<=,
                      206065, 'Too long travel time'
      assert_operator solutions[0].routes.sum{ |r| r.info.total_time }, :<=,
                      449970, 'Too long total time'

      # Check elapsed time
      assert solutions[0].elapsed < 8000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # La Roche-Sur-Yon - A single route with a single double timewindow
    def test_ortools_one_route_with_single_mtws
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count{ |a| a[:service_id] } } +
                                            solutions[0].unassigned.size)
      assert_equal 1, solutions[0].unassigned.count(&:reason)

      # Check total travel time
      assert_operator solutions[0].routes.sum{ |r| r.info.total_travel_time }, :<=,
                      6381, 'Too long travel time'

      # Check elapsed time
      assert solutions[0].elapsed < 7000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Haute-Savoie - A single route with a visit with 2 open timewindows (0 ; x] [y ; ∞)
    def test_ortools_open_timewindows
      vrp = TestHelper.load_vrp(self)
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      # Check stops
      service_with_endless_tw = vrp.services[15]
      stop_with_endless_tw = solutions[0].routes[0].stops.find{ |stop|
        stop.service_id == service_with_endless_tw.id # service_with_endless_tw
      }
      endless_tw_respected = stop_with_endless_tw.activity.timewindows.one?{ |tw|
        stop_with_endless_tw.info.begin_time >= (tw.start || 0) &&
          stop_with_endless_tw.info.begin_time <= (tw.end || Float::INFINITY)
      }
      assert endless_tw_respected, 'Service does not respect endless TW'
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })

      # Check total travel time
      assert solutions[0].routes.sum{ |r| r.info.total_travel_time } <= 13225,
             "Too long travel time: #{solutions[0].routes.sum{ |r| r.info.total_travel_time }}"

      # Check elapsed time
      # The rework of time horizon in optimizer-ortools has decreased the computation time drastically
      assert solutions[0].elapsed < 1000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Nantes - A single route with an order defining the most part of the route
    def test_ortools_single_route_with_route_order
      vrp = TestHelper.load_vrp(self)
      # Letting lateness and wide horizon has bad impact on performances
      vrp.vehicles.each{ |v| v.cost_late_multiplier = 0 }
      check_vrp_services_size = vrp.services.size
      # TODO: move to fixtures at the next update of the dump
      vrp.preprocessing_prefer_short_segment = false
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count{ |a| a[:service_id] } })
      expected_ids = vrp.relations.first.linked_ids
      actual_route = solutions[0].routes.first.stops.map(&:service_id).compact

      route_order = actual_route.select{ |service_id| expected_ids.include?(service_id) }
      # Check solution order
      assert_equal expected_ids, route_order

      # Check total travel time
      assert solutions[0].routes.sum{ |r| r.info.total_travel_time } <= 12085,
             "Too long travel time: #{solutions[0].routes.sum{ |r| r.info.total_travel_time }}"

      # Check elapsed time
      assert solutions[0].elapsed < 65000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Nice - A single route with an order defining the most part of the route, many stops
    def test_ortools_single_route_with_route_order_2
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal vrp.services.size, (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })

      expected_ids = vrp.relations.first.linked_ids
      actual_route = solutions[0].routes.first.stops.map(&:service_id)

      route_order = actual_route.select{ |service_id| expected_ids.include?(service_id) }
      # Check solution order
      assert_equal expected_ids, route_order

      # Check total travel time
      assert solutions[0].routes.sum{ |r| r.info.total_travel_time } < 13500,
             "Too long travel time: #{solutions[0].routes.sum{ |r| r.info.total_travel_time }}"

      # Check elapsed time
      assert solutions[0].elapsed < 35000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Bordeaux - route  with transmodality point
    def test_ortools_multimodal_route
      vrp = TestHelper.load_vrp(self)
      skip "Multimodal implementation might be making a hard copy instead of a soft one.
            and it losses the connection between vrp.points and vrp.services[#].activity.point._blankslate_as_name.
            Gwen said he will fix it."
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools, :ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })
      assert solutions[0].routes.sum{ |r| r.stops.count{ |a| a.info.point.id == 'Park_eugene_leroy' } } >= 2

      # Check total cost
      assert solutions[0].cost < 6800, "Cost is to high: #{solutions[0].cost}"

      # Check elapsed time
      assert solutions[0].elapsed < 35000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Bordeaux - route with transmodality point
    def test_ortools_multimodal_route2
      vrp = TestHelper.load_vrp(self)
      skip "Multimodal implementation might be making a hard copy instead of a soft one.
            and it losses the connection between vrp.points and vrp.services[#].activity.point._blankslate_as_name.
            Gwen said he will fix it."
      check_vrp_services_size = vrp.services.size
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools, :ortools] }}, vrp, nil)
      assert solutions[0]
      # Check stops
      assert_equal check_vrp_services_size, (solutions[0].routes.sum{ |r| r.stops.count(&:service_id) })
      assert solutions[0].routes.sum{ |r| r.stops.count{ |a| a.info.point.id == 'Park_thiers' } } >= 2

      # Check total cost
      assert solutions[0][:cost] < 7850, "Cost is to high: #{solutions[0][:cost]}"

      # Check elapsed time
      assert solutions[0].elapsed < 10000, "Too long elapsed time: #{solutions[0].elapsed}"
    end

    # Paris - Multiple independent routes
    def test_ortools_optimize_each
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      assert_equal 5, solutions[0].routes.size
    end

    def test_dichotomious_check_number_of_services
      # TODO: This test is an old test left here. It doesn't have enough vehicles.
      # It just check if we lose or add services.
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)

      routes = solutions[0].routes
      unassigned = solutions[0].unassigned

      result_num = {
        points: routes.flat_map{ |route| route.stops.map{ |act| act.activity.point.id } } +
                unassigned.map{ |un| un.activity.point.id },
        services: routes.flat_map{ |route| route.stops.select{ |act| act.type == :service && act.service_id } } +
                  unassigned.select{ |act| act.type == :service && act.service_id },
        shipments: routes.flat_map{ |route|
          route.stops.select{ |act| act.delivery_shipment_id || act.pickup_shipment_id }
        } + unassigned.select{ |un| un.delivery_shipment_id || un.pickup_shipment_id },
        rests: routes.flat_map{ |route| route.stops.select(&:rest_id) } +
               unassigned.select(&:rest_id),
      }

      result_num.each{ |k, v|
        v.compact!
        v.uniq!
        result_num[k] = v.size
      }
      %i[services shipments rests].each { |type|
        if vrp[type].nil?
          assert result_num[type].zero?, "Created additional #{type}"
        else
          assert_operator result_num[type], :<=, vrp[type].size, "Created additional #{type}"
          assert_operator result_num[type], :>=, vrp[type].size, "Lost some #{type}"
        end
      }
      assert_operator result_num[:points], :<=, vrp[:points].size, 'Created additional points'
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_g1g2
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimum_duration = 8000
      vrp.resolution_duration = 600000
      vrp.restitution_intermediate_solutions = false

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      total_return_distance = solutions[0].routes.sum{ |route| route.stops.last.info.travel_distance }
      assert solutions[0]
      assert solutions[0].info.total_distance - total_return_distance <= 85100
      assert solutions[0].unassigned.size <= 6
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_hv11
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimum_duration = 40000
      vrp.resolution_duration = 600000
      vrp.restitution_intermediate_solutions = false

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      total_return_distance = solutions[0].routes.sum{ |route| route.stops.last.info.travel_distance }
      assert solutions[0]
      assert solutions[0].info.total_distance - total_return_distance <= 183800
      assert_equal 0, solutions[0].unassigned.size
    end

    # North West of France - at the fastest with distance minimization
    def test_instance_fr_tv1
      vrp = TestHelper.load_vrp(self)
      vrp.resolution_minimum_duration = 30000
      vrp.resolution_duration = 600000
      vrp.restitution_intermediate_solutions = false

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      assert solutions[0]
      assert solutions[0].info.total_distance <= 97400
      assert_equal 0, solutions[0].unassigned.size
    end

    # North West of France - at the fastest with distance minimization with vehicle returning at the depot
    def test_instance_fr_tv11
      vrp = TestHelper.load_vrp(self, fixture_file: 'instance_fr_tv1')
      vrp.resolution_minimum_duration = 8000
      vrp.resolution_duration = 600000
      vrp.restitution_intermediate_solutions = false

      vrp.vehicles.first.end_point = vrp.vehicles.first.start_point
      vrp.vehicles.first.end_point_id = vrp.vehicles.first.start_point_id

      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      total_return_distance = solutions[0].routes.sum{ |route| route.stops.last.info.travel_distance }
      assert solutions[0]
      assert solutions[0].info.total_distance - total_return_distance <= 105700
      assert_equal 0, solutions[0].unassigned.size
    end

    # Paris - Multiple independent routes
    def test_vroom_optimize_each
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:vroom] }}, vrp, nil)
      assert solutions[0]
      assert_equal 5, solutions[0].routes.size
    end

    def test_vroom_one_vehicle_is_not_needed
      vrp = TestHelper.load_vrp(self)
      solutions = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:vroom] }}, vrp, nil)
      assert_equal 5, solutions[0].routes.size
    end
  end
end
