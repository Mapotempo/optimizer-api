# Copyright © Mapotempo, 2021
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
require './models/base'

module Models
  class SolutionRoute < Base
    field :geometry

    has_many :activities, class_name: 'Models::RouteActivity'
    has_many :initial_loads, class_name: 'Models::Load'

    belongs_to :cost_details, class_name: 'Models::CostDetails'
    belongs_to :details, class_name: 'Models::RouteDetails'
    belongs_to :vehicle, class_name: 'Models::Vehicle'

    def as_json(options = {})
      hash = super(options)
      hash.delete('details')
      hash.merge(details.as_json(options))
    end

    def activities=(_acts)
      compute_route_waiting_times
    end

    def compute_route_waiting_times
      previous_end = activities.first.timings.begin_time
      loc_index = nil
      consumed_travel_time = 0
      consumed_setup_time = 0
      activities.each.with_index{ |act, index|
        used_travel_time = 0
        if act.type == 'rest'
          if loc_index.nil?
            next_index = activities[index..-1].index{ |a| a[:type] != 'rest' }
            loc_index = index + next_index if next_index
            consumed_travel_time = 0
          end
          shared_travel_time = loc_index && activities[loc_index].timings.travel_time || 0
          potential_setup = shared_travel_time > 0 && activities[loc_index].details.setup_duration || 0
          left_travel_time = shared_travel_time - consumed_travel_time
          used_travel_time = [act.timings.begin_time - previous_end, left_travel_time].min
          consumed_travel_time += used_travel_time
          # As setup is considered as a transit value, it may be performed before a rest
          consumed_setup_time  += act.timings.begin_time - previous_end - [used_travel_time, potential_setup].min
        else
          used_travel_time = (act.timings.travel_time || 0) - consumed_travel_time - consumed_setup_time
          consumed_travel_time = 0
          consumed_setup_time = 0
          loc_index = nil
        end
        considered_setup = act.timings.travel_time&.positive? && (act.details.setup_duration.to_i - consumed_setup_time) || 0
        arrival_time = previous_end + used_travel_time + considered_setup + consumed_setup_time
        act.timings.waiting_time = act.timings.begin_time - arrival_time
        previous_end = act.timings.end_time || act.timings.begin_time
      }
    end
  end
end
