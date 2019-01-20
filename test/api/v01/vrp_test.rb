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

require './api/root'

class Api::V01::VrpTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def simple_vrp
    {
      points: [{
        id: 'p1',
        location: {
          lat: 1,
          lon: 2
        }
      }],
      vehicles: [{
        id: 'v1',
        router_mode: 'car',
        router_dimension: 'time'
      }],
      services: [{
        id: 's1',
        type: 'service',
        activity: {
          point_id: 'p1'
        }
      }],
      configuration: {
        resolution: {
          duration: 1
        }
      }
    }
  end

  def solve_asynchronously
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false
    yield
  ensure
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
  end

  def submit_vrp(params)
    post '/0.1/vrp/submit', params
    assert 200 || 201 == last_response.status
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

  def delete_job(job_id, params)
    delete "0.1/vrp/jobs/#{@job_id}.json", api_key: 'demo'
    assert_equal 202, last_response.status, last_response.body
  end

  # Unit tests

  def test_submit_vrp_in_queue
    solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: simple_vrp
    end
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_submit_vrp
    post '/0.1/vrp/submit', api_key: '!', vrp: simple_vrp
    assert_equal 401, last_response.status, last_response.body
  end

  def test_exceed_params_limit
    vrp = simple_vrp
    vrp[:points] *= 101
    post '/0.1/vrp/submit', api_key: 'vroom', vrp: vrp
    assert_equal 400, last_response.status, last_response.body
  end

  def test_ignore_unknown_parameters
    vrp = simple_vrp
    vrp[:points][0][:unknown_parameter] = 'test'
    vrp[:configuration][:unknown_parameter] = 'test'
    vrp[:unknown_parameter] = 'test'
    submit_vrp api_key: 'demo', vrp: vrp
  end

  def test_time_parameters
    vrp = simple_vrp
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

  def test_first_solution_strategie_param
    vrp = simple_vrp
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
    solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: simple_vrp
    end

    get '/0.1/vrp/jobs', api_key: 'demo'
    assert_equal 200, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_list_vrp
    solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: simple_vrp
    end

    get '/0.1/vrp/jobs', api_key: 'vroom'
    assert_equal 200, last_response.status, last_response.body
    refute_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_delete_vrp
    solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: simple_vrp
    end

    delete_job @job_id, api_key: 'demo'
    get "0.1/vrp/jobs/#{@job_id}.json", api_key: 'demo'
    assert_equal 404, last_response.status, last_response.body
    assert_equal JSON.parse(last_response.body)['status'], 'Not Found'
  end

  def test_cannot_delete_vrp
    solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: simple_vrp
    end

    delete "0.1/vrp/jobs/#{@job_id}.json", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_real_problem_without_matrix
    vrp = {
      points: [{
        id: 'point_0',
        location: {lat: 45.288798, lon: 4.951565}
      }, {
        id: 'point_1',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_2',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_3',
        location: {lat: 45.344334, lon: 4.817731}
      }, {
        id: 'point_4',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_5',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_6',
        location: {lat: 45.2583248913, lon: 4.6873225272}
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_mode: 'car',
        router_dimension: 'distance',
      }],
      services: [{
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        type: 'service',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        type: 'service',
        activity: {
          point_id: 'point_3'
        }
      }, {
        id: 'service_4',
        type: 'service',
        activity: {
          point_id: 'point_4'
        }
      }, {
        id: 'service_5',
        type: 'service',
        activity: {
          point_id: 'point_5'
        }
      }, {
        id: 'service_6',
        type: 'service',
        activity: {
          point_id: 'point_6'
        }
      }],
    }

    post '/0.1/vrp/submit', {api_key: 'vroom', vrp: vrp}
    assert_equal 200, last_response.status, last_response.body
    assert_equal 1.upto(6).collect{ |i| "service_#{i}"}, JSON.parse(last_response.body)['solutions'][0]['routes'][0]['activities'][1..-2].collect{ |p| p['service_id'] }.sort_by{ |p| p[-1].to_i }
  end

  def test_deleted_job # The server must be running
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = {
      configuration: {
          resolution: {
            duration: 2000
          },
        },
      points: [{
        id: 'point_0',
        location: {lat: 45.288798, lon: 4.951565}
      }, {
        id: 'point_1',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_2',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_3',
        location: {lat: 45.344334, lon: 4.817731}
      }, {
        id: 'point_4',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_5',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_6',
        location: {lat: 45.2583248913, lon: 4.6873225272}
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        timewindow: {
          start: 0,
          end: 50000
        },
        router_mode: 'car',
        router_dimension: 'distance',
      }],
      services: [{
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        type: 'service',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        type: 'service',
        activity: {
          point_id: 'point_3'
        }
      }, {
        id: 'service_4',
        type: 'service',
        activity: {
          point_id: 'point_4'
        }
      }, {
        id: 'service_5',
        type: 'service',
        activity: {
          point_id: 'point_5'
        }
      }, {
        id: 'service_6',
        type: 'service',
        activity: {
          point_id: 'point_6'
        }
      }]
    }

    job_id = submit_vrp api_key: 'ortools', vrp: vrp

    get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
    previous_response = nil
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
      previous_response = last_response
      if JSON.parse(last_response.body)['job']['status'] != 'queued'
        break
      end
    end
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
    delete "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
    assert_equal 202, last_response.status, last_response.body
    assert !JSON.parse(previous_response.body)["solutions"].nil? && !JSON.parse(previous_response.body)["solutions"].empty? ||
    !JSON.parse(last_response.body)["solutions"].nil? && !JSON.parse(last_response.body)["solutions"].empty?
  end

  # Optimize each 5 routes
  def test_vroom_optimize_each
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp']
    post '/0.1/vrp/submit', {api_key: 'demo', vrp: vrp}
    assert_equal 201, last_response.status, last_response.body
    job_id = JSON.parse(last_response.body)['job']['id']
    get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
      if JSON.parse(last_response.body)['job']['status'] == 'completed'
        break
      end
    end
    result = JSON.parse(last_response.body)
    assert_equal 5, result['solutions'][0]['routes'].size

    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
  end

  # Optimize each 5 routes
  def test_ortools_optimize_each
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = JSON.parse(File.open('test/fixtures/' + self.name[5..-1] + '.json').to_a.join)['vrp']

    job_id = submit_vrp api_key: 'ortools', vrp: vrp

    get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'demo'}
      if JSON.parse(last_response.body)['job']['status'] == 'completed'
        break
      end
    end

    result = JSON.parse(last_response.body)
    assert_equal 5, result['solutions'][0]['routes'].size

    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
  end

  def test_csv_configuration
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = {
      configuration: {
          resolution: {
            duration: 500
          },
          restitution: {
            csv: true
          }
        },
      points: [{
        id: 'point_0',
        location: {lat: 45.288798, lon: 4.951565}
      }, {
        id: 'point_1',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_2',
        location: {lat: 45.6047844887, lon: 4.7589656711}
      }, {
        id: 'point_3',
        location: {lat: 45.344334, lon: 4.817731}
      }, {
        id: 'point_4',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_5',
        location: {lat: 45.5764120817, lon: 4.8056146502}
      }, {
        id: 'point_6',
        location: {lat: 45.2583248913, lon: 4.6873225272}
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        timewindow: {
          start: 0,
          end: 50000
        },
        router_mode: 'car',
        router_dimension: 'distance',
      }],
      services: [{
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        type: 'service',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        type: 'service',
        activity: {
          point_id: 'point_3'
        }
      }, {
        id: 'service_4',
        type: 'service',
        activity: {
          point_id: 'point_4'
        }
      }, {
        id: 'service_5',
        type: 'service',
        activity: {
          point_id: 'point_5'
        }
      }, {
        id: 'service_6',
        type: 'service',
        activity: {
          point_id: 'point_6'
        }
      }]
    }

    job_id = submit_vrp api_key: 'ortools', vrp: vrp

    get "0.1/vrp/jobs/#{job_id}.csv", {api_key: 'demo'}
    while last_response.status
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.csv", {api_key: 'demo'}
      if last_response.status != 206
        break
      end
    end
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
    assert_equal 200, last_response.status, last_response.body
    assert_equal 9, last_response.body.count("\n")
  end

  def test_using_two_solver
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false
    problem={
      points: [
        {
          id: 'point_0',
          location: {
            lat: 48.787021,
            lon: 2.65819
          }
        },
        {
        id: 'point_1',
            location:
            {
                lat: 48.844836,
                lon: 2.369496
            }
        },
        {
        id: 'point_2',
            location:
            {
                lat: 48.630381,
                lon: 2.437141
            }
        }
      ],
      vehicles: [
        {
            id: 'vehicle_0',
            router_mode: 'car',
            speed_multiplier: 1.0,
            start_point_id: 'point_0',
            cost_time_multiplier: 1.0,
            cost_waiting_time_multiplier: 1.0
        },
        {
            id: 'vehicle_1',
            router_mode: 'car',
            speed_multiplier: 1.0,
            cost_time_multiplier: 1.0,
            cost_waiting_time_multiplier: 1.0
        }
      ],
      services: [
        {
            id: 'service_1',
            sticky_vehicle_ids: ['vehicle_0'],

            activity:
            {
                point_id: 'point_1',
                duration: 600.0
            }
        },
        {
            id: 'service_2',
            sticky_vehicle_ids: ['vehicle_1'],
            activity:
            {
                point_id: 'point_2',
                duration: 600.0
            }
        }
      ],
      configuration: {
        resolution: {
          duration: 100,
        }
      }
    }

    post('/0.1/vrp/submit', {api_key: 'solvers', vrp: problem}, content_type: :json)
    assert_equal 201, last_response.status, last_response.body
    job_id = JSON.parse(last_response.body)['job']['id']
    get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'solvers'}
    while last_response.status
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", {api_key: 'solvers'}
      if last_response.status != 206
        break
      end
    end
    result = JSON.parse(last_response.body)
    assert_equal result['solutions'][0]['solvers'][0],'vroom'
    assert_equal result['solutions'][0]['solvers'][1],'ortools'

    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
  end
end
