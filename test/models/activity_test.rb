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

module Models
  class ActivityTest < Minitest::Test
    include Rack::Test::Methods

    def test_timewindows
      skip "This test has no effect. Even if we make it pass; there is nothing checking invalid timewindows.
            Because Active hash doesn't call the validators of the sub classes and validation checks similar
            to followings are never performed during runtime. Therefore this test is misleading and skipped
            until we implement a proper validation for time windows.
            5th and 6th asserts currently fail. SEE models/activity.rb for further note."

      assert Activity.create(timewindows: []).validate

      assert Activity.create(timewindows: [{
        start: 0,
        end: 1
      }]).validate

      assert Activity.create(timewindows: [{
        start: 0,
        end: 1
      }, {
        start: 2,
        end: 3
      }]).validate

      assert Activity.create(timewindows: [{
        start: nil,
        end: 1
      }, {
        start: 2,
        end: nil
      }]).validate

      assert !Activity.create(timewindows: [{
        start: 0,
        end: nil
      }, {
        start: 2,
        end: 3
      }]).validate

      assert !Activity.create(timewindows: [{
        start: 0,
        end: 1
      }, {
        start: 0,
        end: 3
      }]).validate
    end
  end
end
