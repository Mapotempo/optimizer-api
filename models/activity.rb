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
  class Activity < Base
    @@id = 0
    field :id, default: ->{ 'a' + (@@id += 1) }

    field :duration, default: 0
    field :setup_duration, default: 0
    validates_numericality_of :duration
    validates_numericality_of :setup_duration

    belongs_to :point, class_name: 'Models::Point'
    has_many :timewindows, class_name: 'Models::Timewindow'

    def point_id=(point_id)
      self[:point] = Point.find point_id
    end

    def point
      self[:point]
    end

    def point_id
      self[:point] && self[:point].id
    end
  end
end
