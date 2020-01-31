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

class OptimizerLoggerTest < Minitest::Test
  def setup
    File.delete './test.log' if File.exist? './test.log'
    OptimizerLogger.log_device = 'test.log'
  end

  def test_logger_should_not_be_nil_for_env
    refute OptimizerLogger.nil?
  end

  def test_logger_should_log_to_file
    log 'Unit test logging'

    assert File.exist? './test.log'
  ensure
    File.delete './test.log'
  end

  def test_should_log_only_allowed_level_message
    tmp_logger_level = OptimizerLogger.level
    OptimizerLogger.level = :fatal
    log 'Unit test logging', level: :debug

    assert File.exist? './test.log'
    assert_equal 1, File.readlines('./test.log').size

    log 'Unit test logging', level: :fatal

    assert_equal 2, File.readlines('./test.log').size
  ensure
    OptimizerLogger.level = tmp_logger_level
    File.delete './test.log'
  end
end
