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

ENV['APP_ENV'] ||= 'test'

require './environment.rb'

WebMock.disable_net_connect!

if Rake.application.top_level_tasks.include?('test') && ![ENV['COVERAGE'], ENV['COV']].include?('false')
  require 'simplecov'
  SimpleCov.start
end

Minitest::Reporters.use! [
  !ENV['TIME'] ? Minitest::Reporters::ProgressReporter.new : nil,
  ENV['HTML'] && Minitest::Reporters::HtmlReporter.new, # Create an HTML report with more information
  ENV['TIME'] && Minitest::Reporters::SpecReporter.new, # Generate a report to find slowest tests
].compact

Minitest::Retry.use!(
  # List of methods that will trigger a retry (when empty, all methods will).
  # The list respects alphabetical order for easy maintenance
  methods_to_retry: %w[
    Api::V01::OutputTest#test_csv_configuration_asynchronously
    Api::V01::OutputTest#test_csv_headers_compatible_with_import_according_to_language
    Api::V01::OutputTest#test_returned_ids
    Api::V01::OutputTest#test_returned_types
    Api::V01::OutputTest#test_use_deprecated_csv_headers_asynchronously
    Api::V01::WithSolverTest#test_deleted_job
    DichotomousTest#test_cluster_dichotomous_heuristic
    DichotomousTest#test_dichotomous_approach
    RealCasesTest#test_ortools_open_timewindows
    SplitClusteringTest#test_avoid_capacities_overlap
    SplitClusteringTest#test_cluster_one_phase_vehicle
    SplitClusteringTest#test_instance_same_point_day
    SplitClusteringTest#test_no_doubles_3000
    Wrappers::OrtoolsTest#test_ortools_performance_when_duration_limit
    WrapperTest#test_detecting_unfeasible_services_can_not_take_too_long
  ]
)

class IsolatedTest < Minitest::Test
  # It cleans the active_hash database before and after (around) the test.
  # Needed for tests calling Model::X.create directly to prevent ID errors.
  include Rack::Test::Methods

  def around
    Models.delete_all
    yield
  ensure
    Models.delete_all
  end
end

module TestHelper # rubocop: disable Style/CommentedKeyword, Lint/RedundantCopDisableDirective, Metrics/ModuleLength
  def self.coerce(vrp)
    # This function is called both with a JSON and Models::Vrp
    # That is, service[:activity]&.fetch(symbol) do not work
    # Code needs to be valid both for vrp and json.
    # Thus `if service[:activity] && service[:activity][symbol]` style verifications.

    # Clean unreferenced points
    all_referenced_point_ids =
      vrp[:vehicles]&.flat_map{ |v| [v[:start_point_id], v[:end_point_id]] }.to_a |
      vrp[:services]&.flat_map{ |s| ([s[:activity]].compact + s[:activities].to_a).map{ |a| a[:point_id] } }.to_a |
      vrp[:shipments]&.flat_map{ |s| [s[:pickup][:point_id], s[:delivery][:point_id]].compact }.to_a |
      vrp[:subtours]&.flat_map{ |s| s[:transmodal_stop_ids].to_a }.to_a
    vrp[:points]&.delete_if{ |p| all_referenced_point_ids.exclude?(p[:id]) }

    vrp[:points]&.each{ |pt|
      next unless pt[:location]

      pt[:location][:lat] = pt[:location][:lat].to_f
      pt[:location][:lon] = pt[:location][:lon].to_f
    }

    # TODO: Either find a way to call grape validators automatically or add necessary grape coerces here
    [:duration, :setup_duration].each { |symbol|
      vrp[:services]&.each{ |service|
        raise 'Remove deprecated type field' if service[:type]

        service.delete(:type)
        service[:activity][symbol] = ScheduleType.type_cast(service[:activity][symbol] || 0) if service[:activity]
        service[:activities]&.each{ |activity|
          activity[symbol] = ScheduleType.type_cast(activity[symbol] || 0) if activity
        }
      }
      vrp[:shipments]&.each{ |shipment|
        shipment[:pickup][symbol]   = ScheduleType.type_cast(shipment[:pickup][symbol] || 0) if shipment[:pickup]
        shipment[:delivery][symbol] = ScheduleType.type_cast(shipment[:delivery][symbol] || 0) if shipment[:delivery]
      }
    }

    vrp[:rests]&.each{ |rest|
      rest[:duration] = ScheduleType.type_cast(rest[:duration] || 0)
    }

    vrp[:vehicles].each{ |vehicle|
      vehicle[:duration]         = ScheduleType.type_cast(vehicle[:duration])         if vehicle[:duration]
      vehicle[:overall_duration] = ScheduleType.type_cast(vehicle[:overall_duration]) if vehicle[:overall_duration]

      if vehicle.key?(:skills)
        vehicle.delete(:skills) if vehicle[:skills].nil? || vehicle[:skills].empty?

        if vehicle[:skills]&.any?{ |skill_set| !skill_set.is_a? Array }
          raise 'Vehicle skills should be an Array[Array[Symbol]]'
        end

        vehicle[:skills]&.each{ |skill_set| skill_set.map!(&:to_sym) }
      end
      vehicle.delete(:original_id)
    }

    [vrp[:services], vrp[:shipments]].each{ |group|
      group&.each{ |s|
        s[:skills]&.map!(&:to_sym)

        s.delete(:original_id)

        [s[:activity] || s[:activities] || s[:pickup] || s[:delivery]].flatten.each{ |activity|
          next unless activity[:position]

          activity[:position] = activity[:position].to_sym
        }

        next if vrp.is_a?(Hash) && !s.key?(:visits_number)

        unless s[:visits_number].is_a?(Integer) && s[:visits_number].positive?
          raise StandardError.new(
            "Service/Shipment #{s[:id]} visits_number (#{s[:visits_number]}) is invalid."
          )
        end
      }
    }

    config = vrp[:configuration]
    if config && config[:preprocessing] && config[:preprocessing][:first_solution_strategy]
      config[:preprocessing][:first_solution_strategy] = [config[:preprocessing][:first_solution_strategy]].flatten
    end

    if config && config[:restitution] && config[:restitution][:geometry] == true
      config[:restitution][:geometry] = %i[polylines encoded_polylines]
    end

    if config
      if config[:restitution]
        config[:restitution][:geometry] ||= []
      else
        config[:restitution] = { geometry: [] }
      end
    end

    if vrp.is_a?(Hash) # TODO: make this work for the model as well.
      # So that, it can detect model change and dump incompatibility.
      unknown_model_fields = vrp.keys - [:name, :matrices, :units, :points, :rests,
                                         :zones, :vehicles, :services, :shipments, :relations, :subtours,
                                         :routes, :configuration]
      unless unknown_model_fields.empty?
        raise "If there is a new model class add it above. "\
              "If not, following fields should not be in vrp: #{unknown_model_fields}"
      end
    end

    if config && config[:preprocessing]
      # partition[:entity] becomes a symbol
      config[:preprocessing][:partitions]&.each{ |partition|
        partition[:entity] = partition[:entity].to_sym
      }
    end
    if vrp.is_a?(Models::Vrp)
      vrp.configuration.preprocessing.partitions&.each{ |partition| partition[:entity] = partition[:entity].to_sym }
    end

    vrp[:relations]&.each{ |r|
      r[:type] = r[:type]&.to_sym
      next if [Models::Relation::NO_LAPSE_TYPES,
               Models::Relation::ONE_LAPSE_TYPES,
               Models::Relation::SEVERAL_LAPSE_TYPES].any?{ |set| set.include?(r[:type]) }

      raise 'This relation does not exit in any of NO_LAPSE_RELATIONS ONE_LAPSE_RELATIONS '\
      'SEVERAL_LAPSE_RELATIONS, there is a risk of incorrect management'
    }

    vrp[:relations]&.each{ |r|
      r[:type] = r[:type]&.to_sym
      next if [Models::Relation::ON_VEHICLES_TYPES,
               Models::Relation::ON_SERVICES_TYPES].any?{ |set| set.include?(r[:type]) }

      raise 'This relation does not exit in any of ON_VEHICLES_TYPES '\
      'ON_SERVICES_TYPES there is a risk of incorrect management'
    }

    vrp[:vehicles]&.each{ |v|
      next if v[:skills].to_a.empty?

      raise 'Vehicle skills should be an array of array' unless v[:skills].first&.is_a?(Array)

      v[:skills].each{ |set| set.map!(&:to_sym) }
    }

    # trips parameter does not exist anymore
    vrp[:vehicles]&.each{ |v|
      next unless v[:trips]

      raise 'vehicle[:trips] parameter does not exist' if v[:trips] > 1

      v.delete(:trips)
    }

    vrp
  end

  def self.create(problem)
    Models::Vrp.create(coerce(Oj.load(Oj.dump(problem), symbol_keys: true)))
  end

  def self.matrices_required(vrps, filename)
    return if vrps.all?{ |vrp| vrp.matrices.any? }

    dump_file = "test/fixtures/#{filename}.dump"
    dumped_data = Oj.load(Zlib.inflate(File.read(dump_file))) if File.file?(dump_file)

    warn 'Overwriting the existing matrix dump' if dumped_data && ENV['TEST_DUMP_VRP'] == 'true'

    write_in_dump = []
    vrps.each{ |vrp|
      next if vrp.matrices.any?

      if dumped_data.nil? && ENV['TEST_DUMP_VRP'] != 'true'
        WebMock.enable_net_connect!
        vrp.compute_matrix
        WebMock.disable_net_connect!
      else
        Routers::RouterWrapper.stub_any_instance(:matrix, lambda { |url, mode, dimensions, row, column, options|
          corresponding_data = nil

          # Oj rounds values:
          row.map!{ |l| l.map!{ |v| v.round(6) } }
          column.map!{ |l| l.map!{ |v| v.round(6) } }

          # Dump the matrices only for uniq locations
          uniq_row = row.uniq
          uniq_column = column.uniq

          if ENV['TEST_DUMP_VRP'] == 'true'
            WebMock.enable_net_connect!
            matrices = vrp.router.send(:__minitest_any_instance_stub__matrix,
                                       url, mode, dimensions, uniq_row, uniq_column, options) # call original method
            WebMock.disable_net_connect!

            corresponding_data =
              { column: uniq_column, dimensions: dimensions,
                matrices: matrices, mode: mode, options: options, row: uniq_row, url: url }

            write_in_dump << corresponding_data
          else
            corresponding_data =
              dumped_data.find{ |dumped|
                dumped[:mode] == mode && dumped[:options] == options && (dimensions - dumped[:dimensions]).empty? &&
                  (uniq_row - dumped[:row]).empty? && (uniq_column - dumped[:column]).empty?
              }
            raise 'Could not find matrix in the dump' unless corresponding_data
          end

          corresponding_matrices = corresponding_data[:matrices]

          row_indices = row.map{ |location| corresponding_data[:row].find_index(location) }
          column_indices = column.map{ |location| corresponding_data[:column].find_index(location) }

          corresponding_matrices.map!{ |matrix|
            matrix.map!{ |r| r.values_at(*column_indices) }
            row_indices.map.with_index{ |r_index, index|
              r_index == index ? matrix[r_index] : matrix[r_index].dup
            }
          }

          dimensions.collect{ |dim| corresponding_matrices[corresponding_data[:dimensions].find_index(dim)] }
        }) do
          vrp.compute_matrix
        end
      end
    }

    File.write("test/fixtures/#{filename}.dump", Zlib.deflate(Oj.dump(write_in_dump))) if write_in_dump.any?
  end

  def self.load_vrp(test, options = {})
    load_vrps(test, options)[0]
  end

  def self.load_vrps(test, options = {})
    filename = options[:fixture_file] || test.name[5..-1]
    json_file = options[:json_file_path] || "test/fixtures/#{filename}.json"
    vrps =
      options[:problem] ? { vrp: options[:problem] } :
                                    JSON.parse(File.read(json_file), symbolize_names: true)
    vrps = [vrps] unless vrps.is_a?(Array)
    vrps.map!{ |vrp| create(vrp[:vrp]) }

    # "unless name" is a way not to keep track of matrices when it is not needed
    matrices_required(vrps, filename) unless vrps.any?(&:name)

    vrps
  end

  def self.expand_vehicles(vrp)
    periodic = Interpreters::PeriodicVisits.new(vrp)
    periodic.generate_vehicles(vrp)
  end

  def self.vehicle_and_days_partitions
    [{ technique: 'balanced_kmeans', metric: 'duration', entity: :vehicle },
     { technique: 'balanced_kmeans', metric: 'duration', entity: :work_day }]
  end

  def self.vehicle_trips_relation(vehicles)
    {
      type: :vehicle_trips,
      linked_vehicle_ids: vehicles.collect{ |v| v[:id] }
    }
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
        activity: {
          point_id: 'p1'
        }
      }],
      configuration: {
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
  end

  def self.basic
    {
      units: [{ id: 'kg' }],
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
        preprocessing: {},
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
  end

  def self.basic_alternatives
    {
      units: [{ id: 'kg' }],
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
        activities: [{
          point_id: 'point_1',
        }, {
          point_id: 'point_2'
        }]
      }, {
        id: 'service_2',
        activities: [{
          point_id: 'point_2'
        }, {
          point_id: 'point_3'
        }]
      }, {
        id: 'service_3',
        activities: [{
          point_id: 'point_3'
        }, {
          point_id: 'point_1'
        }]
      }],
      configuration: {
        resolution: {
          duration: 100
        },
        preprocessing: {},
        restitution: {
          intermediate_solutions: false,
        }
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
          duration: 2000
        },
        preprocessing: {},
        restitution: {
          intermediate_solutions: false,
        }
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
        preprocessing: {},
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
  end

  def self.periodic
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
        },
        restitution: {
          intermediate_solutions: false,
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
        activity: {
          point_id: 'point_1'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_2',
        activity: {
          point_id: 'point_2'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_3',
        activity: {
          point_id: 'point_3'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_4',
        activity: {
          point_id: 'point_4'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_5',
        activity: {
          point_id: 'point_5'
        },
        quantities: [{
          unit_id: 'kg',
          value: 2
        }]
      }, {
        id: 'service_6',
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
        },
        restitution: {
          intermediate_solutions: false,
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

  def self.lat_lon_periodic
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
      },
      restitution: {
        intermediate_solutions: false,
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
          [0, 47517, 48430, 45189, 42265, 43516, 27045, 27767, 28944, 26764, 25854, 26981, 26981, 47517],
          [47895, 0, 1041, 7247, 5677, 6735, 53175, 52927, 53644, 52224, 51314, 50371, 50371, 0],
          [48809, 1041, 0, 8160, 6590, 7648, 54088, 53841, 54558, 53137, 52227, 51284, 51284, 1041],
          [46138, 7058, 7971, 0, 4128, 4005, 51215, 51937, 53114, 50263, 49353, 48411, 48411, 7058],
          [43348, 5746, 6659, 4161, 0, 1251, 48681, 49764, 50481, 47729, 46819, 45877, 45877, 5746],
          [44408, 6799, 7712, 4073, 1251, 0, 49485, 51015, 51732, 48534, 47624, 46681, 46681, 6799],
          [27645, 53274, 54187, 51568, 48577, 49829, 0, 1169, 2413, 3525, 3041, 4614, 4614, 53274],
          [28391, 53009, 53923, 52314, 49347, 50598, 1192, 0, 1621, 2732, 3606, 3821, 3821, 53009],
          [29383, 53810, 54723, 53306, 50147, 51398, 2388, 1572, 0, 3533, 4407, 4621, 4621, 53810],
          [27454, 52282, 53195, 50575, 47585, 48836, 3572, 2756, 3473, 0, 1106, 2088, 2088, 52282],
          [26501, 51329, 52242, 49622, 46632, 47883, 3013, 3641, 4358, 1118, 0, 1887, 1887, 51329],
          [27191, 50443, 51356, 48737, 45747, 46998, 4660, 3844, 4561, 2088, 1887, 0, 0, 50443],
          [27191, 50443, 51356, 48737, 45747, 46998, 4660, 3844, 4561, 2088, 1887, 0, 0, 50443],
          [47895, 0, 1041, 7247, 5677, 6735, 53175, 52927, 53644, 52224, 51314, 50371, 50371, 0]
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
      }, {
        id: 'service_7',
        activity: {
          point_id: 'point_7'
        }
      }, {
        id: 'service_8',
        activity: {
          point_id: 'point_8'
        }
      }, {
        id: 'service_9',
        activity: {
          point_id: 'point_9'
        }
      }, {
        id: 'service_10',
        activity: {
          point_id: 'point_10'
        }
      }, {
        id: 'service_11',
        activity: {
          point_id: 'point_11'
        }
      }, {
        id: 'service_12',
        activity: {
          point_id: 'point_11_d'
        }
      }, {
        id: 'service_13',
        activity: {
          point_id: 'point_1_d'
        }
      }],
      configuration: {
        resolution: {
          duration: 100
        },
        restitution: {
          intermediate_solutions: false,
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

  def self.lat_lon_periodic_two_vehicles
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

  def self.periodic_seq_timewindows
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
        },
        restitution: {
          intermediate_solutions: false,
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
        },
        restitution: {
          intermediate_solutions: false,
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
        },
        restitution: {
          intermediate_solutions: false,
        }
      }
    }
  end

  def self.basic_threshold
    size = 5
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ],
        distance: [
          [0,  1,  1, 10,  0],
          [1,  0,  1, 10,  1],
          [1,  1,  0, 10,  1],
          [10, 10, 10, 0, 10],
          [0,  1,  1, 10,  0]
        ]
      }],
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          matrix_index: i
        }
      },
      rests: [{
        id: 'rest_0',
        timewindows: [{
          start: 1,
          end: 1
        }],
        duration: 1
      }],
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        matrix_id: 'matrix_0',
        rest_ids: ['rest_0']
      }],
      services: (1..(size - 1)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}",
          }
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 20,
        }
      }
    }
  end

  def self.real_matrix_threshold
    size = 6
    {
      matrices: [{
        id: 'matrix_0',
        time: [
          [0,    693,  655,  1948, 693,  0],
          [609,  0,    416,  2070, 0,    609],
          [603,  489,  0,    1692, 489,  603],
          [1861, 1933, 1636, 0,    1933, 1861],
          [609,  0,    416,  2070, 0,    609],
          [0,    693,  655,  1948, 693,  0]
        ]
      }],
      points: (0..(size - 1)).collect{ |i|
        {
          id: "point_#{i}",
          matrix_index: i
        }
      },
      vehicles: [{
        id: 'vehicle_0',
        start_point_id: 'point_0',
        end_point_id: "point_#{size - 1}",
        matrix_id: 'matrix_0'
      }],
      services: (1..(size - 2)).collect{ |i|
        {
          id: "service_#{i}",
          activity: {
            point_id: "point_#{i}"
          }
        }
      },
      configuration: {
        preprocessing: {
          cluster_threshold: 5
        },
        resolution: {
          duration: 20,
        }
      }
    }
  end
end
