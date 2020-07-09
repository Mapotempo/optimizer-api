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
    loop do
      get "0.1/vrp/jobs/#{job_id}.json", options
      sleep 1

      break if JSON.parse(last_response.body)['job']['status'] == status

      assert_equal 206, last_response.status, last_response.body
    end
    JSON.parse(last_response.body)
  end

  def wait_status_csv(job_id, status, options)
    loop do
      get "0.1/vrp/jobs/#{job_id}", options
      sleep 1

      break if last_response.status == status

      assert_equal 206, last_response.status, last_response.body
    end
  end

  def submit_vrp(params)
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      job_id
    else
      response = JSON.parse(last_response.body)
      assert response['job']['status']['completed'] || response['job']['status']['queued']
    end
  end

  def submit_csv(params)
    post '/0.1/vrp/submit', params.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_includes [200, 201], last_response.status
    assert last_response.body
    if last_response.status == 201
      job_id = JSON.parse(last_response.body)['job']['id']
      assert job_id
      job_id
    else
      response = last_response.body.slice(1..-1).split('\n').map{ |line| line.split(',') }
      response
    end
  end

  def delete_job(job_id, params)
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 202, last_response.status, last_response.body
  end

  def delete_completed_job(job_id, params)
    delete "0.1/vrp/jobs/#{job_id}.json", params
    assert_equal 404, last_response.status, last_response.body
  end
end
