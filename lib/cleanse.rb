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

module Cleanse
  def self.cleanse(vrp, solution)
    return unless solution

    cleanse_empties_fills(vrp, solution)
    # cleanse_empty_routes(result)
  end

  def self.same_position(vrp, current)
    current.timing.travel_time&.zero? || current.timing.travel_distance&.zero?
  end

  def self.same_empty_units(capacities, previous, current)
    if previous && current
      if previous
        previous_empty_units = previous.loads.map{ |l|
          l.quantity.unit.id if l.quantity.empty
        }.compact
      end
      if current
        useful_units = (current.loads.map{ |l|
          l.quantity.unit.id
        }.compact & capacities)

        current_empty_units = current.loads.map{ |l|
          l.quantity.unit.id if l.quantity.empty
        }.compact
      end
      !previous_empty_units.empty? && !current_empty_units.empty? &&
        (useful_units & previous_empty_units & current_empty_units == useful_units)
    end
  end

  def self.same_fill_units(capacities, previous, current)
    if previous && current
      if previous
        previous_fill_units = previous.loads.map{ |l|
          l.quantity.unit.id if l.quantity.fill
        }.compact
      end
      if current
        useful_units = (current.loads.map{ |l|
          l.quantity.unit.id
        }.compact & capacities)

        current_fill_units = current.loads.map{ |l|
          l.quantity.unit.id if l.quantity.fill
        }.compact
      end
      !previous_fill_units.empty? && !current_fill_units.empty? &&
        (useful_units & previous_fill_units & current_fill_units == useful_units)
    end
  end

  def self.cleanse_empties_fills(vrp, solution)
    service_types = %i[pickup delivery service]

    solution.routes.each{ |route|
      vehicle = route.vehicle
      capacities_units = vehicle.capacities.collect{ |capacity| capacity.unit_id if capacity.limit }.compact
      previous_activity = nil

      route.activities.delete_if{ |r_activity|
        next unless service_types.include?(r_activity.type)

        if previous_activity && r_activity && same_position(vrp, r_activity) &&
           same_empty_units(capacities_units, previous_activity, r_activity) &&
           !same_fill_units(capacities_units, previous_activity, r_activity)
          add_unnassigned(solution.unassigned, r_activity, 'Duplicate empty service.')
          true
        elsif previous_activity && r_activity && same_position(vrp, r_activity) &&
              same_fill_units(capacities_units, previous_activity, r_activity) &&
              !same_empty_units(capacities_units, previous_activity, r_activity)
          add_unnassigned(solution.unassigned, r_activity, 'Duplicate fill service.')
          true
        else
          previous_activity = r_activity if previous_activity.nil? || r_activity.service_id
          false
        end
      }
    }
  end

  def self.add_unnassigned(unassigned, route_activity, reason)
    route_activity.reason = reason
    unassigned << route_activity
  end

  def self.cleanse_empty_routes(result)
    result.routes.delete_if{ |route| route.activities.none?(&:service_id) }
  end
end
