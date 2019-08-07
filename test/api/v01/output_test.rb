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
require './test/api/v01/request_helper'

class Api::V01::OutputTest < Api::V01::RequestHelper
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def test_day_week_num
    vrp = {
      matrices: [{
        id: 'm1',
        time: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ],
        distance: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'm1',
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

    FCT.solve_asynchronously do
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      wait_status_csv @job_id, 200, api_key: 'demo'
      csv_data = last_response.body.split("\n").map{ |line| line.split(',') }
      assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
      assert csv_data.first.include?('day_week')
      assert csv_data.first.include?('day_week_num')
    end
  ensure
    delete_completed_job @job_id, api_key: 'solvers'
  end

  def test_no_day_week_num
    vrp = {
      matrices: [{
        id: 'm1',
        time: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ],
        distance: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'm1',
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

    FCT.solve_asynchronously do
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      wait_status_csv @job_id, 200, api_key: 'demo'
      csv_data = last_response.body.split("\n").map{ |line| line.split(',') }
      assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
      assert !csv_data.first.include?('day_week')
      assert !csv_data.first.include?('day_week_num')
    end
  ensure
    delete_completed_job @job_id, api_key: 'solvers'
  end

  def test_skill_when_partitions
    vrp = {
      matrices: [{
        id: 'm1',
        time: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ],
        distance: [
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0],
          [0, 0, 0, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: {
          lat: 39.5897,
          lon: 2.6579
        }
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'm1',
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
    FCT.solve_asynchronously do
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      wait_status_csv @job_id, 200, api_key: 'demo'
      csv_data = last_response.body.split("\n").map{ |line| line.split(',') }
      assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
      assert(csv_data.select{ |line| line[csv_data.first.find_index('type')] == 'visit' }.all?{ |line| !line[csv_data.first.find_index('skills')].nil? })
    end
  ensure
    delete_completed_job @job_id, api_key: 'solvers'
  end
end
