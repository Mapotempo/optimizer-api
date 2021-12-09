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
module ContainedPointAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    point = super

    self.attributes.each{ |key, value|
      next unless value.is_a? Models::Point

      point["#{key}_id"] = value.id
      point.delete(key.to_s)
    }
    point
  end
end

module ActivityAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    activity = super
    return activity unless self.is_a? Models::Activity

    activity.delete('point')
    activity.delete('id') unless self.class == Models::Rest
    activity.delete('timewindow_ids')
    activity
  end
end

module ServiceAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    service = super
    return service unless self.is_a? Models::Service

    service.delete('relations')
    service.delete('sticky_vehicles')
    service.delete('activity_id')
    service.delete('quantity_ids')
    service
  end
end

module RelationAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    return super unless self.is_a? Models::Relation

    except = %i[linked_services linked_vehicles]
    relation = Models::Relation.field_names.map{ |field_name|
      next if except.include? field_name

      [field_name, self.send(field_name).as_json]
    }.compact.to_h

    relation.delete(:id)

    relation
  end
end

module TimewindowAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    timewindow = super

    self.attributes.each{ |key, value|
      next unless value.is_a? Models::Timewindow

      timewindow.delete(key.to_s)
    }
    timewindow
  end
end

module LoadAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    load_hash = super

    self.attributes.each{ |key, value|
      next unless value.is_a? Models::Unit

      load_hash["#{key}_id"] = value.id
      load_hash.delete(key.to_s)
    }
    load_hash.delete('quantity_id')
    load_hash.delete('capacity_id')
    load_hash
  end
end

module SolutionRouteAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    solution_route = super
    self.attributes.each{ |key, value|
      next unless value.is_a? Models::Vehicle

      solution_route["#{key}_id"] = value.id
      solution_route.delete(key.to_s)
    }
    solution_route
  end
end

module SolutionStopAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    stop = super
    return stop unless self.is_a? Models::Solution::Stop

    stop.delete('id') if self.type == :depot
    stop.delete('activity_id')
    stop
  end
end

module PointAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    stop = super
    return stop unless self.is_a? Models::Point

    stop['location']&.delete('id')
    stop.delete('location_id')
    stop
  end
end

module VehicleAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    return super unless self.is_a? Models::Vehicle

    except = %i[start_point end_point rests]
    vehicle = Models::Vehicle.field_names.map{ |field_name|
      next if except.include? field_name

      [field_name, self.send(field_name).as_json]
    }.compact.to_h

    vehicle.delete(:timewindow_id)

    vehicle[:rest_ids] = self.rests.map(&:id)
    vehicle[:id] = self.id
    vehicle
  end
end

module VrpAsJson
  extend ActiveSupport::Concern

  def empty_json
    vrp = {
      'name' => self.name,
      'configuration' => self.configuration.as_json,
      'points' => [], 'services' => [], 'vehicles' => []
    }

    delete_end_with_nested_key!(vrp['configuration'], 'id')
    delete_end_with_nested_key!(vrp['configuration'], '_id')
    delete_end_with_nested_key!(vrp['configuration'], '_ids')
    vrp.to_json
  end

  def as_json(options = {})
    return super unless self.is_a? Models::Vrp

    vrp = super

    delete_end_with_nested_key!(vrp['configuration'], 'id')
    delete_end_with_nested_key!(vrp['configuration'], '_id')
    delete_end_with_nested_key!(vrp['configuration'], '_ids')
    vrp
  end

  def delete_end_with_nested_key!(hash, except_key)
    if hash.is_a? Hash
      hash.each{ |key, value|
        if key.end_with?(except_key)
          hash.delete(key)
        else
          delete_end_with_nested_key!(value, except_key)
        end
      }
    elsif hash.is_a? Array
      hash.each{ |value| delete_end_with_nested_key!(value, except_key) }
    end
    hash
  end
end

module IndependentAsJson
  extend ActiveSupport::Concern

  def as_json(options = {})
    object = super
    except_models = [
      Models::Point.to_s,
      Models::Rest.to_s,
      Models::Solution::Stop.to_s,
      Models::Service.to_s,
      Models::Vehicle.to_s,
      Models::Matrix.to_s,
      Models::Unit.to_s,
    ]
    return object if except_models.include? self.class.to_s

    object.delete('id')
    object
  end
end
