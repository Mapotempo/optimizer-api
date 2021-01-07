# Copyright © Mapotempo, 2020
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

class Api::V01::ApiTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Api::Root
  end

  def test_should_not_access
    get '/0.1/vrp/submit'
    assert_equal 401, last_response.status
    assert_equal '401 Unauthorized', JSON.parse(last_response.body)['error']
  end

  def test_should_not_access_if_expired
    get '/0.1/vrp/submit', api_key: 'expired'
    assert_equal 402, last_response.status
    assert_equal '402 Subscription expired', JSON.parse(last_response.body)['error']
  end
end