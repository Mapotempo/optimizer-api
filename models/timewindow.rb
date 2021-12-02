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
  class Timewindow < Base
    field :start, default: 0
    field :end, default: nil
    field :day_index, default: nil
    field :maximum_lateness, default: nil

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :start, allow_nil: true
    # validates_numericality_of :end, allow_nil: true, greater_than: :start, if: :start
    # validates_numericality_of :day_index, allow_nil: true

    def self.create(hash)
      # By default 25% of the timewindow (if there is no end, it is 0)
      hash[:maximum_lateness] ||= hash[:end] ? (0.25 * (hash[:end] - hash[:start].to_i)).round : 0

      super(hash)
    end

    def safe_end(lateness_allowed = false)
      if self.end
        self.end + (lateness_allowed ? self.maximum_lateness : 0)
      elsif self.day_index
        86399 # 24h - 1sec
      else
        2147483647 # 2**31 - 1
      end
    end
  end
end
