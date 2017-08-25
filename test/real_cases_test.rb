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
    #   vrp = ENV['DUMP_VRP'] ? 
    #     Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
    #     Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
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
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total distance
      assert result[:total_distance] < 150000, "Too long distance: #{result[:total_distance]}"

      # Check elapsed time
      assert result[:elapsed] < 10000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Strasbourg - 107 services with few time windows - dimension distance car - late for services & vehicles
    def test_ortools_one_route_without_rest_2
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total distance
      assert result[:total_distance] < 265000, "Too long distance: #{result[:total_distance]}"

      # Check elapsed time
      assert result[:elapsed] < 10000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Béziers - 203 services with time window - dimension time car - late for services & vehicles - force start and no wait cost
    def test_ortools_one_route_many_stops
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total travel time
      assert result[:routes][0][:total_travel_time] < 21050, "Too long travel time: #{result[:routes][0][:total_travel_time]}"

      # Check elapsed time
      assert result[:elapsed] < 60000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lyon - 65 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_ortools_one_route_with_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2 + 1, result[:routes][0][:activities].size

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
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 4900, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"
      # Check activities
      assert_equal vrp.services.size + 2 + 1, result[:routes][0][:activities].size
      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lyon - 769 services (without tw) + rest - dimension time car_urban - late for services & vehicles
    def test_ortools_ten_routes_with_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      # Check activities
      assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }
      services_by_routes.each{ |k, v|
        assert_equal v.size, result[:routes].find{ |r| r[:vehicle_id] == k[0] }[:activities].select{ |a| a[:service_id] }.size
      }

      # Check routes
      assert_equal vrp.vehicles.size, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 42300, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 420000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Lille - 141 services with time window and quantity - no late for services
    def test_ortools_global_six_routes_without_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check routes
      assert_equal (vrp.vehicles.size - 1), result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 35000, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check activities
      activities = result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      assert 140 < activities, "Not enough activities: #{activities}"

      # Check elapsed time
      assert result[:elapsed] < 30000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Bordeaux - 81 services with time window - late for services & vehicles
    def test_ortools_global_ten_routes_without_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      # Check activities
      assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)

      # Check routes
      assert_equal 4, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 31700, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 35000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # Angers - Route duration and vehicle timewindow are identical
    def test_ortools_global_with_identical_route_duration_and_vehicle_window
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result

      # Check activities
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service35'}
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service83'}
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service84'}
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'service88' || unassigned[:service_id] == 'service89' }
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'R1169'}
      assert result[:unassigned].one? { |unassigned| unassigned[:service_id] == 'R1183'}
      assert_equal vrp.services.size - 6, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)

      # Check routes
      assert_equal 29, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 176000, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 8000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # La Roche-Sur-Yon - A single route with a single double timewindow
    def test_ortools_one_route_with_single_mtws
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      # Check activities
      assert_equal vrp.services.size - 1, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
      services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles.map(&:id) }

      # Check total travel time
      assert result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+) < 6300, "Too long travel time: #{result[:routes].map{ |r| r[:total_travel_time]}.reduce(&:+)}"

      # Check elapsed time
      assert result[:elapsed] < 7000, "Too long elapsed time: #{result[:elapsed]}"
    end
  end

end
