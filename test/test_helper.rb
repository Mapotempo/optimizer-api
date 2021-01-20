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
require 'minitest'
require 'simplecov'
SimpleCov.start if (!ENV.has_key?('COV') && !ENV.has_key?('COVERAGE')) || (ENV['COV'] != 'false' && ENV['COVERAGE'] != 'false')
require 'fakeredis/minitest'

ENV['APP_ENV'] ||= 'test'
require File.expand_path('../../config/environments/' + ENV['APP_ENV'], __FILE__)
Dir[File.dirname(__FILE__) + '/../config/initializers/*.rb'].sort.each{ |file| require file }

Dir[File.dirname(__FILE__) + '/../models/*.rb'].sort.each{ |file| require file }
require './optimizer_wrapper'
require './api/root'

require 'minitest/reporters'
Minitest::Reporters.use! [
  Minitest::Reporters::ProgressReporter.new,
  ENV['HTML'] && Minitest::Reporters::HtmlReporter.new, # Create an HTML report with more information
  ENV['TIME'] && Minitest::Reporters::SpecReporter.new, # Generate a report to find slowest tests
].compact

require 'grape'
require 'hashie'
require 'grape-swagger'
require 'grape-entity'

require 'minitest/autorun'
require 'minitest/stub_any_instance'
require 'minitest/focus'
require 'byebug'
require 'rack/test'
require 'find'

module FakeRedis
  def teardown
    OptimizerWrapper.config[:redis_count].flushall
  end
end

module TestHelper # rubocop: disable Style/CommentedKeyword, Lint/RedundantCopDisableDirective, Metrics/ModuleLength
  def self.coerce(vrp)
    # This function is called both with a JSON and Models::Vrp
    # That is, service[:activity]&.fetch(symbol) do not work
    # Code needs to be valid both for vrp and json.
    # Thus `if service[:activity] && service[:activity][symbol]` style verificiations.

    # TODO: Either find a way to call grape validators automatically or add necessary grape coerces here
    [:duration, :setup_duration].each { |symbol|
      vrp[:services]&.each{ |service|
        service[:activity][symbol] = ScheduleType.type_cast(service[:activity][symbol]) if service[:activity] && service[:activity][symbol]
        service[:activities]&.each{ |activity| activity[symbol] = ScheduleType.type_cast(activity[symbol]) if activity && activity[symbol] }
      }
      vrp[:shipments]&.each{ |shipment|
        shipment[:pickup][symbol]   = ScheduleType.type_cast(shipment[:pickup][symbol])   if shipment[:pickup] && shipment[:pickup][symbol]
        shipment[:delivery][symbol] = ScheduleType.type_cast(shipment[:delivery][symbol]) if shipment[:delivery] && shipment[:delivery][symbol]
      }
    }

    [vrp[:services], vrp[:shipments]].flatten.each{ |s|
      next if s.nil?
      next if vrp.is_a?(Hash) && !s.has_key?(:visits_number)

      raise StandardError, "Service/Shipment #{s[:id]} visits_number (#{s[:visits_number]}) is invalid." unless s[:visits_number].is_a?(Integer) && s[:visits_number].positive?

      [s[:activity] || s[:activities] || s[:pickup] || s[:delivery]].flatten.each{ |activity|
        next unless activity[:position]

        activity[:position] = activity[:position].to_sym
      }
    }

    if vrp[:configuration] && vrp[:configuration][:preprocessing] && vrp[:configuration][:preprocessing][:first_solution_strategy]
      vrp[:configuration][:preprocessing][:first_solution_strategy] = [vrp[:configuration][:preprocessing][:first_solution_strategy]].flatten
    end

    if vrp.is_a?(Hash) # TODO: make this work for the model as well. So that, it can detect model change and dump incompatibility.
      unknown_model_fields = vrp.keys - [:name, :matrices, :units, :points, :rests, :zones, :vehicles, :services, :shipments, :relations, :subtours, :routes, :configuration]
      raise StandardError, "If there is a new model class add it above. If not, following fields should not be in vrp: #{unknown_model_fields}" unless unknown_model_fields.empty?
    end

    # partition[:entity] becomes a symbol
    vrp[:configuration][:preprocessing][:partitions]&.each{ |partition| partition[:entity] = partition[:entity].to_sym } if vrp[:configuration] && vrp[:configuration][:preprocessing]
    vrp.preprocessing_partitions&.each{ |partition| partition[:entity] = partition[:entity].to_sym } if vrp.is_a?(Models::Vrp)

    vrp.provide_original_ids unless vrp.is_a?(Hash) # TODO: re-dump with this modification

    vrp
  end

  def self.create(problem)
    Models::Vrp.create(coerce(problem))
  end

  def self.matrix_required(vrp)
    if ENV['TEST_DUMP_VRP'].to_s == 'true' && vrp.name
      vrp.compute_matrix
      File.binwrite('test/fixtures/' + vrp.name + '.dump', Marshal.dump(vrp))
    end
  end

  def self.multipe_matrices_required(vrps, test)
    if ENV['TEST_DUMP_VRP'].to_s == 'true'
      vrps.each(&:compute_matrix)
      File.binwrite('test/fixtures/' + test.name[5..-1] + '.dump', Marshal.dump(vrps))
    end
  end

  def self.load_vrp(test, options = {})
    filename = options[:fixture_file] || test.name[5..-1]
    dump_file = 'test/fixtures/' + filename + '.dump'
    if File.file?(dump_file) && ENV['TEST_DUMP_VRP'].to_s != 'true'
      vrp = Marshal.load(File.binread(dump_file)) # rubocop: disable Security/MarshalLoad
      coerce(vrp)
    else
      vrp = options[:problem] || Hashie.symbolize_keys(JSON.parse(File.open('test/fixtures/' + filename + '.json').to_a.join)['vrp'])
      vrp = create(vrp)

      if vrp.matrices.empty?
        vrp.name = filename
        matrix_required(vrp)
      end

      vrp
    end
  end

  def self.load_vrps(test, options = {})
    filename = options[:fixture_file] || test.name[5..-1]
    dump_file = 'test/fixtures/' + filename + '.dump'
    if File.file?(dump_file) && ENV['TEST_DUMP_VRP'].to_s != 'true'
      vrps = Marshal.load(File.binread(dump_file)) # rubocop: disable Security/MarshalLoad
      vrps.map!{ |vrp| coerce(vrp) }
    else
      vrps = options[:problem] || JSON.parse(File.open('test/fixtures/' + filename + '.json').to_a.join).map{ |stored_vrp| Hashie.symbolize_keys(stored_vrp['vrp']) }

      vrps.map!{ |vrp|
        create(vrp)
      }

      multipe_matrices_required(vrps, test)

      vrps
    end
  end

  def self.solve_asynchronously
    pid_worker = Process.spawn({ 'COUNT' => '1', 'QUEUE' => 'DEFAULT' }, 'bundle exec rake resque:workers --trace', pgroup: true) # don't create another shell
    pgid_worker = Process.getpgid(pid_worker)
    sleep 0.1 while `ps -o pgid | grep #{pgid_worker}`.split(/\n/).size < 2 # wait for the worker to launch
    old_config_solve_synchronously = OptimizerWrapper.config[:solve][:synchronously]
    OptimizerWrapper.config[:solve][:synchronously] = false
    old_resque_inline = Resque.inline
    Resque.inline = false
    yield
  ensure
    if pgid_worker
      # Kill all grandchildren
      worker_pids = `ps -o pgid,pid | grep #{pgid_worker}`.split(/\n/)
      worker_pids.collect!{ |i| i.split(' ')[-1].to_i }
      worker_pids.sort!
      worker_pids.reverse_each{ |pid|
        next if pid == pgid_worker

        Process.kill('SIGKILL', pid)
        Process.detach(pid)
      }
      Process.kill('SIGTERM', -pgid_worker) # Kill the process group (this doesn't kill grandchildren)
      puts "Waiting the worker process group #{pgid_worker} to die\n"
      Process.waitpid(-pgid_worker, 0)
      Resque.inline = old_resque_inline if old_resque_inline
      OptimizerWrapper.config[:solve][:synchronously] = old_config_solve_synchronously if old_config_solve_synchronously
    end
  end

  def self.expand_vehicles(vrp)
    periodic = Interpreters::PeriodicVisits.new(vrp)
    periodic.generate_vehicles(vrp)
  end

  def self.vehicle_and_days_partitions
    [{ method: 'balanced_kmeans', metric: 'duration', entity: :vehicle },
     { method: 'balanced_kmeans', metric: 'duration', entity: :work_day }]
  end
end

module VRP # rubocop: disable Metrics/ModuleLength, Style/CommentedKeyword
  def self.toy
    {
      units: [{ id: 'u1' }],
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
          duration: 100
        }
      }
    }
  end

  def self.basic
    {
      units: [],
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
          duration: 100
        },
        preprocessing: {}
      }
    }
  end

  def self.pud
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0, 3, 3, 9],
          [3, 0, 3, 8],
          [3, 3, 0, 8],
          [9, 9, 9, 0]
        ]
      }],
      units: [{
        id: 'unit_0',
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
        cost_time_multiplier: 1,
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        matrix_id: 'matrix_0'
      }],
      shipments: [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_2',
          duration: 3,
          late_multiplier: 0,
        }
      }, {
        id: 'shipment_1',
        pickup: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_3',
          duration: 3,
          late_multiplier: 0,
        }
      }],
      configuration: {
        preprocessing: {
          prefer_short_segment: true
        },
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
  end

  def self.lat_lon
    {
      matrices: [{
        id: 'm1',
        time: [
          [0, 2824, 2824, 1110, 2299, 2299, 1823],
          [2780, 0, 0, 2132, 660, 660, 2803],
          [2780, 0, 0, 2132, 660, 660, 2803],
          [1174, 2212, 2212, 0, 1687, 1687, 1248],
          [2349, 668, 668, 1701, 0, 0, 2372],
          [2349, 668, 668, 1701, 0, 0, 2372],
          [1863, 2865, 2865, 1240, 2340, 2340, 0]
        ],
        distance: [
          [0, 53744.7, 53744.7, 15417.8, 47523.6, 47523.6, 27177.2],
          [52770.6, 0, 0, 41717.6, 5566.7, 5566.7, 53715.5],
          [52770.6, 0, 0, 41717.6, 5566.7, 5566.7, 53715.5],
          [16537, 43048.8, 43048.8, 0, 36827.6, 36827.6, 18271.5],
          [47608.5, 5636.2, 5636.2, 36555.5, 0, 0, 48553.4],
          [47608.5, 5636.2, 5636.2, 36555.5, 0, 0, 48553.4],
          [27976.8, 54797.1, 54797.1, 18252.9, 48576, 48576, 0]
        ]
      }],
      units: [],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: { lat: 45.288798, lon: 4.951565 }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: { lat: 45.344334, lon: 4.817731 }
      }, {
        id: 'point_4',
        matrix_index: 4,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_5',
        matrix_index: 5,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_6',
        matrix_index: 6,
        location: { lat: 45.2583248913, lon: 4.6873225272 }
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
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
        },
        preprocessing: {}
      }
    }
  end

  def self.lat_lon_pud
    {
      matrices: [{
        id: 'm1',
        time: [
          [0, 2824, 2824, 1110, 2299, 2299, 1823],
          [2780, 0, 0, 2132, 660, 660, 2803],
          [2780, 0, 0, 2132, 660, 660, 2803],
          [1174, 2212, 2212, 0, 1687, 1687, 1248],
          [2349, 668, 668, 1701, 0, 0, 2372],
          [2349, 668, 668, 1701, 0, 0, 2372],
          [1863, 2865, 2865, 1240, 2340, 2340, 0]
        ],
        distance: [
          [0, 53744.7, 53744.7, 15417.8, 47523.6, 47523.6, 27177.2],
          [52770.6, 0, 0, 41717.6, 5566.7, 5566.7, 53715.5],
          [52770.6, 0, 0, 41717.6, 5566.7, 5566.7, 53715.5],
          [16537, 43048.8, 43048.8, 0, 36827.6, 36827.6, 18271.5],
          [47608.5, 5636.2, 5636.2, 36555.5, 0, 0, 48553.4],
          [47608.5, 5636.2, 5636.2, 36555.5, 0, 0, 48553.4],
          [27976.8, 54797.1, 54797.1, 18252.9, 48576, 48576, 0]
        ]
      }],
      units: [],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: { lat: 45.288798, lon: 4.951565 }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: { lat: 45.344334, lon: 4.817731 }
      }, {
        id: 'point_4',
        matrix_index: 4,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_5',
        matrix_index: 5,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_6',
        matrix_index: 6,
        location: { lat: 45.2583248913, lon: 4.6873225272 }
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_dimension: 'distance',
      }],
      shipments: [{
        id: 'shipment_1',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_1'
        }
      }, {
        id: 'shipment_2',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_2'
        }
      }, {
        id: 'shipment_3',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_3'
        }
      }, {
        id: 'shipment_4',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_4'
        }
      }, {
        id: 'shipment_5',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_5'
        }
      }, {
        id: 'shipment_6',
        pickup: {
          point_id: 'point_0'
        },
        delivery: {
          point_id: 'point_6'
        }
      }],
      configuration: {
        resolution: {
          duration: 2000
        },
        preprocessing: {}
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
          duration: 100,
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

  def self.lat_lon_capacitated
    {
      units: [{
        id: 'kg'
      }],
      matrices: [{
        id: 'm1',
        time: [
          [0, 4032, 4032, 1142, 3194, 3194, 2177],
          [4391, 0, 0, 3003, 660, 660, 3806],
          [4391, 0, 0, 3003, 660, 660, 3806],
          [1226, 3079, 3079, 0, 2412, 2412, 1282],
          [3619, 668, 668, 2437, 0, 0, 3424],
          [3619, 668, 668, 2437, 0, 0, 3424],
          [2192, 3802, 3802, 1302, 3443, 3443, 0]
        ],
        distance: [
          [0, 47421.3, 47421.3, 15006.4, 42202.1, 42202.1, 25276.8],
          [47800.9, 0, 0, 36467.2, 5566.7, 5566.7, 51131.4],
          [47800.9, 0, 0, 36467.2, 5566.7, 5566.7, 51131.4],
          [15659.2, 36787.3, 36787.3, 0, 31151.1, 31151.1, 17579.1],
          [43286.1, 5636.2, 5636.2, 31545.7, 0, 0, 46706.8],
          [43286.1, 5636.2, 5636.2, 31545.7, 0, 0, 46706.8],
          [25669.7, 51202.7, 51202.7, 17574.4, 46538.9, 46538.9, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: { lat: 45.288798, lon: 4.951565 }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: { lat: 45.6047844887, lon: 4.7589656711 }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: { lat: 45.344334, lon: 4.817731 }
      }, {
        id: 'point_4',
        matrix_index: 4,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_5',
        matrix_index: 5,
        location: { lat: 45.5764120817, lon: 4.8056146502 }
      }, {
        id: 'point_6',
        matrix_index: 6,
        location: { lat: 45.2583248913, lon: 4.6873225272 }
      }],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_dimension: 'distance',
        capacities: [{
          unit_id: 'kg',
          limit: 5
        }]
      }],
      services: [{
        id: 'service_1',
        type: 'service',
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_2',
        type: 'service',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_3',
        type: 'service',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_4',
        type: 'service',
        activity: {
          point_id: 'point_4'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_5',
        type: 'service',
        activity: {
          point_id: 'point_5'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_6',
        type: 'service',
        activity: {
          point_id: 'point_6'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }],
      configuration: {
        resolution: {
          duration: 100
        }
      }
    }
  end

  def self.lat_lon_capacitated_2dimensions
    vrp = lat_lon_capacitated
    vrp[:vehicles].each{ |vehicle|
      vehicle[:cost_time_multiplier] = 1
      vehicle[:cost_distance_multiplier] = 1
    }

    vrp
  end

  def self.lat_lon_scheduling
    vrp = lat_lon_capacitated
    vrp[:vehicles].each{ |v|
      v.delete(:capacities)
      v[:timewindow] = { start: 28800, end: 61200 }
    }
    vrp[:services].each{ |v| v.delete(:quantities) }
    vrp[:configuration] = {
      resolution: {
        duration: 100,
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

    vrp
  end

  def self.lat_lon_two_vehicles
    {
      units: [{
        id: 'kg'
      }],
      matrices: [{
        id: 'm1',
        time: [
          [0, 4046, 4555, 3807, 3207, 3423, 2560, 2615, 2647, 2058, 1990, 2134, 2134, 4046],
          [4395, 0, 528, 887, 678, 878, 4245, 4193, 4267, 3766, 3698, 4014, 4014, 0],
          [4904, 521, 0, 1396, 1187, 1388, 4754, 4702, 4777, 4276, 4207, 4524, 4524, 521],
          [3965, 866, 1375, 0, 401, 386, 4703, 4758, 4791, 4224, 4156, 4473, 4473, 866],
          [3626, 686, 1195, 422, 0, 216, 3862, 3634, 3708, 3383, 3315, 3631, 3631, 686],
          [3826, 896, 1405, 391, 221, 0, 4564, 3855, 3929, 4086, 4017, 4334, 4334, 896],
          [2638, 4263, 4772, 4804, 3902, 4119, 0, 193, 301, 441, 522, 528, 528, 4263],
          [2680, 4153, 4662, 4845, 3592, 3809, 181, 0, 164, 305, 343, 391, 391, 4153],
          [2688, 4226, 4735, 4854, 3665, 3882, 286, 156, 0, 378, 416, 464, 464, 4226],
          [2123, 3741, 4250, 4282, 3380, 3597, 443, 313, 387, 0, 80, 219, 219, 3741],
          [2056, 3673, 4183, 4214, 3313, 3529, 502, 352, 427, 87, 0, 148, 148, 3673],
          [2392, 3994, 4503, 4535, 3633, 3849, 526, 396, 471, 223, 148, 0, 0, 3994],
          [2392, 3994, 4503, 4535, 3633, 3849, 526, 396, 471, 223, 148, 0, 0, 3994],
          [4395, 0, 528, 887, 678, 878, 4245, 4193, 4267, 3766, 3698, 4014, 4014, 0]
        ],
        distance: [
          [0, 47517.6, 48430.8, 45189.3, 42265.6, 43516.8, 27045, 27767.6, 28944.3, 26764.8, 25854.9, 26981.3, 26981.3, 47517.6],
          [47895.8, 0, 1041.8, 7247.1, 5677.2, 6735.3, 53175.5, 52927.8, 53644.9, 52224, 51314.1, 50371.6, 50371.6, 0],
          [48809, 1041.8, 0, 8160.3, 6590.4, 7648.5, 54088.7, 53841, 54558.1, 53137.2, 52227.3, 51284.8, 51284.8, 1041.8],
          [46138, 7058.6, 7971.8, 0, 4128.1, 4005.4, 51215, 51937.7, 53114.3, 50263.6, 49353.6, 48411.2, 48411.2, 7058.6],
          [43348.3, 5746.6, 6659.9, 4161.3, 0, 1251.2, 48681.3, 49764.1, 50481.2, 47729.9, 46819.9, 45877.5, 45877.5, 5746.6],
          [44408.7, 6799.1, 7712.3, 4073.4, 1251.2, 0, 49485.8, 51015.3, 51732.4, 48534.3, 47624.4, 46681.9, 46681.9, 6799.1],
          [27645.2, 53274.4, 54187.6, 51568.2, 48577.8, 49829.1, 0, 1169.2, 2413.7, 3525.5, 3041, 4614, 4614, 53274.4],
          [28391.3, 53009.8, 53923, 52314.3, 49347, 50598.3, 1192.7, 0, 1621.1, 2732.9, 3606.8, 3821.4, 3821.4, 53009.8],
          [29383.2, 53810.3, 54723.5, 53306.2, 50147.5, 51398.8, 2388.6, 1572.5, 0, 3533.4, 4407.3, 4621.9, 4621.9, 53810.3],
          [27454.2, 52282, 53195.2, 50575.8, 47585.4, 48836.7, 3572.1, 2756, 3473.1, 0, 1106.8, 2088, 2088, 52282],
          [26501.3, 51329, 52242.2, 49622.8, 46632.5, 47883.7, 3013.4, 3641.4, 4358.5, 1118.3, 0, 1887.6, 1887.6, 51329],
          [27191.7, 50443.5, 51356.7, 48737.3, 45747, 46998.2, 4660.6, 3844.5, 4561.6, 2088, 1887.3, 0, 0, 50443.5],
          [27191.7, 50443.5, 51356.7, 48737.3, 45747, 46998.2, 4660.6, 3844.5, 4561.6, 2088, 1887.3, 0, 0, 50443.5],
          [47895.8, 0, 1041.8, 7247.1, 5677.2, 6735.3, 53175.5, 52927.8, 53644.9, 52224, 51314.1, 50371.6, 50371.6, 0]
        ]
      }],
      points: [{
        id: 'point_0',
        matrix_index: 0,
        location: { lat: 45.2888, lon: 4.9515 }
      }, {
        id: 'point_1',
        matrix_index: 1,
        location: { lat: 45.6047, lon: 4.7581 }
      }, {
        id: 'point_2',
        matrix_index: 2,
        location: { lat: 45.6046, lon: 4.752 }
      }, {
        id: 'point_3',
        matrix_index: 3,
        location: { lat: 45.6044, lon: 4.8171 }
      }, {
        id: 'point_4',
        matrix_index: 4,
        location: { lat: 45.5767, lon: 4.8052 }
      }, {
        id: 'point_5',
        matrix_index: 5,
        location: { lat: 45.5766, lon: 4.8153 }
      }, {
        id: 'point_6',
        matrix_index: 6,
        location: { lat: 45.2583, lon: 4.6773 }
      }, {
        id: 'point_7',
        matrix_index: 7,
        location: { lat: 45.2584, lon: 4.6674 }
      }, {
        id: 'point_8',
        matrix_index: 8,
        location: { lat: 45.2585, lon: 4.6575 }
      }, {
        id: 'point_9',
        matrix_index: 9,
        location: { lat: 45.2686, lon: 4.6776 }
      }, {
        id: 'point_10',
        matrix_index: 10,
        location: { lat: 45.2687, lon: 4.6877 }
      }, {
        id: 'point_11',
        matrix_index: 11,
        location: { lat: 45.2788, lon: 4.6878 }
      }, {
        id: 'point_11_d',
        matrix_index: 12,
        location: { lat: 45.2788, lon: 4.6878 }
      }, {
        id: 'point_1_d',
        matrix_index: 13,
        location: { lat: 45.6047, lon: 4.7581 }
      },],
      vehicles: [{
        id: 'vehicle_0',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        # router_mode: 'car',
        router_dimension: 'distance'
      }, {
        id: 'vehicle_1',
        matrix_id: 'm1',
        start_point_id: 'point_0',
        end_point_id: 'point_0',
        router_dimension: 'distance'
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
          duration: 100
        }
      }
    }
  end

  def self.lat_lon_two_vehicles_2dimensions
    vrp = lat_lon_two_vehicles
    vrp[:vehicles].each{ |vehicle|
      vehicle[:cost_time_multiplier] = 1
      vehicle[:cost_distance_multiplier] = 1
    }

    vrp
  end

  def self.lat_lon_scheduling_two_vehicles
    vrp = lat_lon_two_vehicles
    vrp[:vehicles].each{ |v|
      v[:sequence_timewindows] = [
        { start: 0, end: 100000, day_index: 0 },
        { start: 0, end: 100000, day_index: 1 },
        { start: 0, end: 100000, day_index: 2 },
        { start: 0, end: 100000, day_index: 3 },
        { start: 0, end: 100000, day_index: 4 }
      ]
    }
    vrp[:configuration][:resolution][:solver] = false
    vrp[:configuration][:preprocessing] = {
      first_solution_strategy: ['periodic']
    }
    vrp[:configuration][:schedule] = {
      range_indices: {
        start: 0,
        end: 3
      }
    }

    vrp
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
        sequence_timewindows: [
          { start: 0, end: 20, day_index: 0 },
          { start: 0, end: 20, day_index: 1 },
          { start: 0, end: 20, day_index: 2 },
          { start: 0, end: 20, day_index: 3 },
          { start: 0, end: 20, day_index: 4 }
        ]
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
          duration: 100,
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

  def self.independent
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
        timewindow: {
          start: 0,
          end: 20
        }
      }, {
        id: 'vehicle_1',
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
          point_id: 'point_1',
        },
        sticky_vehicle_ids: [
          'vehicle_0'
        ],
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        sticky_vehicle_ids: [
          'vehicle_0'
        ],
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        },
        sticky_vehicle_ids: [
          'vehicle_0'
        ],
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4',
        },
        sticky_vehicle_ids: [
          'vehicle_1'
        ],
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5'
        },
        sticky_vehicle_ids: [
          'vehicle_1'
        ],
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_6'
        },
        sticky_vehicle_ids: [
          'vehicle_1'
        ],
      }],
      configuration: {
        resolution: {
          duration: 100
        }
      }
    }
  end

  def self.independent_skills
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
        skills: [['D', 'S1']]
      }, {
        id: 'vehicle_1',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        skills: [['D', 'S2']]
      }, {
        id: 'vehicle_2',
        matrix_id: 'matrix_0',
        start_point_id: 'point_0',
        skills: [['S3', 'S4']]
      }],
      services: [{
        id: 'service_1',
        activity: {
          point_id: 'point_1',
        },
        skills: ['S3']
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        skills: ['S1', 'D']
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        },
        skills: ['S2', 'D']
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4',
        },
        skills: ['S1']
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5'
        },
        skills: ['S2']
      }, {
        id: 'service_6',
        activity: {
          point_id: 'point_6'
        },
        skills: ['S3', 'S4']
      }],
      configuration: {
        resolution: {
          duration: 100
        }
      }
    }
  end
end
