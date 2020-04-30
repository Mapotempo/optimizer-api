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
require './api/root'

require './test/api/v01/request_helper'

class Api::V01::VrpTest < Api::V01::RequestHelper
  include Rack::Test::Methods

  def app
    Api::Root
  end

  # Unit tests
  def test_submit_vrp_in_queue
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_submit_vrp
    post '/0.1/vrp/submit', api_key: '!', vrp: VRP.toy
    assert_equal 401, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['error'], 'Unauthorized'
  end

  def test_dont_ignore_legitimate_skills
    OptimizerWrapper.stub(
      :define_main_process,
      lambda { |services_vrps, _job|
        assert_equal [['skill']], services_vrps[0][:vrp][:vehicles][0][:skills]
        assert_equal ['skill'], services_vrps[0][:vrp][:services][0][:skills]
        assert_equal [[]], services_vrps[0][:vrp][:vehicles][1][:skills]
        assert_equal [], services_vrps[0][:vrp][:services][1][:skills]
        {}
      }
    ) do
      vrp = VRP.toy
      vrp[:vehicles] << vrp[:vehicles][0].dup
      vrp[:services] << vrp[:services][0].dup
      vrp[:vehicles][0][:skills] = [['skill']]
      vrp[:services][0][:skills] = ['skill']
      submit_vrp api_key: 'demo', vrp: vrp
    end
  end

  def test_exceed_params_limit
    vrp = VRP.toy
    vrp[:points] *= 151
    post '/0.1/vrp/submit', api_key: 'vroom', vrp: vrp
    assert_equal 400, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'Exceeded points limit authorized'
  end

  def test_ignore_unknown_parameters
    vrp = VRP.toy
    vrp[:points][0][:unknown_parameter] = 'test'
    vrp[:configuration][:unknown_parameter] = 'test'
    vrp[:unknown_parameter] = 'test'
    submit_vrp api_key: 'demo', vrp: vrp
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

  def test_first_solution_strategie_param
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
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'demo'
    assert_equal 200, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_list_vrp
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get '/0.1/vrp/jobs', api_key: 'vroom'
    assert_equal 200, last_response.status, last_response.body
    refute_includes JSON.parse(last_response.body).map{ |a| a['uuid'] }, @job_id
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_cannot_get_vrp
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    get "/0.1/vrp/jobs/#{@job_id}", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
    assert_equal JSON.parse(last_response.body)['status'], 'Not Found'
    assert_includes JSON.parse(last_response.body)['message'], 'not found'
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_delete_vrp
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete_job @job_id, api_key: 'demo'
    assert_equal 202, last_response.status, last_response.body
    get "0.1/vrp/jobs/#{@job_id}.json", api_key: 'demo'
    assert_equal 404, last_response.status, last_response.body
  end

  def test_cannot_delete_vrp
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'demo', vrp: VRP.toy
    end

    delete "0.1/vrp/jobs/#{@job_id}.json", api_key: 'vroom'
    assert_equal 404, last_response.status, last_response.body
    assert_includes JSON.parse(last_response.body)['message'], 'not found'
  ensure
    delete_job @job_id, api_key: 'demo'
  end

  def test_block_call_under_clustering
    @job_ids = []
    TestHelper.solve_asynchronously do
      vrp = VRP.lat_lon_scheduling_two_vehicles
      vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
      @job_ids << submit_vrp(api_key: 'ortools', vrp: vrp)
      wait_status @job_ids.last, 'completed', api_key: 'ortools'
      refute JSON.parse(last_response.body)['solutions'].nil? || JSON.parse(last_response.body)['solutions'].empty?

      vrp = VRP.independent_skills
      vrp[:points] = VRP.lat_lon_scheduling[:points]
      vrp[:services].first[:skills] = ['D']
      vrp[:configuration][:preprocessing] = {
        max_split_size: 4,
        partitions: [
          { method: 'balanced_kmeans', metric: 'duration', entity: 'vehicle' }
        ]
      }
      @job_ids << submit_vrp(api_key: 'ortools', vrp: vrp)
      wait_status @job_ids.last, 'completed', api_key: 'ortools'
      refute JSON.parse(last_response.body)['solutions'].nil? || JSON.parse(last_response.body)['solutions'].empty?
    end
  ensure
    @job_ids.each{ |job_id|
      delete_completed_job job_id, api_key: 'ortools'
    }
  end

  def test_unfounded_avancement_message_change
    lines_with_avancement = ''
    Dir.mktmpdir('temp_', 'test/') { |tmpdir|
      begin
        previous = { log_level: ENV['LOG_LEVEL'], log_device: ENV['LOG_DEVICE'], repetition: OptimizerWrapper.config[:solve][:repetition] }
        output = Tempfile.new('avencement-output', tmpdir)
        ENV['LOG_LEVEL'] = 'info'
        ENV['LOG_DEVICE'] = output.path
        OptimizerWrapper.config[:solve][:repetition] = 2

        TestHelper.solve_asynchronously do
          vrp = VRP.lat_lon_scheduling_two_vehicles
          vrp[:configuration][:preprocessing][:partitions] = TestHelper.vehicle_and_days_partitions
          @job_id = submit_vrp(api_key: 'ortools', vrp: vrp)
          wait_status @job_id, 'completed', api_key: 'ortools'
        end

        lines_with_avancement = output.grep(/avancement/)
      ensure
        ENV['LOG_LEVEL'] = previous[:log_level]
        ENV['LOG_DEVICE'] = previous[:log_device]
        OptimizerWrapper.config[:solve][:repetition] = previous[:repetition]
        output&.unlink
        delete_completed_job @job_id, api_key: 'ortools' if @job_id
      end
    }

    assert_msg = "\nThe structure of avancement message has changed! If the modification is on purpose " \
                 "fix this test \n(#{self.class.name}::#{self.name}) to represent the actual functionality."
    # Currently the expected output is in the following form
    # [date time] jobid - INFO: avancement: repetition (1..2)/2 - clustering phase (y: 1..2)/2 - step (1..y)/(y)
    # [date time] jobid - INFO: avancement: repetition (1..2)/2 - process (1..9)/10 - solving scheduling heuristic

    lines_with_avancement.each{ |line|
      date_time_jobid = '\[(?<date>[0-9-]*) (?<hour>[0-9: +]*)\] (?<job_id>[0-9a-z]*)'
      # There needs to be avancement and repetition
      %r{#{date_time_jobid} - INFO: avancement: repetition [1-2]/2 - (?<rest>.*)\n} =~ line

      refute_nil Regexp.last_match, assert_msg
      refute_nil Regexp.last_match(:date)&.to_date, assert_msg
      refute_nil Regexp.last_match(:hour)&.to_time, assert_msg

      rest = Regexp.last_match(:rest)

      # The rest needs to be either clustering or heuristic solution
      %r{clustering phase [1-2]/2 - step [1-2]/[1-2] } =~ rest || %r{process [1-9]/10 - solving scheduling heuristic } =~ rest

      refute_nil Regexp.last_match, assert_msg
    }
  end

  def test_remove_unecessary_units
    vrp = TestHelper.load_vrp(self)
    assert_empty vrp.units
    vrp.vehicles.all?{ |v| v.capacities.empty? }
    vrp.services.all?{ |s| s.quantities.empty? }
  end

  def test_remove_unecessary_units_one_needed
    vrp = TestHelper.load_vrp(self)
    assert_equal 1, vrp.units.size
    assert_operator vrp.vehicles.collect{ |v| v.capacities.collect(&:unit_id) }.flatten.uniq,
                    :==,
                    vrp.services.collect{ |s| s.quantities.collect(&:unit_id) }.flatten.uniq
  end

  def test_vrp_creation_if_route_and_partitions
    vrp = VRP.lat_lon_scheduling_two_vehicles
    vrp[:routes] = [{
      vehicle_id: 'vehicle_0',
      mission_ids: ['service_1']
    }, {
      vehicle_id: 'vehicle_1',
      mission_ids: ['service_7']
    }]
    vrp[:configuration][:preprocessing] = {
      partitions: TestHelper.vehicle_and_days_partitions
    }

    vrp = TestHelper.create(vrp)
    assert_equal 2, (vrp.services.count{ |s| !s.sticky_vehicles.empty? })
    assert_equal 'vehicle_0', vrp.services.find{ |s| s.id == 'service_1' }.sticky_vehicles.first.id
    assert_equal 'vehicle_1', vrp.services.find{ |s| s.id == 'service_7' }.sticky_vehicles.first.id
  end
end
