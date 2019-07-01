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
require 'simplecov'
SimpleCov.start if ENV['COV']

ENV['APP_ENV'] ||= 'test'
require File.expand_path('../../config/environments/' + ENV['APP_ENV'], __FILE__)
Dir[File.dirname(__FILE__) + '/../config/initializers/*.rb'].each{ |file| require file }

Dir[File.dirname(__FILE__) + '/../models/*.rb'].each{ |file| require file }
require './optimizer_wrapper'
require './api/root'

require 'minitest/reporters'
Minitest::Reporters.use!

require 'grape'
require 'hashie'
require 'grape-swagger'
require 'grape-entity'

require 'minitest/autorun'
require 'minitest/stub_any_instance'
require 'minitest/focus'
require 'byebug'
require 'rack/test'

module FCT
  def self.create(problem)
    Models::Vrp.create(problem)
  end

  def self.load_vrp(test, options = {})
    filename = options[:fixture_file] || test.name[5..-1]
    dump_file = 'test/fixtures/' + filename + '.dump'
    if File.file?(dump_file) && !ENV['DUMP_VRP']
      Marshal.load(Base64.decode64(File.open(dump_file).to_a.join))
    else
      problem = options[:problem] || Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + filename + '.json').to_a.join)['vrp'])
      vrp = Models::Vrp.create(problem)
      # File.write(dump_file, Base64.encode64(Marshal::dump(vrp)))
      vrp.name = filename if vrp.matrices.empty?
      vrp
    end
  end

  def self.solve_asynchronously
    OptimizerWrapper.config[:solve_synchronously] = false
    Resque.inline = false
    yield
  ensure
    Resque.inline = true
    OptimizerWrapper.config[:solve_synchronously] = true
  end
end

module VRP
  def self.toy
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

  def self.basic
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 4, 5, 5],
          [6, 0, 1, 5],
          [1, 2, 0, 5],
          [5, 5, 5, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }, {
        id: 'point_3',
        matrix_index: 3
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0'
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
        preprocessing: {}
      }
    }
  end

  def self.lat_lon
    {
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
      configuration: {
        resolution: {
          duration: 2000
        }
      }
    }
  end

  def self.scheduling
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 4, 5, 5],
          [6, 0, 1, 5],
          [1, 2, 0, 5],
          [5, 5, 5, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }, {
        id: 'point_3',
        matrix_index: 3
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        timewindow: {
          start: 0,
          end: 20
        }
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
        }
      }
    }
  end

  def self.lat_lon_scheduling
    {
      units: [{
        id: 'kg'
      }],
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
        }
      }
    }
  end

  def self.lat_lon_scheduling_two_vehicles
    {
      units: [{
        id: 'kg'
      }],
      points: [{
        id: 'point_0',
        location: { lat: 45.2888, lon: 4.9515 }
      }, {
        id: 'point_1',
        location: { lat: 45.6047, lon: 4.7581 }
      }, {
        id: 'point_2',
        location: { lat: 45.6046, lon: 4.752 }
      }, {
        id: 'point_3',
        location: { lat: 45.6044, lon: 4.8171 }
      }, {
        id: 'point_4',
        location: { lat: 45.5767, lon: 4.8052 }
      }, {
        id: 'point_5',
        location: { lat: 45.5766, lon: 4.8153 }
      }, {
        id: 'point_6',
        location: { lat: 45.2583, lon: 4.6773 }
      }, {
        id: 'point_7',
        location: { lat: 45.2584, lon: 4.6674 }
      }, {
        id: 'point_8',
        location: { lat: 45.2585, lon: 4.6575 }
      }, {
        id: 'point_9',
        location: { lat: 45.2686, lon: 4.6776 }
      }, {
        id: 'point_10',
        location: { lat: 45.2687, lon: 4.6877 }
      }, {
        id: 'point_11',
        location: { lat: 45.2788, lon: 4.6878 }
      }, {
        id: 'point_11_d',
        location: { lat: 45.2788, lon: 4.6878 }
      }, {
        id: 'point_1_d',
        location: { lat: 45.6047, lon: 4.7581 }
      },],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_mode: 'car',
        router_dimension: 'distance',
        sequence_timewindows: [{
          start: 0,
          end: 20,
          day_index: 0
        }, {
          start: 0,
          end: 20,
          day_index: 1
        }, {
          start: 0,
          end: 20,
          day_index: 2
        }, {
          start: 0,
          end: 20,
          day_index: 3
        }, {
          start: 0,
          end: 20,
          day_index: 4
        }]
      }, {
        id: 'vehicle_1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_mode: 'car',
        router_dimension: 'distance',
        sequence_timewindows: [{
          start: 0,
          end: 20,
          day_index: 0
        }, {
          start: 0,
          end: 20,
          day_index: 1
        }, {
          start: 0,
          end: 20,
          day_index: 2
        }, {
          start: 0,
          end: 20,
          day_index: 3
        }, {
          start: 0,
          end: 20,
          day_index: 4
        }]
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
      }, {
        id: 'service_7',
        type: 'service',
        activity: {
          point_id: 'point_7'
        }
      }, {
        id: 'service_8',
        type: 'service',
        activity: {
          point_id: 'point_8'
        }
      }, {
        id: 'service_9',
        type: 'service',
        activity: {
          point_id: 'point_9'
        }
      }, {
        id: 'service_10',
        type: 'service',
        activity: {
          point_id: 'point_10'
        }
      }, {
        id: 'service_11',
        type: 'service',
        activity: {
          point_id: 'point_11'
        }
      }, {
        id: 'service_12',
        type: 'service',
        activity: {
          point_id: 'point_11_d'
        }
      }, {
        id: 'service_13',
        type: 'service',
        activity: {
          point_id: 'point_1_d'
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
        }
      }
    }
  end

  def self.scheduling_seq_timewindows
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 4, 5, 5, 7, 2, 3],
          [6, 0, 1, 5, 2, 2, 4],
          [1, 2, 0, 5, 1, 6, 8],
          [5, 5, 5, 0, 2, 3, 3],
          [5, 5, 5, 2, 0, 3, 3],
          [5, 5, 5, 2, 3, 0, 3],
          [5, 5, 5, 2, 3, 3, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0
      }, {
        id: 'point_1',
        matrix_index: 1
      }, {
        id: 'point_2',
        matrix_index: 2
      }, {
        id: 'point_3',
        matrix_index: 3
      }, {
        id: 'point_4',
        matrix_index: 4
      }, {
        id: 'point_5',
        matrix_index: 5
      }, {
        id: 'point_6',
        matrix_index: 6
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        sequence_timewindows: [{
          start: 0,
          end: 20,
          day_index: 0
        }, {
          start: 0,
          end: 20,
          day_index: 1
        }, {
          start: 0,
          end: 20,
          day_index: 2
        }, {
          start: 0,
          end: 20,
          day_index: 3
        }, {
          start: 0,
          end: 20,
          day_index: 4
        }]
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
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4'
        }
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5'
        }
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_6'
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
            end: 10
          }
        }
      }
    }
  end
end
