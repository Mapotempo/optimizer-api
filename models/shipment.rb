# Copyright © Mapotempo, 2016
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


module Models
  class Shipment < Base
    field :late_multiplier, default: nil
    field :exclusion_cost, default: nil
    validates_numericality_of :late_multiplier
    validates_numericality_of :exclusion_cost

    field :skills, default: []

    belongs_to :pickup, class_name: 'Models::Activity'
    belongs_to :delivery, class_name: 'Models::Activity'
    has_many :quantities, class_name: 'Models::ServiceQuantity'

    def pickup=(activity)
      self[:pickup] = Activity.create(activity)
    end

    def pickup
      self[:pickup] ||= Activity.create
    end

    def delivery=(activity)
      self[:delivery] = Activity.create(activity)
    end

    def delivery
      self[:delivery] ||= Activity.create
    end
  end
end
