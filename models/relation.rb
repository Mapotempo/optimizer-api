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
  class Relation < Base
    field :type, default: :same_route
    field :lapse, default: nil
    field :linked_ids, default: []
    has_many :linked_services, class_name: 'Models::Service'
    field :linked_vehicle_ids, default: []
    field :periodicity, default: 1

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :lapse, allow_nil: true
    # validates_numericality_of :periodicity, greater_than_or_equal_to: 1
    # validates_inclusion_of :type, :in => %i(same_route sequence order minimum_day_lapse maximum_day_lapse shipment meetup maximum_duration_lapse vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months vehicle_trips)

    def self.create(hash)
      hash[:type] = hash[:type]&.to_sym if hash.key?(:type)
      super(hash)
    end
  end
end
