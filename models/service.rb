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
  class Service < Base
    field :original_id, default: nil

    field :priority, default: 4
    field :exclusion_cost, default: nil
    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :priority
    # validates_numericality_of :exclusion_cost, allow_nil: true
    field :type, default: :service

    # this should be a VISIT attribute
    # for each visit, first possible day to assign it
    field :first_possible_days, default: []
    field :last_possible_days, default: []

    field :visits_number, default: 1

    # validates_numericality_of :visits_number

    field :unavailable_visit_indices, default: []
    field :unavailable_days, default: Set[] # extends unavailable_visit_day_date and unavailable_visit_day_indices

    field :minimum_lapse, default: nil
    field :maximum_lapse, default: nil

    # validates_numericality_of :minimum_lapse
    # validates_numericality_of :maximum_lapse

    # validates_inclusion_of :type, :in => %i(service pickup delivery)

    field :skills, default: []
    field :original_skills, default: []

    ## has_many :period_activities, class_name: 'Models::Activity' # Need alternatives visits
    belongs_to :activity, class_name: 'Models::Activity'
    has_many :activities, class_name: 'Models::Activity'
    has_many :sticky_vehicles, class_name: 'Models::Vehicle'
    has_many :quantities, class_name: 'Models::Quantity'
    has_many :relations, class_name: 'Models::Relation'

    def loads(options = {})
      quantity_hash = quantities.map{ |quantity| [quantity.unit.id, quantity] }.to_h
      options[:loads]&.map{ |ld|
        next unless quantity_hash.key? ld.quantity.unit.id

        ld.quantity = quantity_hash[ld.quantity.unit.id]
        ld
      }&.compact
    end

    def route_activity(options = {})
      Models::RouteActivity.new(
        id: self.original_id,
        service_id: options[:service_id] || self.id,
        pickup_shipment_id: self.type == :pickup && self.original_id || self.id,
        delivery_shipment_id: self.type == :delivery && self.original_id || self.id,
        type: self.type,
        alternative: options[:index],
        loads: loads(options),
        detail: options[:index] && self.activities[options[:index]] || self.activity,
        timing: options[:timing] || Models::Timing.new({}),
        reason: options[:reason]
      )
    end
  end
end
