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
end
