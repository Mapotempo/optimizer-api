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
end
