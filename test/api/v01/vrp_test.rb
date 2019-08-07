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
require './api/root'

require './test/api/v01/request_helper'

class Api::V01::VrpTest < Api::V01::RequestHelper
  include Rack::Test::Methods

  def app
    Api::Root
  end

  # Unit tests
  def test_submit_vrp_in_queue
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_submit_vrp
    post '/0.1/vrp/submit', api_key: '!', vrp: VRP.toy
    assert_equal 401, last_response.status, last_response.body
  end

  def test_exceed_params_limit
    vrp = VRP.toy
    vrp[:points] *= 151
    post '/0.1/vrp/submit', api_key: 'vroom', vrp: vrp
    assert_equal 400, last_response.status, last_response.body
  end

  def test_ignore_unknown_parameters
    vrp = VRP.toy
    vrp[:points][0][:unknown_parameter] = 'test'
    vrp[:configuration][:unknown_parameter] = 'test'
    vrp[:unknown_parameter] = 'test'
    submit_vrp api_key: 'demo', vrp: vrp
  end

  def test_time_parameters
    vrp = VRP.toy
    vrp[:vehicles][0][:duration] = '12:00'
    vrp[:services][0][:activity] = {
      point_id: 'p1',
      duration: '00:20:00',
      timewindows: [{
        start: 80,
        end: 800.0
      }]
    }
    OptimizerWrapper.stub(:wrapper_vrp,
      lambda { |_api_key, _services, vrp, _checksum|
        assert_equal 12 * 3600, vrp.vehicles.first.duration
        assert_equal 20 * 60, vrp.services.first.activity.duration
        assert_equal 80, vrp.services.first.activity.timewindows.first.start
        assert_equal 800, vrp.services.first.activity.timewindows.first.end
        'job_id'
      }
    ) do
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_null_value_matrix
    vrp = VRP.basic
    vrp[:matrices].first[:value] = nil

    post '/0.1/vrp/submit', api_key: 'demo', vrp: vrp
    assert_equal 400, last_response.status, last_response.body
  end

  def test_first_solution_strategie_param
    vrp = VRP.toy
    vrp[:configuration].merge!(preprocessing: { first_solution_strategy: 'a, b ' })
    OptimizerWrapper.stub(:wrapper_vrp,
      lambda { |_api_key, _services, vrp, _checksum|
        assert_equal ['a', 'b'], vrp.preprocessing_first_solution_strategy
        'job_id'
      }
    ) do
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_list_vrp
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'demo'
    assert_equal 200, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_list_vrp
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'vroom'
    assert_equal 200, last_response.status, last_response.body
    refute_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_get_vrp
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get "/0.1/vrp/jobs/#{@job_id}", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_delete_vrp
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete_job @job_id, api_key: 'demo'
    assert_equal 202, last_response.status, last_response.body
    get "0.1/vrp/jobs/#{@job_id}.json", api_key: 'demo'
    assert_equal 404, last_response.status, last_response.body
    assert_equal JSON.parse(last_response.body)['status'], 'Not Found'
  end

  def test_cannot_delete_vrp
    FCT.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete "0.1/vrp/jobs/#{@job_id}.json", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
  ensure
    delete_job @job_id, api_key: 'demo'
  end
end
