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
require './api/v01/entities/error'
require './api/v01/entities/vrp_result'

module Api
  module V01
    class Vrp < APIBase
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      default_format :json
      version '0.1', using: :path

      def self.vrp_request_timewindow(this)
        this.optional(:start, type: Integer)
        this.optional(:end, type: Integer)
        this.at_least_one_of :start, :end
      end

      def self.vrp_request_activity(this)
        this.optional(:duration, type: Float)
        this.optional(:setup_duration, type: Float)
        this.requires(:point_id, type: String)
        this.optional(:quantities, type: Array) do
          requires(:id, type: String)
          requires(:values, type: Array[Float])
        end
        this.optional(:timewindows, type: Array) do
          Vrp.vrp_request_timewindow(self)
        end
      end

      namespace :vrp do
        resource :submit do
          desc 'Submit VRP problem', {
            named: 'vrp',
            success: VrpResult,
            failure: [
              [400, 'Bad Request', ::Api::V01::Error]
            ]
          }
          params {
            requires(:vrp, type: Hash, documentation: {param_type: 'body'}) do
              optional(:matrix_time, type: Array[Array[Float]])
              optional(:matrix_distance, type: Array[Array[Float]])

              optional(:points, type: Array) do
                requires(:id, type: String)
                optional(:matrix_index, type: Integer)
                optional(:location, type: Hash) do
                  requires(:lat, type: Float)
                  requires(:lon, type: Float)
                end
                at_least_one_of :matrix_index, :location
              end

              optional(:services, type: Array) do
                requires(:id, type: String)
                optional(:late_multiplier, type: Float)
                optional(:exclusion_cost, type: Float)
                optional(:skills, type: Array[String])
                requires(:activity, type: Hash) do
                  Vrp.vrp_request_activity(self)
                end
                optional(:quantities, type: Array[Array[Float]])
              end
              optional(:shipments, type: Array) do
                requires(:id, type: String)
                optional(:late_multiplier, type: Float)
                optional(:exclusion_cost, type: Float)
                optional(:skills, type: Array[String])
                requires(:pickup, type: Hash) do
                  Vrp.vrp_request_activity(self)
                end
                requires(:delivery, type: Hash) do
                  Vrp.vrp_request_activity(self)
                end
                optional(:quantities, type: Array) do
                  requires(:id, type: String)
                  requires(:values, type: Array[Float])
                end
              end
              at_least_one_of :services, :shipments

              optional(:rests, type: Array) do
                requires(:id, type: String)
                requires(:duration, type: Float)
                optional(:late_multiplier, type: Float)
                optional(:exclusion_cost, type: Float)
              end

              requires(:vehicles, type: Array) do
                requires(:id, type: String)
                optional(:cost, type: Hash) do
                  optional(:fixed, type: Float)
                  optional(:distance_multiplier, type: Float)
                  optional(:time_multiplier, type: Float)
                  optional(:waiting_time_multiplier, type: Float)
                  optional(:late_multiplier, type: Float)
                  optional(:setup_time_multiplier, type: Float)
                  optional(:setup, type: Float)
                end

                optional(:router_mode, type: String)
                optional(:router_dimension, type: String, values: ['time', 'distance'])
                optional(:speed_multiplier, type: Float)
                optional(:duration, type: Float)
                optional(:skills, type: Array[Array[String]])

                optional(:start_point_id, type: String)
                optional(:end_point_id, type: String)
                optional(:quantities, type: Array) do
                  requires(:id, type: String)
                  requires(:values, type: Array[Float])
                end
                optional(:timewindows, type: Array) do
                  Vrp.vrp_request_timewindow(self)
                end
                optional(:rest_ids, type: Array[String])
              end

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
                error!({error: 'Model Validation Error', detail: vrp.errors}, 400)
              else
                ret = OptimizerWrapper.wrapper_vrp(APIBase.services(params[:api_key]), vrp)
                if ret.is_a?(String)
                  #present result, with: VrpResult
                  status 201
                  present({
                    job: {
                      id: ret,
                      status: :queued
                    }
                  }, with: Grape::Presenters::Presenter)
                elsif ret.is_a?(Hash)
                  status 200
                  present({
                    solutions: [ret],
                    job: {
                      status: :completed,
                    }
                  }, with: Grape::Presenters::Presenter)
                else
                  error!({error: 'Internal Server Error'}, 500)
                end
              end
            ensure
              ::Models.delete_all
            end
          end
        end

        resource :job do
          desc 'Fetch vrp job status', {
            named: 'job',
            success: VrpResult,
            failure: [
              [404, 'Not Found', ::Api::V01::Error]
            ]
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if !job
              error!({error: 'Not Found', detail: "Not found job with id='#{id}'"}, 404)
            else
              solution = OptimizerWrapper::Result.get(id) || {}
              if job.killed? || job.failed?
                status 202
                present({
                  solutions: [solution['result']],
                  job: {
                    id: id,
                    status: job.killed? ? :killed : :failed,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              elsif !job.completed?
                status 200
                present({
                  solutions: [solution['result']],
                  job: {
                    id: id,
                    status: job.queued? ? :queued : job.working? ? :working : nil,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              else
                status 200
                present({
                  solutions: [solution['result']],
                  job: {
                    id: id,
                    status: :completed,
                    avancement: job.message,
                    graph: solution['graph']
                  }
                }, with: Grape::Presenters::Presenter)
              end
            end
          end

          desc 'Delete vrp job', {
            named: 'deleteJob',
            failure: [
              [404, 'Not Found', ::Api::V01::Error]
            ]
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          delete ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if !job
              status 404
              error!({error: 'Not Found', detail: "Not found job with id='#{id}'"}, 404)
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
