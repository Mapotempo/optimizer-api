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

class HelperTest < Minitest::Test
  def test_no_unassigned_merge_with_nil_result
    results = [{ unassigned: [{ service_id: 'service_1' }] }, nil]
    merged_result = Helper.merge_results(results, false)
    assert_equal merged_result[:unassigned].size, 1
    assert(merged_result[:unassigned].one?{ |unassigned| unassigned[:service_id] == 'service_1' })
  end

  def test_merge_results_with_only_nil_results
    results = [nil]
    assert Helper.merge_results(results)
    assert Helper.merge_results(results, false)
  end

  def test_rounding_with_steps
    decimal_max = 4

    floats = (0..10**decimal_max - 1).collect{ |i| Rational(i, 10**decimal_max) }

    (0..decimal_max).each{ |decimal|
      (0..9).each{ |step|
        rounded = floats.collect{ |i| i.to_f.round_with_steps(decimal, step) } # use round with steps on float
        manual = floats.collect{ |i| (Rational(i, (1r / 10**decimal) / (step + 1)).round(0) * ((1r / 10**decimal) / (step + 1))).to_f.round(decimal + 1) } # Manually calculate using rational numbers

        assert_equal manual, rounded, "floats[#{rounded.find_index.with_index{ |r, i| r - manual[i] != 0 }}].to_f.round_with_steps(#{decimal}, #{step}) does not produce the correct result"
      }
    }
  end
end
