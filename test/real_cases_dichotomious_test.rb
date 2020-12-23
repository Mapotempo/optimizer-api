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

    def test_dichotomious_first_instance
      skip "This test have incorrect bounds so it never passes and it takes 3 hours to complete.
            Followed by gitlab-issue https://gitlab.com/mapotempo/optimizer-api/-/issues/648"

      vrp = TestHelper.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      t2 = Time.now
      assert result

      # TODO: remove the logs after dicho overhead problem is fixed
      log "duration_min = #{vrp.resolution_minimum_duration / 1000.to_f}", level: :debug
      log "duration_max = #{vrp.resolution_duration / 1000.to_f}", level: :debug
      log "duration_optimization = #{result[:elapsed] / 1000.to_f}", level: :debug
      log "duration_elapsed =  #{t2 - t1}", level: :debug

      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"

      # Check time
      duration_min = vrp.resolution_minimum_duration / 1000.to_f
      duration_max = vrp.resolution_duration / 1000.to_f
      duration_optimization = result[:elapsed] / 1000.to_f
      duration_elapsed =  t2 - t1

      # Check time elapsed inside optimization
      optim_time_info_str = "#{duration_optimization}s -- optimisation duration demanded between [#{duration_min}, #{duration_max}]"
      assert duration_optimization > duration_min * 0.90, "Not enough time spent in optimization: #{optim_time_info_str}"
      assert duration_optimization < duration_max * 1.01, "Too much time spent in optimization: #{optim_time_info_str}"

      # Check time spent inside api
      elapsed_time_info_str = "#{duration_elapsed}s for an optimisation of #{duration_optimization}s ([#{duration_min}, #{duration_max}])"
      assert duration_elapsed > duration_min * 0.90, "Too little time spent inside api: #{elapsed_time_info_str}"
      assert duration_elapsed < duration_max * 1.55, "Too much time spent inside api: #{elapsed_time_info_str}"
    end

    def test_dichotomious_second_instance
      skip "This test have incorrect bounds so it never passes and it takes 3 hours to complete.
            Followed by gitlab-issue https://gitlab.com/mapotempo/optimizer-api/-/issues/648"

      vrp = TestHelper.load_vrp(self)
      t1 = Time.now
      result = OptimizerWrapper.wrapper_vrp('ortools', { services: { vrp: [:ortools] }}, vrp, nil)
      t2 = Time.now
      assert result

      # TODO: remove the logs after dicho overhead problem is fixed
      log "duration_min = #{vrp.resolution_minimum_duration / 1000.to_f}", level: :debug
      log "duration_max = #{vrp.resolution_duration / 1000.to_f}", level: :debug
      log "duration_optimization = #{result[:elapsed] / 1000.to_f}", level: :debug
      log "duration_elapsed =  #{t2 - t1}", level: :debug

      # Check activities
      assert result[:unassigned].size < 50, "Too many unassigned services #{result[:unassigned].size}"

      # Check routes
      assert result[:routes].size < 48, "Too many routes: #{result[:routes].size}"

      # Check time
      duration_min = vrp.resolution_minimum_duration / 1000.to_f
      duration_max = vrp.resolution_duration / 1000.to_f
      duration_optimization = result[:elapsed] / 1000.to_f
      duration_elapsed =  t2 - t1

      # Check time elapsed inside optimization
      optim_time_info_str = "#{duration_optimization}s -- optimisation duration demanded between [#{duration_min}, #{duration_max}]"
      assert duration_optimization > duration_min * 0.90, "Not enough time spent in optimization: #{optim_time_info_str}"
      assert duration_optimization < duration_max * 1.01, "Too much time spent in optimization: #{optim_time_info_str}"

      # Check time spent inside api
      elapsed_time_info_str = "#{duration_elapsed}s for an optimisation of #{duration_optimization}s ([#{duration_min}, #{duration_max}])"
      assert duration_elapsed > duration_min * 0.90, "Too little time spent inside api: #{elapsed_time_info_str}"
      assert duration_elapsed < duration_max * 1.55, "Too much time spent inside api: #{elapsed_time_info_str}"
    end

  end
end
