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
    cleanse_duplicate_empties_fills(vrp, solution)
    # cleanse_empty_routes(result)
  end

  def self.same_position(current)
    current.info.travel_time&.zero? || current.info.travel_distance&.zero?
  end

  def self.same_empty_units(capacity_unit_ids, previous, current)
    if previous && current
      if previous
        previous_empty_units = previous.loads.map{ |loa|
          loa.quantity.unit.id if loa.quantity.empty
        }.compact
      end
      if current
        useful_units = useful_unit_ids(capacity_unit_ids, current)

        current_empty_units = current.loads.map{ |loa|
          loa.quantity.unit.id if loa.quantity.empty
        }.compact
      end
      !previous_empty_units.empty? && !current_empty_units.empty? &&
        (useful_units & previous_empty_units & current_empty_units == useful_units)
    end
  end

  def self.same_fill_units(capacity_unit_ids, previous, current)
    if previous && current
      if previous
        previous_fill_units = previous.loads.map{ |loa|
          loa.quantity.unit.id if loa.quantity.fill
        }.compact
      end
      if current
        useful_units = useful_unit_ids(capacity_unit_ids, current)

        current_fill_units = current.loads.map{ |loa|
          loa.quantity.unit.id if loa.quantity.fill
        }.compact
      end
      !previous_fill_units.empty? && !current_fill_units.empty? &&
        (useful_units & previous_fill_units & current_fill_units == useful_units)
    end
  end

  def self.useful_unit_ids(capacity_unit_ids, stop)
    stop.loads.map{ |loa| loa.quantity.unit.id }.compact & capacity_unit_ids
  end

  def self.cleanse_empties_fills(_vrp, solution)
    service_types = %i[pickup delivery service]
    solution.routes.each{ |route|
      vehicle = route.vehicle
      capacity_unit_ids = vehicle.capacities.collect{ |capacity| capacity.unit_id if capacity.limit }.compact
      previous_activity = nil

      route.stops.delete_if{ |stop|
        next unless service_types.include?(stop.type)

        if previous_activity && stop && same_position(stop) &&
           same_empty_units(capacity_unit_ids, previous_activity, stop) &&
           !same_fill_units(capacity_unit_ids, previous_activity, stop)
          add_unnassigned(solution.unassigned_stops, stop, 'Duplicate empty service.')
          true
        elsif previous_activity && stop && same_position(stop) &&
              same_fill_units(capacity_unit_ids, previous_activity, stop) &&
              !same_empty_units(capacity_unit_ids, previous_activity, stop)
          add_unnassigned(solution.unassigned_stops, stop, 'Duplicate fill service.')
          true
        else
          previous_activity = stop if previous_activity.nil? || stop.service_id
          false
        end
      }
    }
  end

  def self.cleanse_duplicate_empties_fills(vrp, solution)
    count_services = vrp.empties_or_fills.map{ |service| [service.id, 0] }.to_h

    # count empties or fills already part of the routes
    solution.routes.each{ |route|
      route.stops.each{ |stop|
        count_services[stop.service_id] += 1 if count_services.key?(stop.service_id)
      }
    }

    # remove duplicated unused empties or fills from unassigned
    solution.unassigned_stops.delete_if{ |a|
      if count_services.key?(a.service_id)
        count_services[a.service_id] += 1
        true if count_services[a.service_id] > 1
      end
    }
    solution.routes.each{ |route|
      if route.stops.map{ |s| s.activity.point_id }.uniq.size == 1
        route.stops.map{ |stop|
          if stop.loads&.first&.quantity&.empty
            add_unnassigned(solution.unassigned_stops, stop, 'Unnecessary empty stop.')
            route.stops.delete(stop)
          end
        }
      end
    }
  end

  def self.add_unnassigned(unassigned, route_stop, reason)
    route_stop.reason = reason
    unassigned << route_stop
  end

  def self.cleanse_empty_routes(result)
    result.routes.delete_if{ |route| route.stops.none?(&:service_id) }
  end
end
