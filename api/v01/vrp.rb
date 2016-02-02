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
require 'grape'
require 'grape-swagger'

require './api/v01/entities/vrp_request'
require './api/v01/entities/vrp_result'

module Api
  module V01
    class Vrp < Grape::API
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      default_format :json
      version '0.1', using: :path

      resource :vrp do
        desc 'Solve VRP problem', {
          nickname: 'vrp',
          entity: VrpResult
        }
        params {
        }
        post do
          result = OptimizerWrapper.wrapper_vrp(params)
          if result
            #present result, with: VrpResult
            result
          else
            error!('500 Internal Server Error', 500)
          end
        end
      end
    end
  end
end
