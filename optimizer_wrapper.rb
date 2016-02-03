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
require 'i18n'

module OptimizerWrapper
  def self.config
    @@c
  end

  def self.wrapper_vrp(params)
    vrp = config[:services][:vrp].find{ |vrp|
      vrp.solve?(params)
    }
    if !vrp
      raise UnsupportedProblemError
    else
      vrp.solve(params)
    end
  end

  class UnsupportedProblemError < StandardError
  end
end
