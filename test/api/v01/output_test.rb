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
require 'minitest/around/unit'

class Api::V01::OutputTest < Api::V01::RequestHelper
  include Rack::Test::Methods

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

  def test_day_week_num
    vrp = VRP.scheduling
    vrp[:configuration][:restitution] = { csv: true }

    csv_data = submit_csv api_key: 'demo', vrp: vrp
    assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
    assert_includes csv_data.first, 'day_week'
    assert_includes csv_data.first, 'day_week_num'
  end

  def test_no_day_week_num
    vrp = VRP.basic
    vrp[:configuration][:restitution] = { csv: true }

    csv_data = submit_csv api_key: 'demo', vrp: vrp
    assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
    refute_includes csv_data.first, 'day_week'
    refute_includes csv_data.first, 'day_week_num'
  end

  def test_skill_when_partitions
    vrp = VRP.lat_lon
    vrp[:vehicles] << vrp[:vehicles][0].dup
    vrp[:configuration][:restitution] = { csv: true }
    vrp[:configuration][:preprocessing] = {
      partitions: [{
        method: 'balanced_kmeans',
        metric: 'duration',
        entity: :vehicle
      }]
    }

    csv_data = submit_csv api_key: 'demo', vrp: vrp
    assert_equal csv_data.collect(&:size).max, csv_data.collect(&:size).first
    assert(csv_data.select{ |line| line[csv_data.first.find_index('type')] == 'visit' }.all?{ |line| line[csv_data.first.find_index('skills')] && line[csv_data.first.find_index('skills')] != '' })
  end

  def test_clustering_generated_files
    all_services_vrps = Marshal.load(File.binread('test/fixtures/cluster_to_output.bindump')) # rubocop: disable Security/MarshalLoad
    file = OutputHelper::Clustering.generate_files(all_services_vrps, true)
    generated_file = File.join(Api::V01::APIBase.dump_vrp_dir.cache, file)

    assert File.exist?(generated_file + '_geojson'), 'Geojson file not found'
    assert File.exist?(generated_file + '_csv'), 'Csv file not found'
    csv = CSV.read(generated_file + '_csv')

    assert_equal all_services_vrps.collect{ |service| service[:vrp].services.size }.sum + 1, csv.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[3] }.uniq.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[4] }.uniq.size
    assert csv.all?{ |line| line[4].count(',').zero? }, 'There should be only one vehicle in vehicles_ids column'
    assert csv.none?{ |line| line[5].nil? }, 'All timewindows of this vehicle should be shown'
  end

  def test_clustering_generated_files_from_dicho
    all_services_vrps = Marshal.load(File.binread('test/fixtures/dicho_cluster_to_output.bindump')) # rubocop: disable Security/MarshalLoad
    file = OutputHelper::Clustering.generate_files(all_services_vrps)
    generated_file = File.join(Api::V01::APIBase.dump_vrp_dir.cache, file)

    assert File.exist?(generated_file + '_geojson'), 'Geojson file not found'
    assert File.exist?(generated_file + '_csv'), 'Csv file not found'
    csv = CSV.read(generated_file + '_csv')

    assert_equal all_services_vrps.collect{ |service| service[:vrp].services.size }.sum + 1, csv.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[3] }.uniq.size
    assert_equal all_services_vrps.size + 1, csv.collect{ |line| line[4] }.uniq.size
    assert_equal [nil], csv.collect(&:last).uniq - ['vehicle_tw_if_only_one']
  end

  def test_scheduling_generated_file
    name = 'test'
    job = 'fake_job'
    schedule_end = 5

    output_tool = OutputHelper::Scheduling.new(name, 'fake_vehicles', job, schedule_end)
    file_name = File.join(Api::V01::APIBase.dump_vrp_dir.cache, 'scheduling_construction_test_fake_job')

    refute File.exist?(file_name), 'File created before end of generation'

    output_tool.add_comment('my comment')
    days = [0, 2, 4]
    output_tool.insert_visits(days, 'service_id', 3)
    output_tool.close_file

    assert File.exist?(file_name), 'File not found'

    csv = CSV.read(file_name)
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

    Heuristics::Scheduling.stub_any_instance(
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

    OptimizerWrapper.stub(
      :build_csv,
      lambda { |_solutions|
        assert_equal :en, I18n.locale
      }
    ) do
      post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
    end

    OptimizerWrapper.stub(
      :build_csv,
      lambda { |_solutions|
        assert_equal :fr, I18n.locale
      }
    ) do
      post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT_LANGUAGE' => 'fr'
    end

    OptimizerWrapper.stub(
      :build_csv,
      lambda { |_solutions|
        assert_equal :en, I18n.locale
      }
    ) do
      post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json', 'HTTP_ACCEPT_LANGUAGE' => 'bad_value'
    end
  end

  def test_csv_configuration
    vrp = VRP.lat_lon
    vrp[:configuration][:restitution] = { csv: true }
    result = submit_csv api_key: 'demo', vrp: vrp
    assert_equal 10, result.size
  end

  def test_csv_configuration_asynchronously
    TestHelper.solve_asynchronously do
      vrp = VRP.lat_lon
      vrp[:configuration][:restitution] = { csv: true }
      @job_id = submit_csv api_key: 'demo', vrp: vrp
      result = wait_status_csv @job_id, 'completed', api_key: 'demo'
      assert_equal 9, result.count("\n")
    end
  end

  def test_returned_ids
    TestHelper.solve_asynchronously do
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
      csv = result.split("\n")
      ids = csv.collect{ |line| line.split(',')[1] }
      assert_includes ids, 'shipment_0_pickup'
      assert_includes ids, 'shipment_0_delivery'
      vrp[:services].each{ |s|
        assert_includes ids, s[:id]
      }
    end
  end
end
