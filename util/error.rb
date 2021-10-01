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
# frozen_string_literal: true

module OptimizerWrapper
  class StandardErrorWithData < StandardError
    attr_reader :data

    def initialize(msg, data = [])
      @data = data
      super(msg)
    end
  end

  class UnsupportedProblemError     < StandardErrorWithData; end

  class ClusteringError             < StandardError; end
  class DiscordantProblemError      < StandardError; end
  class JobKilledError              < StandardError; end
  class PeriodicHeuristicError      < StandardError; end
  class UnsupportedRouterModeError  < StandardError; end
end
