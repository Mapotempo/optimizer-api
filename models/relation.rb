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
    ALL_OR_NONE_RELATIONS = %i[
      meetup
      shipment
    ].freeze

    ALTERNATIVE_COMPATIBLE_RELATIONS = %i[
      order
      same_route
      sequence
      shipment
      force_first
      never_first
      force_end
      exclusive
    ].freeze

    # Relations that link multiple services to be on the same route
    LINKING_RELATIONS = %i[
      order
      same_route
      same_vehicle
      sequence
      shipment
    ].freeze

    # Relations that force multiple services/vehicles to stay in the same VRP
    FORCING_RELATIONS = %i[
      maximum_day_lapse
      maximum_duration_lapse
      meetup
      minimum_day_lapse
      minimum_duration_lapse
      vehicle_trips
    ].freeze

    NO_LAPSE_TYPES = %i[
      force_end
      force_first
      exclusive
      same_route
      same_vehicle
      sequence
      shipment
      meetup
      never_first
      order
    ].freeze

    ONE_LAPSE_TYPES = %i[
      vehicle_group_duration
      vehicle_group_duration_on_months
      vehicle_group_duration_on_weeks
      vehicle_group_number
    ].freeze

    SEVERAL_LAPSE_TYPES = %i[
      maximum_day_lapse
      maximum_duration_lapse
      minimum_day_lapse
      minimum_duration_lapse
      vehicle_trips
    ].freeze

    ON_VEHICLES_TYPES = %i[
      vehicle_group_duration
      vehicle_group_duration_on_months
      vehicle_group_duration_on_weeks
      vehicle_group_number
      vehicle_trips
    ].freeze

    ON_SERVICES_TYPES = %i[
      force_end
      force_first
      exclusive
      maximum_day_lapse
      maximum_duration_lapse
      meetup
      minimum_day_lapse
      minimum_duration_lapse
      never_first
      order
      same_route
      same_vehicle
      shipment
      sequence
    ].freeze

    POSITION_TYPES = %i[
      order
      sequence
      shipment
    ].freeze

    field :type, default: :same_route, type: Symbol
    field :lapses, default: nil
    has_many :linked_services, class_name: 'Models::Service', as_json: :ids
    field :linked_vehicle_ids, default: []
    field :periodicity, default: 1

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :lapse, allow_nil: true
    # validates_numericality_of :periodicity, greater_than_or_equal_to: 1
    # validates_inclusion_of :type,
    #                        in: %i[same_vehicle same_route sequence order minimum_day_lapse
    #                               maximum_day_lapse shipment meetup maximum_duration_lapse
    #                               vehicle_group_duration vehicle_group_duration_on_weeks
    #                               vehicle_group_duration_on_months vehicle_trips]
    def split_regarding_lapses
      # TODO : can we create relations from here ?
      # remove self.linked_ids
      if Models::Relation::SEVERAL_LAPSE_TYPES.include?(self.type)
        if self.lapses.uniq.size == 1
          [[self.linked_service_ids, self.linked_vehicle_ids, self.lapses.first]]
        else
          self.lapses.collect.with_index{ |lapse, index|
            [self.linked_service_ids && self.linked_service_ids[index..index + 1],
             self.linked_vehicle_ids && self.linked_vehicle_ids[index..index + 1],
             lapse]
          }
        end
      else
        [[self.linked_service_ids, self.linked_vehicle_ids, self.lapses&.first]]
      end
    end
  end
end
