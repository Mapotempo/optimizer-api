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

class Api::V01::WithSolverTest < Minitest::Test
  include Rack::Test::Methods
  include TestHelper

  def app
    Api::Root
  end

  def test_deleted_job
    # using ORtools to make sure that optimization takes enough time to be cut before ending
    asynchronously start_worker: true do
      vrp = VRP.lat_lon.deep_merge!({ configuration: { restitution: { intermediate_solutions: true }}})
      @job_id = submit_vrp api_key: 'ortools', vrp: vrp
      response = wait_avancement_match @job_id, /run optimization, iterations [0-9]+/, api_key: 'ortools'
      refute_empty response['solutions'].to_a, "Solution is missing from the response body: #{response}"
      response = delete_job @job_id, api_key: 'ortools'
      refute_empty response['solutions'].to_a, "Solution is missing from the response body: #{response}"
    end
    delete_completed_job @job_id, api_key: 'ortools' if @job_id
  end

  def test_using_two_solver
    asynchronously start_worker: true do
      problem = VRP.lat_lon
      problem[:vehicles].first[:end_point_id] = nil
      problem[:vehicles] << Oj.load(Oj.dump(problem[:vehicles].first))
      problem[:vehicles].last[:id] = 'vehicle_1'
      problem[:vehicles].last[:start_point_id] = nil

      problem[:services][0][:sticky_vehicle_ids] = ['vehicle_0']
      problem[:services][1][:sticky_vehicle_ids] = ['vehicle_0']
      problem[:services][2][:sticky_vehicle_ids] = ['vehicle_0']
      problem[:services][3][:sticky_vehicle_ids] = ['vehicle_1']
      problem[:services][4][:sticky_vehicle_ids] = ['vehicle_1']
      problem[:services][5][:sticky_vehicle_ids] = ['vehicle_1']

      @job_id = submit_vrp api_key: 'solvers', vrp: problem
      result = wait_status @job_id, 'completed', api_key: 'solvers'
      assert_equal 'vroom', result['solutions'][0]['solvers'][0], "result['solutions'][0]['solvers'][0]"
      assert_equal 'ortools', result['solutions'][0]['solvers'][1], "result['solutions'][0]['solvers'][1]"
    end
    delete_completed_job @job_id, api_key: 'solvers' if @job_id
  end

  def test_returned_graph
    # using ORtools to make sure that optimization generates graph
    asynchronously start_worker: true do
      vrp = VRP.lat_lon
      vrp[:configuration][:resolution][:duration] = 20
      @job_id = submit_vrp api_key: 'ortools', vrp: vrp
      result = wait_status @job_id, 'completed', api_key: 'ortools'
      assert_operator result['job']['graph'].size, :>, 1,
                      'Graph seems to have been overwritten at each call to blockcall'
    end
    delete_completed_job @job_id, api_key: 'ortools' if @job_id
  end

  def test_filter_intermediate_solution
    # Verify that intermediate solution are correctly filtered
    asynchronously start_worker: true do
      vrp = VRP.lat_lon
      vrp[:configuration][:resolution][:duration] = 2000
      vrp[:units] = [{ id: 'unit_1' }]
      vrp[:services].each{ |s|
        s[:quantities] = [{ unit_id: 'unit_1', value: 1 }]
      }
      vrp[:services] << {
        id: 'vidage_1',
        activity: {
          point_id: 'point_0'
        },
        quantities: [{
          unit_id: 'unit_1',
          empty: true
        }]
      }
      vrp[:vehicles].first[:capacities] = [{ unit_id: 'unit_1', limit: 10 }]
      vrp[:services] << vrp[:services].last.dup.tap{ |s| s[:id] = 'vidage_2' }
      vrp[:configuration][:restitution][:intermediate_solutions] = true
      @job_id = submit_vrp api_key: 'ortools', vrp: vrp
      result = wait_avancement_match(@job_id, /run optimization, iterations/, api_key: 'ortools')
      assert_equal "Duplicate empty service.", result['solutions'].first['unassigned'].first['reason']
    end
    delete_job(@job_id, api_key: 'ortools') if @job_id
  end
end
