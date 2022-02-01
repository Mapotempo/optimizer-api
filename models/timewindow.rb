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

DEFAULT_MAX_LATENESS_RATIO = ENV['OPTIM_DEFAULT_MAX_LATENESS_RATIO'] ? ENV['OPTIM_DEFAULT_MAX_LATENESS_RATIO'].to_f : 1

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
      # If the maximum_lateness of the timewindow is not defined, by default, it is 100% of the timewindow or
      # if ENV['OPTIM_DEFAULT_MAX_LATENESS_RATIO'] is defined, this value takes the precedence in the calculation
      # (if there is no end to the timewindow, the maximum lateness is 0 since tardiness is not possible in any case)
      hash[:maximum_lateness] ||= hash[:end] ? (DEFAULT_MAX_LATENESS_RATIO.to_f * (hash[:end] - hash[:start].to_i)).round : 0

      super(hash)
    end

    def update(max_time)
      return unless self.end.nil?

      self.end = max_time
      self.maximum_lateness = (DEFAULT_MAX_LATENESS_RATIO.to_f * (self.end - self.start)).round
    end
  end
end
