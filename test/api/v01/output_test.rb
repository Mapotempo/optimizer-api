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
    vrp = VRP.basic
    vrp[:configuration][:restitution] = { csv: true }
    vrp[:configuration][:preprocessing][:partitions] = [{
      method: 'balanced_kmeans',
      metric: 'duration', # generates warning in output
      entity: 'vehicle' # generates warning in output
    }]

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
    output_tool.output_scheduling_insert(days, 'service_id', 3)
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
        check_solution_validity

        @output_tool&.close_file

        prepare_output_and_collect_routes(vrp_in)
      }
    ) do
      OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
    end

    files = Find.find(OptimizerWrapper.dump_vrp_dir.cache).select { |path|
      path.include?(name)
    }

    assert_equal 3, files.size
    assert_includes files, File.join(OptimizerWrapper.dump_vrp_dir.cache, "scheduling_construction_#{name}")
    assert(files.any?{ |f| f.include?("generated_clusters_#{name}") && f.include?('csv') }, 'Geojson file not found')
    assert(files.any?{ |f| f.include?("generated_clusters_#{name}") && f.include?('json') }, 'Csv file not found')
  end
end
