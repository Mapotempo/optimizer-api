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

class Api::V01::RequestHelper < Minitest::Test
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def wait_status(job_id, status, options)
    puts "#{job_id} #{Time.now} waiting #{status} status"
    loop do
      sleep 0.5
      get "0.1/vrp/jobs/#{job_id}.json", options

      puts "Empty response body: #{JSON.parse(last_response.body)}" if JSON.parse(last_response.body).nil? || JSON.parse(last_response.body)['job'].nil?

      break if JSON.parse(last_response.body)['job']['status'] == status

      assert_equal 206, last_response.status, last_response.body
    end
    puts "#{job_id} #{Time.now} got #{status} status"
    sleep 0.5
    JSON.parse(last_response.body)
  end

  def wait_status_csv(job_id, status, options)
    puts "#{job_id} #{Time.now} waiting #{status} status_csv"
    loop do
      sleep 0.5
      get "0.1/vrp/jobs/#{job_id}", options

      break if last_response.status == status

      assert_equal 206, last_response.status, last_response.body
    end
    puts "#{job_id} #{Time.now} got #{status} status_csv"
    sleep 0.5
  end

  def submit_vrp(params)
    hex = Digest::MD5.hexdigest params.to_s
    puts "#{hex} #{Time.now} submiting #{hex}"
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      puts "#{job_id} #{Time.now} submitted #{hex}"
      job_id
    else
      response = JSON.parse(last_response.body)
      puts "#{job_id} #{Time.now} submitted #{hex} but it returned a result"
      assert response['job']['status']['completed'] || response['job']['status']['queued']
    end
  end

  def submit_csv(params)
    hex = Digest::MD5.hexdigest params.to_s
    puts "#{hex} #{Time.now} submiting_csv #{hex}"
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      puts "#{job_id} #{Time.now} submitted_csv #{hex}"
      job_id
    else
      response = last_response.body.slice(1..-1).split('\n').map{ |line| line.split(',') }
      puts "#{job_id} #{Time.now} submitted_csv #{hex} but it returned a result"
      response
    end
  end

  def delete_job(job_id, params)
    puts "#{job_id} #{Time.now} sending delete"
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 202, last_response.status, last_response.body
    puts "#{job_id} #{Time.now} delete done"
  end

  def delete_completed_job(job_id, params)
    puts "#{job_id} #{Time.now} sending delete_completed"
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 404, last_response.status, last_response.body
    puts "#{job_id} #{Time.now} delete_completed done"
  end
end
