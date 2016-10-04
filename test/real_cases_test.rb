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

    #   # Check total distance
    #   assert result[:total_distance] < ***, "Too long distance: #{result[:total_distance]}"
    # end

    def test_ortools_one_route_without_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2, result[:routes][0][:activities].size

      # Check total distance
      assert result[:total_distance] < 150000, "Too long distance: #{result[:total_distance]}"

      # Check elapsed time
      assert result[:elapsed] < 3150, "Too long elapsed time: #{result[:elapsed]}"
    end

    def test_ortools_one_route_with_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
      assert result

      # Check routes
      assert_equal 1, result[:routes].size

      # Check activities
      assert_equal vrp.services.size + 2 + 1, result[:routes][0][:activities].size

      # Check total time
      v = vrp.vehicles.find{ |v| v.id == result[:routes][0][:vehicle_id] }
      previous = nil
      total_travel_time = result[:routes][0][:activities].sum{ |a|
        point_id = a[:point_id] ? a[:point_id] : a[:service_id] ? vrp.services.find{ |s|
          s.id == a[:service_id]
        }.activity.point_id : nil
        if point_id
          point = vrp.points.find{ |p| p.id == point_id }.matrix_index
          if previous && point
            a[:travel_time] = v.matrix.time[previous][point]
          end
        end
        previous = point
        a[:travel_time] || 0
      }
      assert total_travel_time < 25000, "Too long travel time: #{total_travel_time}"

      # Check rest position
      rest_position = result[:routes][0][:activities].index{ |a| a[:rest_id] }
      assert rest_position > 10 && rest_position < 20, "Bad rest position"

      # Check elapsed time
      assert result[:elapsed] < 4000, "Too long elapsed time: #{result[:elapsed]}"
    end

    # def test_ortools_ten_routes_with_rest
    #   vrp = ENV['DUMP_VRP'] ? 
    #     Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
    #     Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
    #   result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
    #   assert result

    #   # Check activities
    #   assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)
    #   services_by_routes = vrp.services.group_by{ |s| s.sticky_vehicles }
    #   services_by_routes.each{ |k, v|
    #     assert_equal v.size, result[:routes].find{ |r| r[:vehicle_id] == k[0] }[:activities].select{ |a| a[:service_id] }.size
    #   }

    #   # Check routes
    #   assert_equal vrp.vehicles.size, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

    #   # Check elapsed time
    #   assert result[:elapsed] < 40000, "Too long elapsed time: #{result[:elapsed]}"
    # end

    def test_ortools_global_ten_routes_without_rest
      vrp = ENV['DUMP_VRP'] ? 
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp)
      assert result

      # Check activities
      assert_equal vrp.services.size, result[:routes].map{ |r| r[:activities].select{ |a| a[:service_id] }.size }.reduce(&:+)

      # Check routes
      assert_equal vrp.vehicles.size, result[:routes].select{ |r| r[:activities].select{ |a| a[:service_id] }.size > 0 }.size

      # Check elapsed time
      assert result[:elapsed] < 300000, "Too long elapsed time: #{result[:elapsed]}"
    end
  end

end
