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
  class Rest < Activity
    field :id
    field :duration, default: 0
    field :late_multiplier, default: 0, vrp_result: :hide
    field :exclusion_cost, default: nil, vrp_result: :hide

    # ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :duration
    # validates_numericality_of :late_multiplier
    # validates_numericality_of :exclusion_cost, allow_nil: true

    has_many :timewindows, class_name: 'Models::Timewindow'
    # include ValidateTimewindows
  end
end
