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

class Api::V01::WithSolverTest < Api::V01::RequestHelper
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def test_deleted_job
    # using ORtools to make sure that optimization takes enough time to be cut before ending
    TestHelper.solve_asynchronously do
      @job_id = submit_vrp api_key: 'ortools', vrp: VRP.lat_lon
      wait_status @job_id, 'working', api_key: 'ortools'
      refute JSON.parse(last_response.body)['solutions'].nil? || JSON.parse(last_response.body)['solutions'].empty?
      delete_job @job_id, api_key: 'ortools'
      refute JSON.parse(last_response.body)['solutions'].nil? || JSON.parse(last_response.body)['solutions'].empty?
    end
    delete_completed_job @job_id, api_key: 'ortools' if @job_id
  end

  def test_using_two_solver
    TestHelper.solve_asynchronously do
      problem = VRP.lat_lon
      problem[:vehicles].first[:end_point_id] = nil
      problem[:vehicles] << Marshal.load(Marshal.dump(problem[:vehicles].first))
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
end
