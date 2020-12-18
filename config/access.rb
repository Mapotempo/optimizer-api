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
module OptimizerWrapper
  @access_by_api_key = {
    # params_limit overload values from profile
    'demo' => { profile: :demo, params_limit: { points: nil, vehicles: nil }},
    'quota_test' => { profile: :demo, params_limit: { points: 1, vehicles: 1 }, quotas: [{ operation: :submit_vrp, daily: 1 }, { monthly: 2 }] },
    'solvers' => { profile: :solvers },
    'vroom' => { profile: :vroom },
    'ortools' => { profile: :ortools },
    'jsprit' => { profile: :jsprit },
  }
end
