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
require './test/api/v01/request_helper'

require 'minitest/around/unit'

class Api::V01::OutputTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    Api::Root
  end

  # This function wraps around each test in this class.
  # And the actual test is called in 'yield' so that
  # we can uniformise the clean-up process
  def around
    # Save current settings to reset it after the test
    current = {
      dump_vrp_dir: OptimizerWrapper.dump_vrp_dir,
      output_clusters: OptimizerWrapper.config[:debug][:output_clusters],
      output_schedule: OptimizerWrapper.config[:debug][:output_schedule]
    }

    Dir.mktmpdir('temp_', 'test/') { |tmpdir|
      # A tmpdir is created with a uniq name and
      # deleted at the end of the block automatically
      OptimizerWrapper.dump_vrp_dir = CacheManager.new(tmpdir)

      yield
    }
  ensure
    # Reset settings back to current
    OptimizerWrapper.dump_vrp_dir = current[:dump_vrp_dir]
    OptimizerWrapper.config[:debug][:output_clusters] = current[:output_clusters]
    OptimizerWrapper.config[:debug][:output_schedule] = current[:output_schedule]
    # tmpdir and generated files are already deleted
  end

  def test_day_week_num_and_other_scheduling_fields
    vrp = VRP.scheduling
    vrp[:services].first[:visits_number] = 2
    vrp[:configuration][:restitution] = { csv: true }

    csv_data = submit_csv api_key: 'demo', vrp: vrp
    assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
    assert_includes csv_data.first, 'day_week'
    assert_includes csv_data.first, 'day_week_num'

    day_index = csv_data.first.find_index('day')
    assert_equal ['day', '0', '1', '2', '3'], csv_data.collect{ |l| l[day_index] }.compact.uniq

    visit_index = csv_data.first.find_index('visit_index')
    assert_equal ['1', '2', 'visit_index'], csv_data.collect{ |l| l[visit_index] }.compact.uniq.sort
  end

  def test_check_returned_day_and_visit_index
    vrp = VRP.basic
    response = post '/0.1/vrp/submit', { api_key: 'solvers', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)
    assert(result['solutions'].first['routes'].none?{ |route| route['day'] })
    assert(result['solutions'].first['routes'].none?{ |route| route['activities'].any?{ |a| a['visit_index'] } })

    vrp = VRP.scheduling
    response = post '/0.1/vrp/submit', { api_key: 'solvers', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)
    assert_equal [0, 1, 2, 3], result['solutions'].first['routes'].collect{ |route| route['day'] }.sort
    visit_indices = result['solutions'].first['routes'].flat_map{ |r|
      r['activities'].flat_map{ |a| a['visit_index'] }
    }.compact
    assert_equal [1], visit_indices.uniq

    vrp = VRP.scheduling
    vrp[:configuration][:schedule] = {
      range_date: {
        start: Date.new(2021, 2, 10),
        end: Date.new(2021, 2, 15)
      }
    }
    response = post '/0.1/vrp/submit', { api_key: 'solvers', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)
    assert_equal %w[2021-02-10 2021-02-11 2021-02-12 2021-02-13 2021-02-14 2021-02-15],
                 result['solutions'].first['routes'].collect{ |route| route['day'] }.sort
  end

  def test_no_day_week_num
    vrp = VRP.basic
    vrp[:configuration][:restitution] = { csv: true }

    csv_data = submit_csv api_key: 'demo', vrp: vrp
    assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
    refute_includes csv_data.first, 'day_week'
    refute_includes csv_data.first, 'day_week_num'
  end

  def test_returned_skills
    vrp = VRP.lat_lon_two_vehicles
    vrp[:configuration][:preprocessing] = { partitions: TestHelper.vehicle_and_days_partitions }
    vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 10 }}
    vrp[:vehicles].first[:skills] = [['skill_to_output']]
    vrp[:services].first[:skills] = ['skill_to_output']

    response = post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)['solutions'].first
    activities = result['routes'].flat_map{ |r| r['activities'] }
    assert(activities.any?{ |a| a['detail'] && a['detail']['skills'].to_a.size < 2 })
    assert(activities.any?{ |a| a['detail'] && a['detail']['skills'].to_a.include?('skill_to_output') })
  end

  def test_skill_when_partitions
    vrp = VRP.lat_lon_two_vehicles
    vrp[:configuration][:preprocessing] = { partitions: TestHelper.vehicle_and_days_partitions }
    # ensure one unassigned service :
    vrp[:services].first[:activity][:timewindows] = [{ end: 100 }]
    vrp[:vehicles].each{ |v| v[:timewindow] = { start: 200 } }
    vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 10 }}

    response = post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)['solutions'].first
    to_check = result['routes'].flat_map{ |route| route['activities'].select{ |stop| stop['type'] == 'service' } } + result['unassigned']
    to_check.each{ |element|
      # each element should have 3 skills added by clustering :
      assert_equal 3, element['detail']['skills'].size
      # - exactly 1 skill corresponding to vehicle_id entity
      assert(element['detail']['skills'].include?('vehicle_0') ^ element['detail']['skills'].include?('vehicle_1'))
      # - exactly 1 skill corresponding to work_day entity
      assert_equal element['detail']['skills'].size - 1, (element['detail']['skills'] - %w[mon tue wed thu fri sat sun]).size
      # - exactly 1 skill corresponding to cluster number
      assert_equal 1, (element['detail']['skills'].count{ |skill| skill.include?('cluster') })
    }

    # to make it hard to find original_id back :
    vrp[:vehicles].each{ |v|
      v[:id] = 'vehicle_cluster_' + v[:id]
    }
    vrp[:configuration][:preprocessing][:partitions].delete_if{ |partition| partition[:entity] == :work_day }
    response = post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    result = JSON.parse(response.body)['solutions'].first
    to_check = result['routes'].flat_map{ |route| route['activities'].select{ |stop| stop['type'] == 'service' } } + result['unassigned']
    to_check.each{ |element|
      # each element should have 2 skills added by clustering :
      assert_equal 2, element['detail']['skills'].size
      # - exactly 1 skill corresponding to vehicle_id entity
      assert(element['detail']['skills'].include?('vehicle_cluster_vehicle_0') ^ element['detail']['skills'].include?('vehicle_cluster_vehicle_1'))
      # - exactly 1 skill corresponding to cluster number
      assert_equal 1, (element['detail']['skills'].count{ |skill| skill.include?('cluster ') })
    }
  end

  def test_clustering_generated_files
    all_services_vrps = Marshal.load(File.binread('test/fixtures/cluster_to_output.bindump')) # rubocop: disable Security/MarshalLoad
    file = OutputHelper::Clustering.generate_files(all_services_vrps, true)
    generated_file = File.join(Api::V01::APIBase.dump_vrp_dir.cache, file)

    assert File.exist?(generated_file + '_geojson'), 'Geojson file not found'
    assert File.exist?(generated_file + '_csv'), 'Csv file not found'
    csv = CSV.parse(Api::V01::APIBase.dump_vrp_dir.read(file + '_csv'))

    assert_equal all_services_vrps.sum{ |service| service[:vrp].services.size } + 1, csv.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[3] }.uniq!.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[4] }.uniq!.size
    assert csv.all?{ |line| line[4].count(',').zero? }, 'There should be only one vehicle in vehicles_ids column'
    assert csv.none?{ |line| line[5].nil? }, 'All timewindows of this vehicle should be shown'
  end

  def test_clustering_generated_files_from_dicho
    all_services_vrps = Marshal.load(File.binread('test/fixtures/dicho_cluster_to_output.bindump')) # rubocop: disable Security/MarshalLoad
    file = OutputHelper::Clustering.generate_files(all_services_vrps)
    generated_file = File.join(Api::V01::APIBase.dump_vrp_dir.cache, file)

    assert File.exist?(generated_file + '_geojson'), 'Geojson file not found'
    assert File.exist?(generated_file + '_csv'), 'Csv file not found'
    csv = CSV.parse(Api::V01::APIBase.dump_vrp_dir.read(file + '_csv'))

    assert_equal all_services_vrps.sum{ |service| service[:vrp].services.size } + 1, csv.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[3] }.uniq!.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[4] }.uniq!.size
    assert_equal [nil], csv.collect(&:last).uniq! - ['vehicle_tw_if_only_one']
  end

  def test_scheduling_generated_file
    name = 'test'
    job = 'fake_job'
    schedule_end = 5

    output_tool = OutputHelper::Scheduling.new(name, 'fake_vehicles', job, schedule_end)
    file = 'scheduling_construction_test_fake_job'
    filepath = File.join(Api::V01::APIBase.dump_vrp_dir.cache, file)

    refute File.exist?(filepath), 'File created before end of generation'

    output_tool.add_comment('my comment')
    days = [0, 2, 4]
    output_tool.insert_visits(days, 'service_id', 3)
    output_tool.close_file

    assert File.exist?(filepath), 'File not found'

    csv = CSV.parse(Api::V01::APIBase.dump_vrp_dir.read(file))
    assert(csv.any?{ |line| line.first == 'my comment' })
    assert(csv.any?{ |line|
      line[0] == 'service_id' &&
        line[1] == '3' &&
        line[2] == 'X' && line[4] == 'X' && line[6] == 'X' &&
        line.count('X') == days.size
    })
  end

  def test_files_generated
    name = 'test_files_generated'
    OptimizerWrapper.config[:debug][:output_clusters] = true
    OptimizerWrapper.config[:debug][:output_schedule] = true

    vrp = TestHelper.load_vrp(self, fixture_file: 'instance_clustered')
    vrp.resolution_repetition = 1
    vrp[:name] = name
    vrp.preprocessing_partitions.each{ |partition| partition[:restarts] = 1 }

    Wrappers::SchedulingHeuristic.stub_any_instance(
      :compute_initial_solution,
      lambda { |vrp_in|
        @starting_time = Time.now

        check_solution_validity

        @output_tool&.close_file

        prepare_output_and_collect_routes(vrp_in)
      }
    ) do
      OptimizerWrapper.wrapper_vrp('demo', { services: { vrp: [:demo] }}, vrp, nil)
    end

    files = Find.find(OptimizerWrapper.dump_vrp_dir.cache).select { |path|
      path.include?(name)
    }

    assert_equal 3, files.size
    assert_includes files, File.join(OptimizerWrapper.dump_vrp_dir.cache, "scheduling_construction_#{name}")
    assert(files.any?{ |f| f.include?("generated_clusters_#{name}") && f.include?('csv') }, 'Geojson file not found')
    assert(files.any?{ |f| f.include?("generated_clusters_#{name}") && f.include?('json') }, 'Csv file not found')
  end

  def test_provided_language
    vrp = VRP.basic
    vrp[:configuration][:restitution] = { csv: true }

    [[nil, :legacy],
     ['fr', :fr],
     ['en', :en],
     ['de', :en]].each{ |provided, expected|
      OutputHelper::Result.stub(
        :build_csv,
        lambda { |_solutions|
          assert_equal expected, I18n.locale
        }
      ) do
        submit_csv api_key: 'demo', vrp: vrp, http_accept_language: provided
      end
    }

    [true, false].each{ |parameter_value|
      vrp[:configuration][:restitution][:use_deprecated_csv_headers] = parameter_value
      OutputHelper::Result.stub(
        :build_csv,
        lambda { |solutions|
          assert_equal parameter_value, solutions.first[:use_deprecated_csv_headers]
        }
      ) do
        submit_csv api_key: 'demo', vrp: vrp, http_accept_language: 'fr'
      end
    }
  end

  def test_returned_types
    complete_vrp = VRP.pud
    complete_vrp[:rests] = [{
      id: 'rest_0',
      duration: 1,
      timewindows: [{
        day_index: 0
      }]
    }]
    complete_vrp[:vehicles].first[:rest_ids] = ['rest_0']
    complete_vrp[:services] = [{
      id: 'service_0',
      activity: {
        point_id: 'point_0',
        timewindows: [{ start: 0, end: 1000 }]
      }
    }]
    complete_vrp[:configuration][:restitution] = { csv: true }

    type_index = nil

    [['en', ['stop type', 'rest', 'store', 'visit']],
     ['fr', ['type arrêt', 'pause', 'dépôt', 'visite']],
     ['es', ['tipo parada', 'descanso', 'depósito', 'visita']]].each{ |provided, translations|
      result = submit_csv api_key: 'ortools', vrp: complete_vrp, http_accept_language: provided
      type_index = result.first.find_index(translations[0])
      types = result.collect{ |line| line[type_index] }.compact - [translations[0]]
      assert_equal 3, types.uniq.size
      assert_equal 1, types.count(translations[1])
      assert_equal 2, types.count(translations[2])
      assert_equal 5, types.count(translations[3])
    }
  end

  def test_csv_configuration
    vrp = VRP.lat_lon
    vrp[:configuration][:restitution] = { csv: true }
    result = submit_csv api_key: 'demo', vrp: vrp
    assert_equal 10, result.size
  end

  def test_csv_configuration_asynchronously
    asynchronously start_worker: true do
      vrp = VRP.lat_lon
      vrp[:configuration][:restitution] = { csv: true }
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      result = wait_status_csv @job_id, 'completed', api_key: 'demo'
      assert_equal 9, result.count("\n")
    end
  end

  def test_returned_ids
    asynchronously start_worker: true do
      vrp = VRP.lat_lon
      vrp[:shipments] = [{
        id: 'shipment_0',
        pickup: {
          point_id: 'point_0',
          duration: 3,
          late_multiplier: 0,
        },
        delivery: {
          point_id: 'point_1',
          duration: 3,
          late_multiplier: 0,
        }
      }]
      vrp[:configuration][:restitution] = { csv: true }
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      result = wait_status_csv @job_id, 'completed', api_key: 'demo'
      csv = CSV.parse(result, headers: true)
      ids = csv.collect{ |line| line['id'] }
      assert_includes ids, 'shipment_0_pickup'
      assert_includes ids, 'shipment_0_delivery'
      vrp[:services].each{ |s|
        assert_includes ids, s[:id]
      }
    end
  end

  def test_returned_keys_csv
    methods = {
      vroom: {
        problem: VRP.lat_lon,
        solver_name: 'vroom',
        scheduling_keys: []
      },
      ortools: {
        problem: VRP.lat_lon,
        solver_name: 'ortools',
        scheduling_keys: []
      },
      periodic_ortools: {
        problem: VRP.lat_lon,
        solver_name: 'ortools',
        scheduling_keys: %w[day_week_num day_week day visit_index]
      },
      periodic_heuristic: {
        problem: VRP.lat_lon_scheduling,
        solver_name: 'heuristic',
        scheduling_keys: %w[day_week_num day_week day visit_index]
      }
    }

    expected_route_keys = %w[vehicle_id original_vehicle_id total_travel_time total_travel_distance total_waiting_time]
    expected_activities_keys = %w[point_id waiting_time begin_time end_time id original_id lat lon duration setup_duration additional_value skills tags]
    expected_unassigned_keys = %w[point_id id type unassigned_reason]

    [:ortools, :periodic_ortools].each{ |method| methods[method][:problem][:vehicles].first[:timewindow] = { start: 28800, end: 61200 } }
    dimensions = %i[time distance]

    methods.each{ |method, data|
      problem = data[:problem]
      problem[:matrices].each{ |matrix|
        dimensions.each{ |dimension|
          matrix[dimension].each{ |line| line << 2**32 }
          matrix[dimension] << [2**32] * matrix[dimension].first.size
        }
      }
      problem[:points] << { id: 'unreachable_point', matrix_index: problem[:matrices].first[:time].first.size - 1, location: { lat: 51.513402, lon: -0.217704 }}
      problem[:services] << { id: 'unfeasible_service', activity: { point_id: 'unreachable_point' }}
      problem[:configuration][:schedule] = { range_indices: { start: 0, end: 3 }} if method == :periodic_ortools
      problem[:configuration][:restitution] = { csv: true }
      response = post '/0.1/vrp/submit', { api_key: 'solvers', vrp: problem }.to_json, 'CONTENT_TYPE' => 'application/json'
      headers = response.body.slice(1..-1).split('\n').map{ |line| line.split(',') }.first
      assert_empty (expected_activities_keys - headers), "#{expected_activities_keys - headers} activity keys are missing in #{method}"
      assert_empty (expected_route_keys - headers - data[:scheduling_keys]), "#{expected_route_keys - headers} route keys are missing in #{method} result"
      assert_empty (expected_unassigned_keys - headers), "#{expected_unassigned_keys - headers} unassigned keys are missing in #{method}"

      undocumented = headers - expected_route_keys - expected_activities_keys - expected_unassigned_keys - data[:scheduling_keys]
      assert_empty undocumented, "#{undocumented} keys are not documented, found in #{method}"
    }
  end

  def test_geojsons_returned
    asynchronously start_worker: true do
      vrp = VRP.lat_lon_scheduling
      @job_id = submit_vrp api_key: 'demo', vrp: vrp
      result = wait_status @job_id, 'completed', api_key: 'demo'
      assert_nil(result['geojsons'])

      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = [TestHelper.vehicle_and_days_partitions[0]]
      vrp[:configuration][:restitution] = { geometry: [:partitions] }
      @job_id = submit_vrp api_key: 'ortools', vrp: vrp
      result = wait_status @job_id, 'completed', api_key: 'ortools'
      refute(result['geojsons'].first['partitions'].key?('work_day'))
      # points should always be returned
      refute_empty(result['geojsons'].first['points'])

      # TODO : remove when returning polylines is more performant and we allow this field in geometry :
      vrp[:configuration][:restitution] = { geometry: [:partitions, :polylines] }
      @job_id = submit_vrp api_key: 'ortools', vrp: vrp
      result = wait_status @job_id, 'completed', api_key: 'ortools'
      refute(result['geojsons'].first.key?('polylines'))
    end

    skip 'Remaining part of this test is skipped because at the moment POST does not return the same result as GET ' \
         '(geojsons is missing); therefore, we need to solve asynchronously but there is a router call and we ' \
         'cannot stub the child process. When the output of POST (synchronous) is the same as GET, this skip ' \
         'can be removed.'

    Routers::RouterWrapper.stub_any_instance(:compute_batch, proc{
      # returns a "truncated" trace, so there will be a jump in the traced path -- original trace has 1000 elements
      [
        [43509.5, 3445.0,
         [[4.951508, 45.28878], [4.951576, 45.288794], [4.951641, 45.289357], [4.951813, 45.290831],
          [4.951879, 45.29089], [4.951922, 45.290928], [4.814183, 45.57754], [4.814562, 45.577271],
          [4.814954, 45.576971], [4.815017, 45.576681], [4.815017, 45.576681]]],
        [44020.8, 3514.8,
         [[4.815017, 45.576681], [4.815017, 45.576681], [4.814954, 45.576971], [4.814562, 45.577271],
          [4.814183, 45.57754], [4.814404, 45.577721], [4.950599, 45.288599], [4.950724, 45.288624],
          [4.951164, 45.288722], [4.951455, 45.288769], [4.951508, 45.28878]]]
      ]
    }) do
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      vrp[:configuration][:restitution] = { geometry: [:polylines, :partitions] }
      assert submit_vrp api_key: 'ortools', vrp: vrp
      result = JSON.parse(last_response.body)
      assert(result['geojsons'].first['polylines']['features'].all?{ |f| f['properties']['color'] })
      assert_equal ['vehicle', 'work_day'], result['geojsons'].first['partitions'].keys
      assert(result['geojsons'].first['partitions']['vehicle']['features'].all?{ |f| f['properties']['color'] })
      assert(result['geojsons'].first['partitions']['work_day']['features'].all?{ |f| f['properties']['color'] })
    end
  end

  def test_csv_headers_compatible_with_import_according_to_language
    vrp = VRP.lat_lon_capacitated
    vrp[:services].first[:activity][:timewindows] = [{ start: 0, end: 10 }]
    vrp[:vehicles].each{ |v| v[:timewindow] = { start: 0, end: 10000 } }
    vrp[:configuration][:preprocessing] = { first_solution_strategy: ['periodic'] }
    vrp[:configuration][:schedule] = { range_indices: { start: 0, end: 2 }}
    vrp[:configuration][:restitution] = { csv: true }

    # checks columns headers when required for import
    expected_headers = {
      en: ['plan', 'reference plan', 'route', 'name', 'lat', 'lng', 'stop type', 'time', 'end time',
           'duration per destination', 'visit duration', 'tags visit', 'tags', 'quantity[kg]',
           'time window start 1', 'time window end 1', 'vehicle', 'reference'],
      es: [
        'plan', 'referencia del plan', 'gira', 'nombre', 'tipo parada', 'lat', 'lng', 'hora', 'fin',
        'horario inicio 1', 'horario fin 1', 'duración de preparación', 'duración visita', 'cantidad[kg]',
        'etiquetas visita', 'etiquetas', 'vehículo', 'referencia visita'],
      fr: ['plan', 'référence plan', 'tournée', 'nom', 'lat', 'lng', 'type arrêt', 'heure',
           'fin de la mission', 'durée client', 'durée visite', 'libellés visite', 'libellés',
           'quantité[kg]', 'horaire début 1', 'horaire fin 1', 'véhicule', 'référence visite']
    }

    asynchronously start_worker: true do
      expected_headers.each{ |languague, expected_list|
        @job_id = submit_csv api_key: 'ortools', vrp: vrp
        wait_status_csv @job_id, 200, api_key: 'ortools', http_accept_language: languague
        current_headers = last_response.body.split("\n").first.split(',')
        assert_empty expected_list - current_headers

        delete_completed_job @job_id, api_key: 'ortools'
      }
    end
  end

  def test_use_deprecated_csv_headers_asynchronously
    vrp = VRP.lat_lon
    vrp[:configuration][:restitution] = { csv: true }

    legacy_basic_headers = %w[vehicle_id id point_id type begin_time end_time setup_duration duration skills]
    french_basic_headers = ['tournée', 'référence', 'heure', 'fin de la mission', 'durée client', 'durée visite', 'libellés']
    [[true, legacy_basic_headers],
     [false, french_basic_headers]].each{ |parameter, expected|

      vrp[:configuration][:restitution][:use_deprecated_csv_headers] = parameter

      asynchronously start_worker: true do
        @job_id = submit_csv api_key: 'demo', vrp: vrp, http_accept_language: 'fr'
        wait_status_csv @job_id, 200, api_key: 'demo', http_accept_language: 'fr'
        current_headers = last_response.body.split("\n").first.split(',')
        assert_empty expected - current_headers

        delete_completed_job @job_id, api_key: 'ortools'
      end
    }
  end
end
