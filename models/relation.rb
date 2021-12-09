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
    include RelationAsJson

    NO_LAPSE_TYPES = %i[same_vehicle same_route sequence order shipment meetup force_first never_first force_end].freeze
    ONE_LAPSE_TYPES = %i[vehicle_group_number vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months].freeze
    SEVERAL_LAPSE_TYPES = %i[minimum_day_lapse maximum_day_lapse minimum_duration_lapse maximum_duration_lapse vehicle_trips].freeze

    ON_VEHICLES_TYPES = %i[vehicle_group_number vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months vehicle_trips].freeze
    ON_SERVICES_TYPES = %i[same_vehicle same_route sequence order shipment meetup force_first never_first force_end minimum_day_lapse maximum_day_lapse minimum_duration_lapse maximum_duration_lapse].freeze

    POSITION_TYPES = %i[order sequence shipment].freeze

    field :type, default: :same_route
    field :lapses, default: nil
    field :linked_ids, default: []
    has_many :linked_services, class_name: 'Models::Service'
    field :linked_vehicle_ids, default: []
    field :periodicity, default: 1

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :lapse, allow_nil: true
    # validates_numericality_of :periodicity, greater_than_or_equal_to: 1
    # validates_inclusion_of :type, :in => %i(same_vehicle same_route sequence order minimum_day_lapse maximum_day_lapse shipment meetup maximum_duration_lapse vehicle_group_duration vehicle_group_duration_on_weeks vehicle_group_duration_on_months vehicle_trips)

    def self.create(hash)
      # TODO: remove it after the linked_ids is replaced with linked_service_ids in the api definition
      exclusive = [:linked_service_ids, :linked_ids, :linked_services].freeze
      raise "#{exclusive} fields are mutually exclusive" if hash.keys.count{ |k| exclusive.include? k } > 1

      # TODO: remove it after the linked_ids is replaced with linked_service_ids in the api definition
      if hash.key?(:linked_ids)
        hash[:linked_service_ids] = hash[:linked_ids]
      elsif hash.key?(:linked_service_ids)
        hash[:linked_ids] = hash[:linked_service_ids]
      elsif hash.key?(:linked_services)
        hash[:linked_ids] = hash[:linked_services].map(&:id)
      end

      hash[:type] = hash[:type]&.to_sym if hash.key?(:type)
      super(hash)
    end

    def split_regarding_lapses
      # TODO : can we create relations from here ?
      # remove self.linked_ids
      if Models::Relation::SEVERAL_LAPSE_TYPES.include?(self.type)
        if self.lapses.uniq.size == 1
          [[self.linked_ids, self.linked_vehicle_ids, self.lapses.first]]
        else
          self.lapses.collect.with_index{ |lapse, index|
            [self.linked_ids && self.linked_ids[index..index+1],
             self.linked_vehicle_ids && self.linked_vehicle_ids[index..index+1],
             lapse]
          }
        end
      else
        [[self.linked_ids, self.linked_vehicle_ids, self.lapses&.first]]
      end
    end
  end
end
