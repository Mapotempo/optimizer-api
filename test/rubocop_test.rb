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

class RubocopTest < Minitest::Test
  def test_no_offenses_in_tests
    output = `rubocop -f c -S --parallel ./test/*`
    /[0-9]* files inspected,\ (.*)\ offenses\ detected/ =~ output
    n_offeses = Regexp.last_match(1)
    assert_equal('no', n_offeses, "Following new Rubocop offenses added to the tests:\n\n#{output}")
  end
end
