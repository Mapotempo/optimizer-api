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
require 'date'


require './api/v01/api_base'
require './api/v01/entities/status'
require './api/v01/entities/vrp_result'

module Api
  module V01
    class Vrp < APIBase
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      default_format :json

      def self.vrp_request_timewindow(this)
        this.optional(:start, type: Integer, desc: 'Beginning of the current timewindow in seconds')
        this.optional(:end, type: Integer, desc: 'End of the current timewindow in seconds')
        # this.at_least_one_of :start, :end
      end

      def self.vrp_request_date_range(this)
        this.optional(:start, type: Date, desc: '')
        this.optional(:end, type: Date, desc: '')
      end

      def self.vrp_request_activity(this)
        this.optional(:duration, type: Float, desc: 'time in seconds while the current activity stand until it\'s over')
        this.optional(:setup_duration, type: Float, desc: 'time at destination before the proper activity is effectively performed')
        this.optional(:timewindow_start_day_shift_number, type: Integer, desc: '')
        this.requires(:point_id, type: String, desc: 'reference to the associated point')
        this.optional(:timewindows, type: Array, desc: 'Time slot while the activity may be performed') do
          Vrp.vrp_request_timewindow(self)
        end
      end

      namespace :vrp do
        resource :submit do
          desc 'Submit VRP problem', {
            nickname: 'vrp',
            success: VrpResult,
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: ''
          }
          params {
            requires(:vrp, type: Hash, documentation: {param_type: 'body'}) do
              optional(:matrices, type: Array, desc: 'Define all the distances between each point of problem') do
                requires(:id, type: String)
                optional(:matrix_time, type: Array[Array[Float]], desc: 'Matrix of time, travel duration between each pair of point in the problem')
                optional(:matrix_distance, type: Array[Array[Float]], desc: 'Matrix of distance, travel distance between each pair of point in the problem')
              end

              optional(:points, type: Array, desc: 'Particular place in the map') do
                requires(:id, type: String)
                optional(:matrix_index, type: Integer, desc: 'Index within the matrices, required if the matrices are already given')
                optional(:location, type: Hash, desc: 'Location of the point if the matrices are not given') do
                  requires(:lat, type: Float, desc: 'Latitude coordinate')
                  requires(:lon, type: Float, desc: 'Longitude coordinate')
                end
                at_least_one_of :matrix_index, :location
              end

              optional(:units, type: Array, desc: 'The name of a Capacity/Quantity') do
                requires(:id, type: String)
                optional(:label, type: String, desc: 'Name of the unit')
              end

              optional(:rests, type: Array, desc: 'Break within a vehicle tour') do
                requires(:id, type: String)
                requires(:duration, type: Float, desc: 'Duration of the vehicle rest')
                optional(:timewindows, type: Array, desc: 'Time slot while the rest may begin') do
                  Vrp.vrp_request_timewindow(self)
                end
                optional(:late_multiplier, type: Float, desc: '(not used)')
                optional(:exclusion_cost, type: Float, desc: '(not used)')
              end

              requires(:vehicles, type: Array, desc: 'Usually represent a work day of a particular driver/vehicle') do
                requires(:id, type: String)
                optional(:cost_fixed, type: Float, desc: 'Cost applied if the vehicle is used')
                optional(:cost_distance_multiplier, type: Float, desc: 'Cost applied to the distance performed')
                optional(:cost_time_multiplier, type: Float, desc: 'Cost applied to the total amount of time of travel (Jsprit) or to the total time of route (ORtools)')
                optional(:cost_waiting_time_multiplier, type: Float, desc: 'Cost applied to the waiting in the route (Jsprit Only)')
                optional(:cost_late_multiplier, type: Float, desc: 'Cost applied once a point is deliver late (ORtools only)')
                optional(:cost_setup_time_multiplier, type: Float, desc: 'Cost applied on the setup duration')
                optional(:coef_setup, type: Float, desc: 'Coefficient applied to every setup duration defined in the tour')

                optional(:matrix_id, type: String, desc: 'Related matrix, if already defined')
                optional(:router_mode, type: String, desc: 'car, truck, bicycle...etc. See the Router Wrapper API doc')
                exactly_one_of :matrix_id, :router_mode
                optional(:router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance')
                optional(:speed_multiplier, type: Float, desc: 'multiply the vehicle speed, default : 1.0')
                optional :area, type: Array, coerce_with: ->(c) { c.split(';').collect{ |b| b.split(',').collect{ |f| Float(f) }}}, desc: 'List of latitudes and longitudes separated with commas. Areas separated with semicolons (only available for truck mode at this time).'
                optional :speed_multiplier_area, type: Array[Float], coerce_with: ->(c) { c.split(';').collect{ |f| Float(f) }}, desc: 'Speed multiplier per area, 0 avoid area. Areas separated with semicolons (only available for truck mode at this time).'
                optional :motorway, type: Boolean, default: true, desc: 'Use motorway or not.'
                optional :toll, type: Boolean, default: true, desc: 'Use toll section or not.'
                optional :trailers, type: Integer, desc: 'Number of trailers.'
                optional :weight, type: Float, desc: 'Vehicle weight including trailers and shipped goods, in tons.'
                optional :weight_per_axle, type: Float, desc: 'Weight per axle, in tons.'
                optional :height, type: Float, desc: 'Height in meters.'
                optional :width, type: Float, desc: 'Width in meters.'
                optional :length, type: Float, desc: 'Length in meters.'
                optional :hazardous_goods, type: Symbol, values: [:explosive, :gas, :flammable, :combustible, :organic, :poison, :radio_active, :corrosive, :poisonous_inhalation, :harmful_to_water, :other], desc: 'List of hazardous materials in the vehicle.'

                optional(:duration, type: Float, desc: 'Maximum tour duration')
                optional(:skills, type: Array[Array[String]], desc: 'Particular abilities which could be handle by the vehicle')

                optional(:static_interval_indices, type: Array[Array[Integer]], desc: 'Describe the schedule intervals of availability')
                optional(:static_interval_date, type: Array, desc: 'Describe the schedule date of availability') do
                  Vrp.vrp_request_date_range(self)
                end
                mutually_exclusive :static_interval_indices, :static_interval_date

                optional(:particular_unavailable_indices, type: Array[Integer], desc: 'Express the exceptionnals indices of unavailabilty')
                optional(:particular_unavailable_date, type: Array, desc: 'Express the exceptionnals days of unavailability')
                mutually_exclusive :particular_unavailable_indices, :particular_unavailable_date

                optional(:sequence_timewindow_start_index, type: Integer, desc: '')

                optional(:start_point_id, type: String, desc: 'Begin of the tour')
                optional(:end_point_id, type: String, desc: 'End of the tour')
                optional(:capacities, type: Array, desc: 'Define the limit of entities the vehicle could carry') do
                  requires(:unit_id, type: String, desc: 'Unit of the capacity')
                  requires(:limit, type: Float, desc: 'Maximum capacity which could be take away')
                  optional(:initial, type: Float, desc: 'Initial quantity value in the vehicle')
                  optional(:overload_multiplier, type: Float, desc: 'Allow to exceed the limit against this cost (ORtools only)')
                end

                optional(:sequence_timewindows, type: Array, desc: '') do
                  Vrp.vrp_request_timewindow(self)
                end
                optional(:timewindow, type: Hash, desc: 'Time window whithin the vehicle may be on route') do
                  Vrp.vrp_request_timewindow(self)
                end
                mutually_exclusive :sequence_timewindows, :timewindow

                optional(:rest_ids, type: Array[String], desc: 'Breaks whithin the tour')
              end

              optional(:services, type: Array, desc: 'Independant activity, which does not require a context') do
                requires(:id, type: String)
                optional(:late_multiplier, type: Float, desc: 'Override the late_multiplier defined at the vehicle level (ORtools only)')
                optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8)')

                optional(:visits_number, type: Integer, desc: 'Total number of visits over the complete schedule')
                optional(:visits_range_days_number, type: Integer, desc: '')

                optional(:static_interval_indices, type: Array[Array[Integer]], desc: '')
                optional(:static_interval_date, type: Array, desc: '') do
                  Vrp.vrp_request_date_range(self)
                end
                mutually_exclusive :static_interval_indices, :static_interval_date

                optional(:particular_unavailable_indices, type: Array[Array[Integer]], desc: 'Express the exceptionnals indices of unavailabilty')
                optional(:particular_unavailable_date, type: Array, desc: 'Express the exceptionnals days of unavailability')
                mutually_exclusive :particular_unavailable_indices, :particular_unavailable_date

                optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the service is assigned')
                optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this service')

                requires(:type, type: Symbol, desc: 'service, pickup or delivery')
                requires(:activity, type: Hash, desc: 'Details of the activity performed to accomplish the current service') do
                  Vrp.vrp_request_activity(self)
                end
                optional(:quantities, type: Array, desc: 'Define the entities which are taken or dropped') do
                  requires(:unit_id, type: String, desc: 'Unit related to this quantity')
                  requires(:value, type: Float, desc: 'Value of the current quantity')
                end
              end
              optional(:shipments, type: Array, desc: 'Link directly one activity of collection to another of drop off') do
                requires(:id, type: String, desc: '')
                optional(:late_multiplier, type: Float, desc: 'Override the late_multiplier defined at the vehicle level (ORtools only)')
                optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8)')
                optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the shipment is assigned')
                optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this shipment')
                requires(:pickup, type: Hash, desc: 'Activity of collection') do
                  Vrp.vrp_request_activity(self)
                end
                requires(:delivery, type: Hash, desc: 'Activity of drop off') do
                  Vrp.vrp_request_activity(self)
                end
                optional(:quantities, type: Array, desc: 'Define the entities which are taken and dropped') do
                  requires(:unit_id, type: String, desc: 'Unit related to this quantity')
                  requires(:value, type: Float, desc: 'Value of the current quantity')
                end
              end
              at_least_one_of :services, :shipments

              optional(:configuration, type: Hash, desc: 'Describe the limitations of the solve in term of computation') do
                optional(:preprocessing, type: Hash, desc: 'Parameters independant from the search') do
                  optional(:cluster_threshold, type: Float, desc: 'Regroup close points which constitute a cluster into a single geolocated point')
                  optional(:force_cluster, type: Boolean, desc: 'Force to cluster visits even if containing timewindows and quantities')
                  optional(:prefer_short_segment, type: Boolean, desc: 'Could allow to pass multiple time in the same street but deliver in a single row')
                end
                optional(:resolution, type: Hash, desc: 'Parameters used to stop the search') do
                  optional(:duration, type: Integer, desc: 'Maximum duration of resolution')
                  optional(:iterations, type: Integer, desc: 'Maximum number of iterations (Jsprit only)')
                  optional(:iterations_without_improvment, type: Integer, desc: 'Maximum number of iterations without improvment from the best solution already found')
                  optional(:stable_iterations, type: Integer, desc: 'maximum number of iterations without variation in the solve bigger than the defined coefficient (Jsprit only)')
                  optional(:stable_coefficient, type: Float, desc: 'variation coefficient related to stable_iterations (Jsprit only)')
                  optional(:initial_time_out, type: Integer, desc: 'minimum solve duration before the solve could stop (x10 in order to find the first solution) (ORtools only)')
                  optional(:time_out_multiplier, type: Integer, desc: 'the solve could stop itself if the solve duration without finding a new solution is greater than the time currently elapsed multiplicate by this parameter (ORtools only)')
                  at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient, :initial_time_out
                end
                optional(:schedule, type: Hash, desc: 'Describe the general settings of a schedule') do
                  optional(:range_indices, type: Array[Float], desc: '')
                  optional(:range_date, type: Array[Date], desc: '')
                  mutually_exclusive :range_indices, :range_date
                  optional(:unavailable_indices, type: Array[Float], desc: '')
                  optional(:unavailable_date, type: Array[Date], desc: '')
                  mutually_exclusive :unavailable_indices, :unavailable_date
                end
              end
            end
          }
          post do
            begin
              if ENV['DUMP_VRP'] || OptimizerWrapper::DUMP_VRP
                path = ENV['DUMP_VRP'] ?
                  'test/fixtures/' + ENV['DUMP_VRP'].gsub(/[^a-z0-9\-]+/i, '_') :
                  'tmp/vrp_' + Time.now.strftime("%Y-%m-%d_%H-%M-%S")
                File.write(path + '.json', {vrp: params[:vrp]}.to_json)
              end
              vrp = ::Models::Vrp.create({})
              [:matrices, :units, :points, :rests, :vehicles, :services, :shipments, :configuration].each{ |key|
                (vrp.send "#{key}=", params[:vrp][key]) if params[:vrp][key]
              }
              if !vrp.valid?
                error!({status: 'Model Validation Error', detail: vrp.errors}, 400)
              else
                ret = OptimizerWrapper.wrapper_vrp(params[:api_key], APIBase.services(params[:api_key]), vrp)
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
                  error!({status: 'Internal Server Error'}, 500)
                end
              end
            ensure
              ::Models.delete_all
            end
          end
        end

        resource :jobs do
          desc 'Fetch vrp job status', {
            nickname: 'job',
            success: VrpResult,
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: 'Get the Job status and details, contains progress avancement. Returns the best actual solutions currently found.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if !job
              error!({status: 'Not Found', detail: "Not found job with id='#{id}'"}, 404)
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
                OptimizerWrapper.job_remove(params[:api_key], id)
              end
            end
          end

          desc 'List vrp jobs', {
            nickname: 'listJobs',
            success: VrpJobsList,
            detail: 'List running or queued jobs.'
          }
          get do
            status 200
            present OptimizerWrapper.job_list(params[:api_key]), with: Grape::Presenters::Presenter
          end

          desc 'Delete vrp job', {
            nickname: 'deleteJob',
            success: {code: 204},
            failure: [
              {code: 404, message: 'Not Found', model: ::Api::V01::Status}
            ],
            detail: 'Kill the job. This operation may have delay.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by create VRP problem.'
          }
          delete ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            if !job
              status 404
              error!({status: 'Not Found', detail: "Not found job with id='#{id}'"}, 404)
            else
              OptimizerWrapper.job_kill(params[:api_key], id)
              status 204
            end
          end
        end
      end
    end
  end
end
