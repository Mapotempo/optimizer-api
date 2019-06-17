# Copyright © Mapotempo, 2018
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

class DichotomiousTest < Minitest::Test

  def test_dichotomious_approach
    vrp = FCT.load_vrp(self)
    t1 = Time.now
    result = OptimizerWrapper.wrapper_vrp('ortools', {services: {vrp: [:ortools]}}, vrp, nil)
    t2 = Time.now
    assert result

    # Check activities
    assert 30 > result[:unassigned].size, "Too many unassigned services #{result[:unassigned].size}"

    # Check routes
    if result[:unassigned].size < 10
      assert 14 > result[:routes].size, "Too many routes: #{result[:routes].size}"
    else
      assert 13 > result[:routes].size, "Too many routes: #{result[:routes].size}"
    end

    # Check elapsed time
    assert t2 - t1 < 765 * 1.25, "Too long elapsed time: #{t2 - t1}"
    assert t2 - t1 > 510, "Too short elapsed time: #{t2 - t1}"
    assert result[:elapsed] / 1000 > 510 && result[:elapsed] / 1000 < 765, "Incorrect elapsed time: #{result[:elapsed]}"
  end

  def test_cluster_dichotomious_heuristic
    vrp = FCT.load_vrp(self, fixture_file: 'cluster_dichotomious.json')
    service_vrp = {vrp: vrp, service: :demo, level: 0}
    while service_vrp[:vrp].services.size > 100
      services_vrps_dicho = Interpreters::Dichotomious.split(service_vrp, nil)
      assert_equal 2, services_vrps_dicho.size

      locations_one = services_vrps_dicho.first[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.first.data_items.map{ |d| [d[0], d[1]] }
      locations_two = services_vrps_dicho.second[:vrp].services.map{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }#clusters.second.data_items.map{ |d| [d[0], d[1]] }
      assert_equal 0, (locations_one & locations_two).size

      durations = []
      services_vrps_dicho.each{ |service_vrp_dicho|
        durations << service_vrp_dicho[:vrp].services_duration
      }
      assert_equal service_vrp[:vrp].services_duration.to_i, durations.sum.to_i
      assert durations[0] <= durations[1]

      average_duration = durations.inject(0, :+) / durations.size
      # Clusters should be balanced but the priority is the geometry
      min_duration = average_duration - 0.5 * average_duration
      max_duration = average_duration + 0.5 * average_duration
      durations.each_with_index{ |duration, index|
        assert duration < max_duration && duration > min_duration, "Duration ##{index} (#{duration}) should be between #{min_duration} and #{max_duration}"
      }

      service_vrp = services_vrps_dicho.first
    end
  end

  def test_no_dichotomious_when_no_location
    vrp = FCT.load_vrp(self)
    service_vrp = { vrp: vrp, service: :demo }

    assert !Interpreters::Dichotomious.dichotomious_candidate(service_vrp)
  end
end
