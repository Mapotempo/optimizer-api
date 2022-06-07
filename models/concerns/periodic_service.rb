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

# Checks periodic services validity
module PeriodicService
  extend ActiveSupport::Concern

  def can_affect_all_visits?(service)
    return true unless self.schedule?

    return true if service.visits_number == 1

    range_indices = self.configuration.schedule.range_indices
    first_service_day = ((range_indices[:start]..range_indices[:end]).to_a - service.unavailable_days.to_a).min

    self.vehicles.any?{ |v|
      next unless service.vehicle_compatibility.nil? || service.vehicle_compatibility[v.id] # vehcile already eliminated

      current_day = [range_indices[:start], first_service_day].max
      decimal_day = current_day
      current_visit = 0

      while current_visit < service.visits_number && current_day <= range_indices[:end]
        if !v.unavailable_days.include?(current_day) &&
           (v.timewindow.nil? && v.sequence_timewindows.empty? ||
           (v.timewindow && (v.timewindow.day_index.nil? || current_day % 7 == v.timewindow.day_index)) ||
           (v.sequence_timewindows.any?{ |tw| tw.day_index.nil? || current_day % 7 == tw.day_index }))
          decimal_day += (service.minimum_lapse || 1)
          current_day = decimal_day.round
          current_visit += 1
        else
          decimal_day += 1
          current_day += 1
        end
      end

      current_visit == service.visits_number
    }
  end
end
