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
  def test_rounding_with_steps
    decimal_max = 4

    floats = (0..10**decimal_max - 1).collect{ |i| Rational(i, 10**decimal_max) }

    allowed_difference = {
      '1 3': { size: 250, max: 0.01 },
      '1 7': { size: 125, max: 0.01 },
      '2 3': { size: 50, max: 0.001 },
      '2 7': { size: 26, max: 0.001 },
      '3 3': { size: 234, max: 0.0001 },
      '3 7': { size: 234, max: 0.0001 }
    }

    (0..decimal_max).each{ |decimal|
      (0..9).each{ |step|
        rounded = floats.collect{ |i| i.to_f.round_with_steps(decimal, step) } # use round with steps on float
        manual = floats.collect{ |i| (Rational(i, (1r / 10**decimal) / (step + 1)).round(0) * ((1r / 10**decimal) / (step + 1))).to_f.round(decimal + 1) } # Manually calculate using rational numbers

        # https://stackoverflow.com/a/51728872/1200528 # Ruby changed the defaults for round with a backport in 2.3.5
        if Gem::Version.new('2.3.5') <= Gem::Version.new(RUBY_VERSION)
          assert_equal manual, rounded, "floats[#{rounded.find_index.with_index{ |r, i| r - manual[i] != 0 }}].to_f.round_with_steps(#{decimal}, #{step}) does not produce the correct result"
        else
          allowed_diff = allowed_difference[:"#{decimal} #{step}"]
          if !allowed_diff.nil?
            diff = rounded.collect.with_index{ |r, i| (r - manual[i]).round(15) if r - manual[i] != 0 }.compact
            assert_equal allowed_diff[:size], diff.size, "There are more or less rounding errors then expected in Ruby #{RUBY_VERSION}"
            assert_equal allowed_diff[:max], diff.max, "There are more or less rounding errors then expected in Ruby #{RUBY_VERSION}"
          else
            assert_equal manual, rounded, "floats[#{rounded.find_index.with_index{ |r, i| r - manual[i] != 0 }}].to_f.round_with_steps(#{decimal}, #{step}) does not produce the correct result"
          end
        end
      }
    }
  end
end
