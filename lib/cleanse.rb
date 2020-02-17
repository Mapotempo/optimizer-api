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
  def self.cleanse(vrp, result)
    if result
      cleanse_empties_fills(vrp, result)
      # cleanse_empty_routes(result)
    end
  end

  def self.same_position(vrp, previous, current)
    previous.matrix_index && current.matrix_index && (vrp.matrices.first[:time].nil? || vrp.matrices.first[:time] && vrp.matrices.first[:time][previous.matrix_index][current.matrix_index] == 0) &&
      (vrp.matrices.first[:distance].nil? || vrp.matrices.first[:distance] && vrp.matrices.first[:distance][previous.matrix_index][current.matrix_index] == 0) ||
      previous.location && current.location && previous.location.lat == current.location.lat && previous.location.lon == current.location.lon
  end

  def self.same_empty_units(capacities, previous, current)
    if previous && current
      if previous
        previous_empty_units = previous.quantities.collect{ |quantity|
          quantity.unit.id if quantity.empty
        }.compact
      end
      if current
        useful_units = (current.quantities.collect{ |quantity|
          quantity.unit.id
        }.compact & capacities)

        current_empty_units = current.quantities.collect{ |quantity|
          quantity.unit.id if quantity.empty
        }.compact
      end
      !previous_empty_units.empty? && !current_empty_units.empty? && (useful_units & previous_empty_units & current_empty_units == useful_units)
    end
  end

  def self.same_fill_units(capacities, previous, current)
    if previous && current
      if previous
        previous_fill_units = previous.quantities.collect{ |quantity|
          quantity.unit.id if quantity.fill
        }.compact
      end
      if current
        useful_units = (current.quantities.collect{ |quantity|
          quantity.unit.id
        }.compact & capacities)

        current_fill_units = current.quantities.collect{ |quantity|
          quantity.unit.id if quantity.fill
        }.compact
      end
      !previous_fill_units.empty? && !current_fill_units.empty? && (useful_units & previous_fill_units & current_fill_units == useful_units)
    end
  end

  def self.cleanse_empties_fills(vrp, result)
    result[:routes].each{ |route|
      vehicle = vrp.vehicles.find{ |vehicle| vehicle.id == route[:vehicle_id] }
      capacities_units = vehicle.capacities.collect{ |capacity| capacity.unit_id if capacity.limit }.compact
      previous = nil
      previous_point = nil
      current_service = nil
      current_point = nil

      route[:activities].delete_if{ |activity|
        current_service = vrp.services.find{ |service| service[:id] == activity[:service_id] }
        current_point = current_service.activity.point if current_service

        if previous && current_service && same_position(vrp, previous_point, current_point) && same_empty_units(capacities_units, previous, current_service) &&
           !same_fill_units(capacities_units, previous, current_service)
          add_unnassigned(result[:unassigned], current_service, 'Duplicate empty service.')
          true
        elsif previous && current_service && same_position(vrp, previous_point, current_point) && same_fill_units(capacities_units, previous, current_service) &&
              !same_empty_units(capacities_units, previous, current_service)
          add_unnassigned(result[:unassigned], current_service, 'Duplicate fill service.')
          true
        else
          previous = current_service if previous.nil? || activity[:service_id]
          previous_point = current_point if previous.nil? || activity[:service_id]
          false
        end
      }
    }
  end

  def self.add_unnassigned(unassigned, service, reason)
    unassigned << {
      original_service_id: service.id,
      service_id: service.id,
      point_id: service.activity&.point_id,
      detail: {
        lat: service.activity&.point&.location&.lat,
        lon: service.activity&.point&.location&.lon,
        setup_duration: service.activity&.setup_duration,
        duration: service.activity&.duration,
        timewindows: service.activity&.timewindows&.collect{ |tw| { start: tw.start, end: tw.end } } || [],
        quantities: service.quantities&.collect{ |qte| { unit: qte.unit.id, value: qte.value } }
      },
      reason: reason
    }
  end

  def self.cleanse_empty_routes(result)
    result[:routes].delete_if{ |route| route[:activities].none?{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] } }
  end
end
