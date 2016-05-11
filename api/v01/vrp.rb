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

require './api/v01/api_base'
require './api/v01/entities/vrp_request'
require './api/v01/entities/vrp_result'

module Api
  module V01
    class Vrp < APIBase
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      default_format :json
      version '0.1', using: :path

      namespace :vrp do
        resource :submit do
          desc 'Submit VRP problem', {
            nickname: 'vrp',
            entity: VrpResult
          }
          params {
          }
          post do
            vrp = ::Models::Vrp.create(params[:vrp])
            ret = OptimizerWrapper.wrapper_vrp(APIBase.services(params[:api_key]), vrp)
            if ret.is_a?(String)
              #present result, with: VrpResult
              status 201
              {
                job: {
                  id: ret,
                  status: :queued,
                  retry: nil
                }
              }
            elsif ret.is_a?(Hash)
              status 200
              {
                solution: ret
              }
            else
              error!('500 Internal Server Error', 500)
            end
          end
        end

        resource :job do
          desc 'Fetch vrp job status', {
            nickname: 'job',
            entity: VrpResult
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if job.status != 'completed'
              status 201
              {
                job: {
                  id: id,
                  status: job.queued? ? :queued : job.working? ? :working : nil,
                  retry: nil,
                  avancement: job.message
                }
              }
            else
              status 200
              solution = OptimizerWrapper::Result.get(id)
              {
                solution: solution,
                job: {
                  id: id,
                  status: :completed,
                  avancement: job.message
                }
              }
            end
          end

          desc 'Delete vrp job', {
            nickname: 'deleteJob',
            entity: VrpResult
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          delete ':id' do
            status 204
            Resque::Plugins::Status::Hash.kill(params[:id])
          end
        end
      end
    end
  end
end
