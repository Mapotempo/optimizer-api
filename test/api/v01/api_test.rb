# Copyright © Mapotempo, 2020
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
require './test/api/v01/helpers/count_helper'

class Api::V01::ApiTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    Api::Root
  end

  def test_should_not_access
    get '/0.1/vrp/submit'
    assert_equal 401, last_response.status
    assert_equal 'Unauthorized', JSON.parse(last_response.body)['error']
  end

  def test_unauthorized_api_key
    post '/0.1/vrp/submit', api_key: '!', vrp: VRP.toy
    assert_equal 401, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['error'], 'Unauthorized'
  end

  def test_should_not_access_if_expired
    get '/0.1/vrp/submit', api_key: 'expired'
    assert_equal 402, last_response.status
    assert_equal 'Subscription expired. Please contact support (support@mapotempo.com) or sales (sales@mapotempo.com) to extend your access period.', JSON.parse(last_response.body)['error']
  end

  def test_count_optimizations
    clear_optim_redis_count
    [
      { method: 'post', uri: 'submit', operation: :optimize, options: { vrp: VRP.toy }},
      { method: 'get', uri: "jobs/#{@job_id}.json", operation: :get_job, options: {}},
      { method: 'get', uri: 'jobs', operation: :get_job_list, options: {}},
      { method: 'delete', uri: "jobs/#{@job_id}.json", operation: :delete_job, options: {}} # delete must be the last one!
    ].each do |obj|
      (1..2).each do |cpt|
        send(obj[:method], "/0.1/vrp/#{obj[:uri]}", { api_key: 'demo' }.merge(obj[:options]))

        keys = OptimizerWrapper.config[:redis_count].keys("optimizer:#{obj[:operation]}:#{Time.now.utc.to_s[0..9]}_key:demo_ip*")

        case obj[:operation]
        when :optimize
          assert_equal 1, keys.count
          assert_equal({ 'hits' => cpt.to_s, 'transactions' => (VRP.toy[:vehicles].count * VRP.toy[:points].count * cpt).to_s }, OptimizerWrapper.config[:redis_count].hgetall(keys.first)) # only one key
        else
          assert_equal 0, keys.count
        end
      end
    end
  end

  def test_use_quota
    clear_optim_redis_count
    post '/0.1/vrp/submit', { api_key: 'quota', vrp: VRP.basic }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert last_response.ok?, last_response.body

    post '/0.1/vrp/submit', { api_key: 'quota', vrp: VRP.basic }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_equal 429, last_response.status

    assert_includes JSON.parse(last_response.body)['message'], 'Too many daily requests'
    assert_equal ["application/json; charset=UTF-8", 4, 0, Time.now.utc.to_date.next_day.to_time.to_i], last_response.headers.select{ |key|
      key =~ /(Content-Type|X-RateLimit-Limit|X-RateLimit-Remaining|X-RateLimit-Reset)/
    }.values
  end

  def test_use_specific_router_api_key
    s = stub_request(:post, %r{/0.1/matrix.json})
        .with(body: hash_including(api_key: 'other_key', mode: 'pedestrian', dimension: 'distance_time'))
        .to_return(status: 200, body: {
          matrix_time: [
            [1] * 3, [1] * 3, [1] * 3,
          ], matrix_distance: [
            [1] * 3, [1] * 3, [1] * 3,
          ]
        }.to_json)
    vrp = {
      points: [{
        id: 'point_0',
        location: { lat: 1, lon: 2 }
      }, {
        id: 'point_1',
        location: { lat: 2, lon: 3 }
      }, {
        id: 'point_2',
        location: { lat: 3, lon: 4 }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        router_mode: 'pedestrian', router_dimension: 'distance'
      }],
      services: [{
        id: 'service_1',
        activity: { point_id: 'point_1' }
      }, {
        id: 'service_2',
        activity: { point_id: 'point_2' }
      }],
      configuration: {
        resolution: {
          duration: 1
        },
        preprocessing: {},
        restitution: {},
      }
    }
    post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_equal 200, last_response.status, last_response.body
  ensure
    remove_request_stub s
  end
end
