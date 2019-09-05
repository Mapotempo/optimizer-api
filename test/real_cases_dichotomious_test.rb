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

class RealCasesTest < Minitest::Test
  if !ENV['SKIP_REAL_DICHO'] && !ENV['SKIP_DICHO'] && !ENV['TRAVIS']

    def test_soft_instance_dichotomious
      vrp = FCT.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      t2 = Time.now
      assert result
  
      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"
  
      # Check routes
      assert result[:routes].size < 48, "Too many routes: #{result[:routes].size}"
  
      # Check elapsed time
      assert result[:elapsed] / 1000 > 4080 * 0.9 && result[:elapsed] / 1000 < 4590 * 1.01, "Incorrect elapsed time: #{result[:elapsed]}"
      assert t2 - t1 < 4590 * 1.55, "Too long elapsed time: #{t2 - t1}"
      assert t2 - t1 > 4080, "Too short elapsed time: #{t2 - t1}"
    end

    def test_dichotomious_first_instance
      vrp = FCT.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      t2 = Time.now
      assert result

      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"

      # Check elapsed time
      assert result[:elapsed] / 1000 > 7110 * 0.9 && result[:elapsed] / 1000 < 6320 * 1.01, "Incorrect elapsed time: #{result[:elapsed]}"
      assert t2 - t1 < 7110 * 1.55, "Too long elapsed time: #{t2 - t1}"
      assert t2 - t1 > 6320 * 0.9, "Too short elapsed time: #{t2 - t1}"
    end

    def test_dichotomious_second_instance
      vrp = FCT.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      t2 = Time.now
      assert result

      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"

      # Check routes
      assert result[:routes].size < 48, "Too many routes: #{result[:routes].size}"

      # Check elapsed time
      assert result[:elapsed] / 1000 > 4080 * 0.9 && result[:elapsed] / 1000 < 4590 * 1.01, "Incorrect elapsed time: #{result[:elapsed]}"
      assert t2 - t1 < 4590 * 1.55, "Too long elapsed time: #{t2 - t1}"
      assert t2 - t1 > 4080, "Too short elapsed time: #{t2 - t1}"
    end

    def test_soft_instance_dichotomious
      vrp = FCT.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
      t2 = Time.now
      assert result

      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"

      # Check routes
      assert result[:routes].size < 48, "Too many routes: #{result[:routes].size}"

      # Check elapsed time
      assert result[:elapsed] / 1000 > 4080 * 0.9 && result[:elapsed] / 1000 < 4590 * 1.01, "Incorrect elapsed time: #{result[:elapsed]}"
      assert t2 - t1 < 4590 * 1.55, "Too long elapsed time: #{t2 - t1}"
      assert t2 - t1 > 4080, "Too short elapsed time: #{t2 - t1}"
    end
  end
end
