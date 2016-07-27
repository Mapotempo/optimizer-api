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
require './test/test_helper'

require './api/root'


class Api::V01::VrpTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def test_vrp
    vrp = {
      points: [{
        id: 'p1',
        location: {
          lat: 1,
          lon: 2
        }
      }],
      services: [{
        id: 's1',
        activity: {
          point_id: 'p1'
        }
      }],
      vehicles: [{
        id: 'v1'
      }],
      configuration: {
        resolution: {
          duration: 1
        }
      }
    }
    post '/0.1/vrp/submit', {api_key: 'demo', vrp: vrp}
    assert_equal 201, last_response.status, last_response.body
    assert JSON.parse(last_response.body)['job']['id']
  end
end
