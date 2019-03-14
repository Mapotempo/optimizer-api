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

class HeuristicTest < Minitest::Test

  if !ENV['SKIP_REAL_SCHEDULING']

    def test_instance_baleares2
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert result[:unassigned].size <= 3
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_baleares2_with_priority
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert result[:unassigned].none?{ |service| service[:service_id].include?('3359') }
      assert result[:unassigned].none?{ |service| service[:service_id].include?('0110') }
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum  + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_andalucia2
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal 22, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0][:value] }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0][:value] }.sum, vrp.services.collect{ |service| service[:quantities][0][:value] }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.size, (result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } } + result[:unassigned].collect{ |unassigned| unassigned[:service_id] }).flatten.compact.uniq.size
    end

    def test_instance_andalucia1_two_vehicles
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal 0, result[:unassigned].size
      assert_equal vrp[:services].size, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum
      assert_equal result[:routes].collect{ |route| route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity| activity[:detail][:quantities][0] ? activity[:detail][:quantities][0][:value] : 0 }.sum }.sum + result[:unassigned].collect{ |unassigned| unassigned[:detail][:quantities][0] ? unassigned[:detail][:quantities][0][:value] : 0 }.sum, vrp.services.collect{ |service| service[:quantities][0] ? service[:quantities][0][:value] : 0 }.sum
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities][0][:value] }.sum > vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] }[:capacities][0][:limit] }
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_800unaffected_clustered
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal vrp[:services].collect{ |service| service[:visits_number] }.sum.to_i, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.flatten.compact.sum).round(3)
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'kg' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'qte' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'l' }[:limit]}
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end

    def test_instance_800unaffected_clustered_same_point
      vrp = ENV['DUMP_VRP'] ?
        Models::Vrp.create(Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp'])) :
        Marshal.load(Base64.decode64(File.open('test/fixtures/' + self.name[5..-1] + '.dump').to_a.join))
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      assert result
      assert_equal vrp[:services].collect{ |service| service[:visits_number] }.sum.to_i, result[:routes].collect{ |route| route[:activities].select{ |stop| stop[:service_id] }.size }.sum + result[:unassigned].size
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.flatten.compact.sum).round(3)
      assert_equal vrp.services.collect{ |service| service[:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value]*service[:visits_number] }.sum.round(3), (result[:routes].collect{ |route| route[:activities].collect{ |stop| stop[:service_id] && stop[:detail][:quantities].size > 0 && stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }}.flatten.compact.sum.round(3) + result[:unassigned].collect{ |service| service[:detail][:quantities].size > 0 && service[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.flatten.compact.sum).round(3)
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'kg' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'kg' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'qte' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'qte' }[:limit]}
      assert result[:routes].none?{ |route| route[:activities].reject{ |stop| stop[:detail][:quantities].empty? }.collect{ |stop| stop[:detail][:quantities].find{ |qte| qte[:unit][:id] == 'l' }[:value] }.sum > vrp[:vehicles].find{ |vehicle| vehicle[:id] == route[:vehicle_id].split('_')[0] }[:capacities].find{ |cap| cap[:unit_id] == 'l' }[:limit]}
      assert_equal result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.size, result[:routes].collect{ |route| route[:activities].collect{ |activity| activity[:service_id] } }.flatten.compact.uniq.size
    end
  end
end
