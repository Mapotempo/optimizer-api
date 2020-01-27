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
    assert merged_result[:unassigned].size == 1
    assert merged_result[:unassigned].one?{ |unassigned| unassigned[:service_id] == 'service_1' }
  end

  def test_merge_results_with_only_nil_results
    results = [nil]
    assert Helper.merge_results(results)
    assert Helper.merge_results(results, false)
  end
end
