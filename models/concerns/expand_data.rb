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
require 'active_support/concern'

# Expands provided data
module ExpandData
  extend ActiveSupport::Concern

  def adapt_relations_between_shipments
    services_ids = self.services.collect(&:id)
    self.shipments.each{ |shipment|
      services_ids << "#{shipment.id}pickup"
      services_ids << "#{shipment.id}delivery"
    }
    self.relations.each{ |relation|
      if %w[minimum_duration_lapse maximum_duration_lapse].include?(relation.type)
        relation.linked_ids[0] = "#{relation.linked_ids[0]}delivery" unless services_ids.include?(relation.linked_ids[0])
        relation.linked_ids[1] = "#{relation.linked_ids[1]}pickup" unless services_ids.include?(relation.linked_ids[1])

        relation.lapse ||= 0
      elsif relation.type == 'same_route'
        relation.linked_ids.each_with_index{ |id, id_i|
          next if services_ids.include?(id)

          relation.linked_ids[id_i] = "#{id}pickup" # which will be in same_route as id_delivery
        }
      elsif %w[sequence order].include?(relation.type)
        raise OptimizerWrapper::DiscordantProblemError, 'Relation between shipment pickup and delivery should be explicitly specified for relation.' unless (relation.linked_ids - services_ids).empty?
      end
    }
  end

  def add_sticky_vehicle_if_routes_and_partitions
    return if self.preprocessing_partitions.empty?

    self.routes.each{ |route|
      route.mission_ids.each{ |id|
        corresponding = [self.services, self.shipments].compact.flatten.find{ |s| s.id == id }
        corresponding.sticky_vehicle_ids = [route.vehicle_id]
      }
    }
  end

  def clean_according_to(unfeasible_services)
    unfeasible_services.each{ |unfeasible_service|
      self.routes.each{ |route|
        route.mission_ids.delete_if{ |id| id == unfeasible_service[:original_service_id] }
      }
    }
  end

  def expand_unavailable_indices
    unavailable_indices = self.schedule_unavailable_indices.select{ |unavailable_index|
      unavailable_index >= self.schedule_range_indices[:start] && unavailable_index <= self.schedule_range_indices[:end]
    }

    self.vehicles.each{ |vehicle|
      vehicle.unavailable_work_day_indices |= unavailable_indices
    }
    [self.services + self.shipments].flatten.each{ |mission|
      mission.unavailable_visit_day_indices |= unavailable_indices
    }
  end

  def provide_original_ids
    (self.services + self.shipments + self.vehicles).each{ |element|
      element.original_id = element.id
    }
  end
end
