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

class OutputTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def test_day_week_num
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = {
      points: [{
        id: 'point_0',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        router_mode: :car,
        timewindow: {
          start: 0,
          end: 20
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        }
      }],
      configuration: {
        resolution: {
          duration: 10,
          solver: false
        },
        preprocessing: {
          first_solution_strategy: ['periodic']
        },
        schedule: {
          range_indices: {
            start: 0,
            end: 3
          }
        },
        restitution: {
          csv: true
        }
      }
    }

    post '/0.1/vrp/submit', { api_key: 'ortools', vrp: vrp }
    assert_equal 201, last_response.status, last_response.body
    job_id = JSON.parse(last_response.body)['job']['id']
    get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
      begin
        JSON.parse(last_response.body)['job']['status']
      rescue
        break
      end
    end
    csv_data = JSON.parse(last_response.body).split("\n").map{ |line| line.split(',') }
    assert_equal csv_data.collect{ |line| line.size }.max, csv_data.collect{ |line| line.size }.first
    assert csv_data.first.include?('day_week')
    assert csv_data.first.include?('day_week_num')
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
    delete "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
  end

  def test_no_day_week_num
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = {
      points: [{
        id: 'point_0',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        router_mode: :car,
        timewindow: {
          start: 0,
          end: 20
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        }
      }],
      configuration: {
        resolution: {
          duration: 10
        },
        restitution: {
          csv: true
        }
      }
    }

    post '/0.1/vrp/submit', { api_key: 'ortools', vrp: vrp }
    assert_equal 201, last_response.status, last_response.body
    job_id = JSON.parse(last_response.body)['job']['id']
    get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
      begin
        JSON.parse(last_response.body)['job']['status']
      rescue
        break
      end
    end
    csv_data = JSON.parse(last_response.body).split("\n").map{ |line| line.split(',') }
    assert_equal csv_data.collect{ |line| line.size }.max, csv_data.collect{ |line| line.size }.first
    assert !csv_data.first.include?('day_week')
    assert !csv_data.first.include?('day_week_num')
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
    delete "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
  end

  def test_skill_when_partitions
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false

    vrp = {
      points: [{
        id: 'point_0',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        router_mode: :car,
        timewindow: {
          start: 0,
          end: 20
        },
        duration: 6
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1'
        }
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        }
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        }
      }],
      configuration: {
        preprocessing: {
          partitions: [{
            method: 'balanced_kmeans',
            metric: 'duration',
            entity: 'vehicle'
          }]
        },
        resolution: {
          duration: 10
        },
        restitution: {
          csv: true
        }
      }
    }

    post '/0.1/vrp/submit', { api_key: 'ortools', vrp: vrp }
    assert_equal 201, last_response.status, last_response.body
    job_id = JSON.parse(last_response.body)['job']['id']
    get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
    while last_response.body
      sleep(1)
      assert_equal 206, last_response.status, last_response.body
      get "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
      begin
        JSON.parse(last_response.body)['job']['status']
      rescue
        break
      end
    end
    csv_data = JSON.parse(last_response.body).split("\n").map{ |line| line.split(',') }
    assert_equal csv_data.collect{ |line| line.size }.max, csv_data.collect{ |line| line.size }.first
    assert csv_data.select{ |line| line[csv_data.first.find_index('type')] == 'visit' }.all?{ |line| !line[csv_data.first.find_index('skills')].nil? }
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
    delete "0.1/vrp/jobs/#{job_id}.json", { api_key: 'demo'}
  end
end