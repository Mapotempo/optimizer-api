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
require './api/v01/entities/vrp_result'
require './api/v01/entities/vrp_request_point'
require './api/v01/entities/vrp_request_service'
require './api/v01/entities/vrp_request_shipment'
require './api/v01/entities/vrp_request_rest'
require './api/v01/entities/vrp_request_vehicle'

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
            success: VrpResult,
            entity: [VrpResult, VrpRequestPoint, VrpRequestService, VrpRequestShipment, VrpRequestRest, VrpRequestVehicle]
          }
          params {
            requires(:vrp, type: Hash) do
              optional(:matrix_time, type: Array[Array[Float]])
              optional(:matrix_distance, type: Array[Array[Float]])

              optional(:points, type: VrpRequestPoint)
              optional(:services, type: VrpRequestService)
              optional(:shipments, type: VrpRequestShipment)
              at_least_one_of :services, :shipments
              optional(:rests, type: VrpRequestRest)
              requires(:vehicles, type: VrpRequestVehicle)
              optional(:units, type: Array[String])

              optional(:configuration, type: Hash) do
                optional(:preprocessing, type: Hash) do
                  optional(:cluster_threshold, type: Float)
                  optional(:prefer_short_segment, type: Boolean)
                end
                optional(:resolution, type: Hash) do
                  optional(:duration, type: Integer)
                  optional(:iterations, type: Integer)
                  optional(:iterations_without_improvment, type: Integer)
                  optional(:stable_iterations, type: Integer)
                  optional(:stable_coefficient, type: Float)
                  at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient
                end
              end
            end
          }
          post do
            begin
              vrp = ::Models::Vrp.create(params[:vrp])
              if !vrp.valid?
                status 400
                vrp.errors
              else
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
                    solution: ret,
                    job: {
                      status: :completed,
                    }
                  }
                else
                  error!('500 Internal Server Error', 500)
                end
              end
            ensure
              ::Models.delete_all
            end
          end
        end

        resource :job do
          desc 'Fetch vrp job status', {
            nickname: 'job',
            success: VrpResult,
            entity: VrpResult
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if !job
              status 404
            else
              solution = OptimizerWrapper::Result.get(id) || {}
              if job.killed? || job.failed?
                status 202
                {
                  solution: solution['result'],
                  job: {
                    id: id,
                    status: job.killed? ? :killed : :failed,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }
              elsif !job.completed?
                status 200
                {
                  solution: solution['result'],
                  job: {
                    id: id,
                    status: job.queued? ? :queued : job.working? ? :working : nil,
                    retry: nil,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }
              else
                status 200
                {
                  solution: solution['result'],
                  job: {
                    id: id,
                    status: :completed,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }
              end
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
            job = Resque::Plugins::Status::Hash.get(params[:id])
            if !job
              status 404
            else
              Resque::Plugins::Status::Hash.kill(params[:id])
              status 204
            end
          end
        end
      end
    end
  end
end
