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
require 'active_support/concern'

module ValidateTimewindows
  extend ActiveSupport::Concern

  included do
    validate :validate_timewindows
  end

  private

  def validate_timewindows
    t = timewindows.collect{ |timewindow|
      [timewindow.start, timewindow.end]
    }

    t.flatten!
    if t.size > 2 && !t[1..-2].all?
      errors.add(:timewindows, 'only start of first or end of last timewindow can be left blank')
    end
    t.compact!
    if t != t.sort
      errors.add(:timewindows, 'timewindows start and end must be in ascending order')
    end
  end
end
