# Copyright © Mapotempo, 2020
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

# Expands provided data
module ExpandData
  extend ActiveSupport::Concern

  def add_relation_references
    self.relations.each{ |relation|
      relation.linked_services.each{ |service|
        service.relations << relation
      }
    }
  end

  def add_sticky_vehicle_if_routes_and_partitions
    return if self.preprocessing_partitions.empty?

    self.routes.each{ |route|
      route.mission_ids.each{ |id|
        corresponding = self.services.find{ |s| s.id == id }
        corresponding.sticky_vehicle_ids = [route.vehicle_id]
      }
    }
  end

  def expand_unavailable_days
    unavailable_days = self.schedule_unavailable_days.select{ |unavailable_index|
      unavailable_index >= self.schedule_range_indices[:start] && unavailable_index <= self.schedule_range_indices[:end]
    }

    self.vehicles.each{ |vehicle|
      vehicle.unavailable_days |= unavailable_days
    }
    self.services.each{ |mission|
      mission.unavailable_days |= unavailable_days
    }
  end

  def provide_original_info
    (self.services + self.vehicles).each{ |element|
      element.original_id ||= element.id
      element.original_skills = element.skills.dup
    }
  end

  # NOTE : The sticky vehicles are converted as logical OR skills
  # TODO : Once the proper logical OR skills is implemented this logic should be merged with it
  def sticky_as_skills
    sticky_hash = {}
    self.services.each{ |service|
      next if service.sticky_vehicle_ids.empty?

      key = service.sticky_vehicle_ids.sort.join('_')
      skill = "sticky_skill_#{key}".to_sym
      unless sticky_hash.key?(key)
        sticky_hash[key] = service.sticky_vehicle_ids
        service.sticky_vehicles.each{ |vehicle| vehicle.skills.each{ |skill_set| skill_set << skill } }
      end
      service.skills << skill
    }
  end

  def accumulate_skills_of_services_in_linking_relations
    # WARNING: this operation should come after shipment->2services+relation and sticky->skill
    # conversions, and original_info expansion is done

    # Forward accumulate the skills of the services which are in a LINKING_RELATIONS
    # Because the tail of a linking relation can be skipped we cannot bring the skills of the tail
    # backwards -- except for shipment we can accumulate the skills of the delivery to the pickup.

    needs_another_iteration = true
    max_repeats = 5
    repeat = 0
    warn_for_on_service_types = false

    while needs_another_iteration && repeat < max_repeats
      repeat += 1
      needs_another_iteration = false
      self.relations.each{ |relation|
        next unless Models::Relation::LINKING_RELATIONS.include?(relation.type)

        if Models::Relation::ON_SERVICES_TYPES.include?(relation.type)
          accumulated_skills = []
          relation.linked_services.each{ |s|
            accumulated_skills |= s.skills
            # there was a skill change which might affect another "linked" service
            needs_another_iteration = true if (accumulated_skills - s.skills).any?
            s.skills = accumulated_skills.sort!.dup
          }
          # except for shipments we need to make sure that all services has the same skills
          if relation.type == :shipment
            relation.linked_services.each{ |s| s.skills = accumulated_skills.dup }
          end
        else
          warn_for_on_service_types = true
        end
      }

    end

    if repeat == max_repeats
      err_msg = 'Either the number of repeats is not enough or there is an infinite loop in '\
                'accumulate_skills_of_services_in_linking_relations. '\
                'Some relations might be silently ignored during split_independent_vrp.'
      log err_msg, level: :warn
      raise err_msg if ENV['APP_ENV'] != 'production'
    end

    if warn_for_on_service_types
      # either a new LINKING_RELATIONS is forgotten to included in ON_SERVICES_TYPES or
      # this new service has ON_VEHICLES_TYPES and this check needs improvement
      err_msg = 'Skill accumulation can only handle LINKING_RELATIONS which are ON_SERVICES_TYPES. '\
                'Some relations might be silently ignored during split_independent_vrp.'
      log err_msg, level: :warn
      raise err_msg if ENV['APP_ENV'] != 'production'
    end
  end

end
