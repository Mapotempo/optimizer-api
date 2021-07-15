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
require './models/solution/timing'

module Models
  class RouteActivity < Base
    # field :point_id
    field :id
    field :type
    field :alternative
    field :reason, default: nil
    # TODO: The following fields should be merged into id in v2
    field :service_id
    field :pickup_shipment_id
    field :delivery_shipment_id
    field :rest_id
    field :skills, default: []
    field :original_skills, default: []
    field :visit_index

    has_many :loads, class_name: 'Models::Load'
    belongs_to :detail, class_name: 'Models::Activity'
    belongs_to :timing, class_name: 'Models::Timing'

    def initialize(options = {})
      super(options)
      self.timing = Models::Timing.new({}) unless options.key? :timing
      set_timing_end_time
    end

    def vrp_result(options = {})
      hash = super(options)
      hash['original_service_id'] = id
      hash.delete('timing')
      hash.delete('skills')
      hash.delete('original_skills')
      hash.merge!(timing.vrp_result(options))
      hash['detail']['skills'] = build_skills
      hash['detail']['internal_skills'] = self.skills
      hash['detail']['quantities'] = loads.vrp_result(options)
      hash.delete_if{ |_k, v| v.nil? }
      hash
    end

    def set_timing_end_time
      timing.end_time = timing.begin_time + detail.duration
      timing.departure_time = timing.end_time
    end

    def build_skills
      return [] unless self.skills.any?

      all_skills = self.skills - self.original_skills
      skills_to_output = []
      vehicle_cluster = all_skills.find{ |sk| sk.to_s.include?('vehicle_partition_') }
      skills_to_output << vehicle_cluster.to_s.split('_')[2..-1].join('_') if vehicle_cluster
      work_day_cluster = all_skills.find{ |sk| sk.to_s.include?('work_day_partition_') }
      skills_to_output << work_day_cluster.to_s.split('_')[3..-1].join('_') if work_day_cluster
      skills_to_output += all_skills.select{ |sk| sk.to_s.include?('cluster ') }
      skills_to_output += self.original_skills
      skills_to_output
    end
  end
end
