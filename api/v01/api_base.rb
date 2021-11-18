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

require_all 'models'

module Api
  module V01
    class APIBase < Grape::API
      def self.tmp_vrp_dir
        ::OptimizerWrapper.tmp_vrp_dir
      end

      def self.dump_vrp_dir
        ::OptimizerWrapper.dump_vrp_dir
      end

      def self.profile(api_key)
        raise 'Profile missing in configuration' unless ::OptimizerWrapper.config[:profiles].has_key? ::OptimizerWrapper.access[api_key][:profile]

        ::OptimizerWrapper.config[:profiles][::OptimizerWrapper.access[api_key][:profile]].deep_merge(
          ::OptimizerWrapper.access[api_key].except(:profile)
        )
      end
    end
  end
end
