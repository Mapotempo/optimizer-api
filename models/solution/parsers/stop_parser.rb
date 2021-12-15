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

module Parsers
  class ServiceParser
    def self.parse(service, options)
      activity = options[:index] && service.activities[options[:index]] || service.activity
      activity_hash = Models::Activity.field_names.map{ |key|
        next if key == :point_id

        [key, activity.send(key)]
      }.compact.to_h

      dup_activity = Models::Activity.new(activity_hash)
      dup_activity[:simplified_setup_duration] = activity[:simplified_setup_duration] if activity[:simplified_setup_duration]

      {
        id: service.original_id,
        service_id: options[:service_id] || service.id,
        pickup_shipment_id: service.type == :pickup ? (service.original_id || service.id) : nil,
        delivery_shipment_id: service.type == :delivery ? (service.original_id || service.id) : nil,
        type: service.type,
        alternative: options[:index],
        loads: build_loads(service, options),
        activity: dup_activity,
        info: options[:info] || Models::Solution::Stop::Info.new({}),
        reason: options[:reason],
        skills: options[:skills] || service.skills,
        original_skills: options[:original_skills] || service.original_skills,
        visit_index: options[:visit_index] || service.visit_index
      }
    end

    def self.build_loads(service, options = {})
      quantity_hash = service.quantities.map{ |quantity| [quantity.unit.id, quantity] }.to_h
      if options[:loads]
        options[:loads]&.map{ |ld|
          next unless quantity_hash.key? ld.quantity.unit.id

          ld.quantity = quantity_hash[ld.quantity.unit.id]
          ld
        }&.compact
      else
        service.quantities.map{ |quantity|
          Models::Solution::Load.new(quantity: quantity)
        }
      end
    end
  end

  class PointParser
    def self.parse(point, options)
      {
        id: point.id,
        type: :depot,
        loads: options[:loads],
        activity: Models::Activity.new(point: point),
        info: options[:info] || Models::Solution::Stop::Info.new({})
      }
    end
  end

  class RestParser
    def self.parse(rest, options)
      {
        id: rest.id,
        rest_id: rest.id,
        type: :rest,
        activity: Models::Rest.new(rest.as_json),
        info: options[:info] || Models::Solution::Stop::Info.new({})
      }
    end
  end
end
