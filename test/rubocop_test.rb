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
  def test_no_error_in_files
    parallel = ENV['RUBOCOP_PARALLEL'] || ENV['TRAVIS'] ? '--parallel' : nil
    # parallel option could cause not to use rubocop from bundle
    options = "#{parallel} -f c --config .rubocop.yml --fail-level E --display-only-fail-level-offenses"
    cmd = "bundle exec rubocop ./* #{options}"
    o = system(cmd, [:out, :err] => '/dev/null')
    assert o, "New Rubocop offenses added to the project, run: #{cmd}"
  end

  def test_no_warning_in_tests
    parallel = ENV['RUBOCOP_PARALLEL'] || ENV['TRAVIS'] ? '--parallel' : nil
    # parallel option could cause not to use rubocop from bundle
    options = "#{parallel} -f c --config .rubocop.yml --fail-level W --display-only-fail-level-offenses"
    cmd = "bundle exec rubocop ./test/* #{options}"
    o = system(cmd, [:out, :err] => '/dev/null')
    assert o, "New Rubocop offenses added to the tests, run: #{cmd}"
  end
end
