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
require './test/api/v01/helpers/request_helper'

class Api::V01::VrpTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    Api::Root
  end

  def test_submit_vrp_in_queue
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_dont_ignore_legitimate_skills
    OptimizerWrapper.stub(
      :define_main_process,
      lambda { |services_vrps, _job|
        assert_equal [[:skill]], services_vrps[0][:vrp][:vehicles][0][:skills]
        assert_equal [:skill], services_vrps[0][:vrp][:services][0][:skills]
        assert_equal [[]], services_vrps[0][:vrp][:vehicles][1][:skills]
        assert_equal [], services_vrps[0][:vrp][:services][1][:skills]
        {}
      }
    ) do
      vrp = VRP.toy
      vrp[:vehicles] << vrp[:vehicles][0].dup
      vrp[:vehicles].last[:id] += '_bis'
      vrp[:services] << vrp[:services][0].dup
      vrp[:services].last[:id] += '_bis'
      vrp[:vehicles][0][:skills] = [['skill']]
      vrp[:services][0][:skills] = ['skill']
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_generated_vehicle_skills
    problem = VRP.basic
    [nil, [], [[]],
     'skill1', [['skill1']],
     'skill1,skill2', [['skill1', 'skill2']]
    ].each_with_index{ |skill_set, v_i|
      problem[:vehicles] << problem[:vehicles].first.dup unless v_i == 0
      problem[:vehicles][v_i][:id] = "vehicle_#{v_i}"
      problem[:vehicles][v_i][:skills] = skill_set
    }
    problem[:services].first[:skills] = ['skill1', 'skill2'] # otherwise skills will be ignored in vehicles

    OptimizerWrapper.stub(
      :define_main_process,
      lambda { |services_vrps, _job|
        vrp = services_vrps[0][:vrp]
        [[[]], [[]], [[]],
         [[:skill1]], [[:skill1]],
         [[:skill1, :skill2]], [[:skill1, :skill2]]
        ].each_with_index{ |expected_skills, v_i|
          assert_equal vrp.vehicles[v_i].skills, expected_skills
        }
        {}
      }
    ) do
      submit_vrp api_key: 'demo', vrp: problem
    end
  end

  def test_exceed_params_limit
    vrp = VRP.toy
    vrp[:points] *= 151
    post '/0.1/vrp/submit', api_key: 'quota', vrp: vrp
    assert_equal 413, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'Exceeded points limit authorized'
  end

  def test_ignore_unknown_parameters
    vrp = VRP.toy
    vrp[:points][0][:unknown_parameter] = 'test'
    vrp[:configuration][:unknown_parameter] = 'test'
    vrp[:unknown_parameter] = 'test'
    submit_vrp api_key: 'demo', vrp: vrp
  end

  def test_refute_solver_and_solver_parameter
    vrp = VRP.toy
    vrp[:configuration][:resolution][:solver] = true
    vrp[:configuration][:resolution][:solver_parameter] = 0
    post '/0.1/vrp/submit', api_key: 'demo', vrp: vrp
    assert_equal 400, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'vrp[configuration][resolution][solver], vrp[configuration][resolution][solver_parameter] are mutually exclusive'
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
    OptimizerWrapper.stub(
      :wrapper_vrp,
      lambda { |_api_key, _services, vrp_in, _checksum|
        assert_equal 12 * 3600, vrp_in.vehicles.first.duration
        assert_equal 20 * 60, vrp_in.services.first.activity.duration
        assert_equal 80, vrp_in.services.first.activity.timewindows.first.start
        assert_equal 800, vrp_in.services.first.activity.timewindows.first.end
        'job_id'
      }
    ) do
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_nil_duration
    vrp = VRP.toy
    vrp[:vehicles][0][:duration] = nil
    vrp[:vehicles][0][:overall_duration] = nil
    OptimizerWrapper.stub(
      :wrapper_vrp,
      lambda { |_api_key, _services, vrp_in, _checksum|
        assert_nil vrp_in.vehicles.first.duration
        assert_nil vrp_in.vehicles.first.overall_duration
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
    assert_includes JSON.parse(last_response.body)['message'], 'is empty'
  end

  def test_first_solution_strategy_param
    vrp = VRP.toy
    vrp[:configuration][:preprocessing] = { first_solution_strategy: 'a, b ' }
    OptimizerWrapper.stub(
      :wrapper_vrp,
      lambda { |_api_key, _services, vrp_in, _checksum|
        assert_equal ['a', 'b'], vrp_in.preprocessing_first_solution_strategy
        'job_id'
      }
    ) do
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_list_vrp
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'demo'
    assert_equal 200, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_list_vrp
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'vroom'
    assert_equal 200, last_response.status, last_response.body
    refute_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_get_vrp
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get "/0.1/vrp/jobs/#{@job_id}", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'not found'
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_delete_vrp
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete_job @job_id, api_key: 'demo'
    assert_equal 202, last_response.status, last_response.body
    get "0.1/vrp/jobs/#{@job_id}.json", api_key: 'demo'
    assert_equal 404, last_response.status, last_response.body
  end

  def test_cannot_delete_vrp
    asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete "0.1/vrp/jobs/#{@job_id}.json", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'not found'
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_get_completed_job_with_solution_dump
    old_config_dump_solution = OptimizerWrapper.config[:dump][:solution]
    OptimizerWrapper.config[:dump][:solution] = true
    asynchronously start_worker: true do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
      wait_status @job_id, 'completed', api_key: 'demo'
    end

    get "/0.1/vrp/jobs/#{@job_id}", api_key: 'demo'
    assert_equal 200, last_response.status, last_response.body
    assert_equal 'completed', JSON.parse(last_response.body)['job']['status'], last_response.body
  ensure
    OptimizerWrapper.config[:dump][:solution] = old_config_dump_solution
  end

  def test_get_deletes_completed_job
    # create a "completed" job with an unused uuid
    uuid = Resque::Plugins::Status::Hash.generate_uuid until !uuid.nil? && Resque::Plugins::Status::Hash.get(uuid).nil?
    Resque::Plugins::Status::Hash.create(uuid, { 'status' => 'completed', 'options' => { 'api_key' => 'demo' } })

    wait_status uuid, 'completed', api_key: 'demo'

    delete_completed_job uuid, api_key: 'demo'
  ensure
    Resque::Plugins::Status::Hash.remove(uuid)
  end

  def test_block_call_under_clustering
    vrp1 = VRP.lat_lon_periodic_two_vehicles
    vrp1[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions

    vrp2 = VRP.independent_skills
    vrp2[:points] = VRP.lat_lon_periodic[:points]
    vrp2[:services].first[:skills] = ['D']
    vrp2[:configuration][:preprocessing] = {
      max_split_size: 4,
      partitions: [
        { method: 'balanced_kmeans', metric: 'duration', entity: :vehicle }
      ]
    }

    asynchronously start_worker: true do
      [vrp1, vrp2].each{ |vrp|
        @job_id = submit_vrp(api_key: 'demo', vrp: vrp)
        response = wait_status @job_id, 'completed', api_key: 'demo'
        refute_empty response['solutions'].to_a, "Solution is missing from the response body: #{response}"
        delete_completed_job @job_id, api_key: 'demo'
      }
    end
  end

  def test_unfounded_avancement_message_change
    lines_with_avancement = ''
    Dir.mktmpdir('temp_', 'test/') { |tmpdir|
      begin
        previous = { log_level: ENV['LOG_LEVEL'], log_device: ENV['LOG_DEVICE'], repetition: OptimizerWrapper.config[:solve][:repetition] }
        output = Tempfile.new('avencement-output', tmpdir)
        output.sync = true
        ENV['LOG_LEVEL'] = 'info'
        ENV['LOG_DEVICE'] = output.path
        OptimizerWrapper.config[:solve][:repetition] = 2

        asynchronously start_worker: true do
          vrp = VRP.lat_lon_periodic_two_vehicles
          vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
          @job_id = submit_vrp(api_key: 'demo', vrp: vrp)
          wait_status @job_id, 'completed', api_key: 'demo'
          output.flush
        end
        delete_completed_job @job_id, api_key: 'demo' if @job_id

        lines_with_avancement = output.grep(/avancement/)
      ensure
        ENV['LOG_LEVEL'] = previous[:log_level]
        ENV['LOG_DEVICE'] = previous[:log_device]
        OptimizerWrapper.config[:solve][:repetition] = previous[:repetition]
        output&.close
        output&.unlink
      end
    }

    assert_msg = "\nThe structure of avancement message has changed! If the modification is on purpose " \
                 "fix this test \n(#{self.class.name}::#{self.name}) to represent the actual functionality."
    # Currently the expected output is in the following form
    # [date time] jobid - INFO: avancement: repetition (1..2)/2 - clustering phase (y: 1..2)/2 - step (1..y)/(y)
    # [date time] jobid - INFO: avancement: repetition (1..2)/2 - process (1..9)/10 - solving periodic heuristic

    lines_with_avancement.each{ |line|
      date_time_jobid = '\[(?<date>[0-9-]*) (?<hour>[0-9: +]*)\] (?<job_id>[0-9a-z]*)'
      # There needs to be avancement and repetition
      %r{#{date_time_jobid} - INFO: avancement: repetition [1-2]/2 - (?<rest>.*)\n} =~ line

      refute_nil Regexp.last_match, assert_msg
      refute_nil Regexp.last_match(:date)&.to_date, assert_msg
      refute_nil Regexp.last_match(:hour)&.to_time, assert_msg

      rest = Regexp.last_match(:rest)

      # The rest needs to be either clustering or heuristic solution
      %r{clustering phase [1-2]/2 - step [1-2]/[1-2] } =~ rest || %r{process [1-9]/8 - periodic heuristic } =~ rest

      refute_nil Regexp.last_match, assert_msg
    }
  end

  def test_submit_without_schedule_start_should_break
    vrp_no_sched_start = VRP.periodic
    vrp_no_sched_start[:configuration][:schedule] = { range_indices: { start: 0 } }
    post '/0.1/vrp/submit', {api_key: 'demo', vrp: vrp_no_sched_start}.to_json, 'CONTENT_TYPE' => 'application/json'
    assert_equal 400, last_response.status
    assert_includes(JSON.parse(last_response.body)['message'], 'vrp[configuration][schedule][range_indices][end] is missing')
  end

  def test_ask_for_geometry
    [false, true, true, # boolean
     ['polylines'], [:polylines], [:polylines, 'partitions'], ['unexistant'], # array of string or symbol
     'partitions', 'polylines,partitions', 'polylines, encoded_polylines' # string to be converted into an array
    ].each_with_index{ |geometry_field, case_index|
      OptimizerWrapper.stub(:define_main_process, lambda { |services_vrps, _job|
          case case_index
          when 0
            assert_empty services_vrps.first[:vrp].restitution_geometry
          when 1
            assert_equal %i[polylines], services_vrps.first[:vrp].restitution_geometry
          when 2
            assert_equal %i[encoded_polylines], services_vrps.first[:vrp].restitution_geometry
          when 5 || 8
            assert_equal %i[partitions], services_vrps.first[:vrp].restitution_geometry
          when 3 || 4
            assert_empty services_vrps.first[:vrp].restitution_geometry
          when 7
            assert_equal %i[partitions], services_vrps.first[:vrp].restitution_geometry
          end
          {}
        }
      ) do
        vrp = VRP.toy
        vrp[:configuration][:restitution] = { geometry: geometry_field }
        vrp[:configuration][:restitution][:geometry_polyline] = true if case_index == 2
        if [6, 9].include?(case_index)
          post '/0.1/vrp/submit', { api_key: 'demo', vrp: vrp }.to_json, 'CONTENT_TYPE' => 'application/json'
          assert_includes [400], last_response.status
        else
          submit_vrp api_key: 'demo', vrp: vrp
        end
      end
    }
  end
end
