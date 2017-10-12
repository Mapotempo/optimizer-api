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
require 'digest/md5'


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
        this.optional(:day_index, type: Integer, values: 0..6, desc: '[planning] Day index of the current timewindow within the periodic week, (monday = 0, ..., sunday = 6)')
        # this.at_least_one_of :start, :end
      end

      def self.vrp_request_date_range(this)
        this.optional(:start, type: Date, desc: '')
        this.optional(:end, type: Date, desc: '')
      end

      def self.vrp_request_matrices(this)
        this.requires(:id, type: String)
        this.optional(:time, type: Array[Array[Float]], desc: 'Matrix of time, travel duration between each pair of point in the problem')
        this.optional(:distance, type: Array[Array[Float]], desc: 'Matrix of distance, travel distance between each pair of point in the problem')
        this.optional(:value, type: Array[Array[Float]], desc: 'Matrix of values, travel value between each pair of point in the problem if not distance or time related')
      end

      def self.vrp_request_point(this)
        this.requires(:id, type: String)
        this.optional(:matrix_index, type: Integer, desc: 'Index within the matrices, required if the matrices are already given')
        this.optional(:location, type: Hash, desc: 'Location of the point if the matrices are not given') do
          self.requires(:lat, type: Float, allow_blank: false, desc: 'Latitude coordinate')
          self.requires(:lon, type: Float, allow_blank: false, desc: 'Longitude coordinate')
        end
        this.at_least_one_of :matrix_index, :location
      end

      def self.vrp_request_unit(this)
        this.requires(:id, type: String)
        this.optional(:label, type: String, desc: 'Name of the unit')
        this.optional(:counting, type: Boolean, desc: 'Define if the unit is a counting one, which allow to count the number of stop in a single route')
      end

      def self.vrp_request_rest(this)
        this.requires(:id, type: String)
        this.requires(:duration, type: Float, desc: 'Duration of the vehicle rest')
        this.optional(:timewindows, type: Array, desc: 'Time slot while the rest may begin') do
          Vrp.vrp_request_timewindow(self)
        end
        this.optional(:late_multiplier, type: Float, desc: '(not used)')
        this.optional(:exclusion_cost, type: Float, desc: '(not used)')
      end

      def self.vrp_request_zone(this)
        this.requires(:id, type: String, desc: '')
        this.requires(:polygon, type: Hash, desc: 'geometry which describe the area')
        this.optional(:allocations, type: Array[Array[String]], desc: 'Define by which vehicle vehicles combination the zone could to be served')
      end

      def self.vrp_request_activity(this)
        this.optional(:duration, type: Float, desc: 'time in seconds while the current activity stand until it\'s over')
        this.optional(:additional_value, type: Integer, desc: 'Additional value associated to the visit')
        this.optional(:setup_duration, type: Float, desc: 'time at destination before the proper activity is effectively performed')
        this.optional(:late_multiplier, type: Float, desc: 'Override the late_multiplier defined at the vehicle level (ORtools only)')
        this.optional(:timewindow_start_day_shift_number, type: Integer, desc: '')
        this.requires(:point_id, type: String, desc: 'reference to the associated point')
        this.optional(:value_matrix_index, type: Integer, desc: 'associated value matrix index')
        this.optional(:timewindows, type: Array, desc: 'Time slot while the activity may be performed') do
          Vrp.vrp_request_timewindow(self)
        end
      end

      def self.vrp_request_quantity(this)
        this.requires(:unit_id, type: String, desc: 'Unit related to this quantity')
        this.optional(:value, type: Float, desc: 'Value of the current quantity')
        this.optional(:setup_value, type: Integer, desc: 'If the associated unit is a counting one, define the default value to count for this stop (additional quantities for this specific service are to define with the value tag)')
      end

      def self.vrp_request_capacity(this)
        this.requires(:unit_id, type: String, desc: 'Unit of the capacity')
        this.requires(:limit, type: Float, desc: 'Maximum capacity which could be take away')
        this.optional(:initial, type: Float, desc: 'Initial quantity value in the vehicle')
        this.optional(:overload_multiplier, type: Float, desc: 'Allow to exceed the limit against this cost (ORtools only)')
      end

      def self.vrp_request_vehicle(this)
        this.requires(:id, type: String)
        this.optional(:cost_fixed, type: Float, desc: 'Cost applied if the vehicle is used')
        this.optional(:cost_distance_multiplier, type: Float, desc: 'Cost applied to the distance performed')
        this.optional(:cost_time_multiplier, type: Float, desc: 'Cost applied to the total amount of time of travel (Jsprit) or to the total time of route (ORtools)')
        this.optional(:cost_value_multiplier, type: Float, desc: 'multiplier applied to the value matrix and additional activity value')
        this.optional(:cost_waiting_time_multiplier, type: Float, desc: 'Cost applied to the waiting in the route (Jsprit Only)')
        this.optional(:cost_late_multiplier, type: Float, desc: 'Cost applied once a point is deliver late (ORtools only)')
        this.optional(:cost_setup_time_multiplier, type: Float, desc: 'Cost applied on the setup duration')
        this.optional(:coef_setup, type: Float, desc: 'Coefficient applied to every setup duration defined in the tour')
        this.optional(:force_start, type: Boolean, desc: 'Force the vehicle to start as soon as the vehicle timewindow is open')

        this.optional(:matrix_id, type: String, desc: 'Related matrix, if already defined')
        this.optional(:value_matrix_id, type: String, desc: 'Related value matrix, if defined')
        this.optional(:router_mode, type: String, desc: 'car, truck, bicycle...etc. See the Router Wrapper API doc')
        this.exactly_one_of :matrix_id, :router_mode

        this.optional(:router_dimension, type: String, values: ['time', 'distance'], desc: 'time or dimension, choose between a matrix based on minimal route duration or on minimal route distance')
        this.optional(:speed_multiplier, type: Float, desc: 'multiply the vehicle speed, default : 1.0')
        this.optional :area, type: Array, coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |b| b.split(',').collect{ |f| Float(f) }} : c }, desc: 'List of latitudes and longitudes separated with commas. Areas separated with pipes (only available for truck mode at this time).'
        this.optional :speed_multiplier_area, type: Array[Float], coerce_with: ->(c) { c.is_a?(String) ? c.split(/;|\|/).collect{ |f| Float(f) } : c }, desc: 'Speed multiplier per area, 0 avoid area. Areas separated with pipes (only available for truck mode at this time).'
        this.optional :motorway, type: Boolean, default: true, desc: 'Use motorway or not.'
        this.optional :toll, type: Boolean, default: true, desc: 'Use toll section or not.'
        this.optional :trailers, type: Integer, desc: 'Number of trailers.'
        this.optional :weight, type: Float, desc: 'Vehicle weight including trailers and shipped goods, in tons.'
        this.optional :weight_per_axle, type: Float, desc: 'Weight per axle, in tons.'
        this.optional :height, type: Float, desc: 'Height in meters.'
        this.optional :width, type: Float, desc: 'Width in meters.'
        this.optional :length, type: Float, desc: 'Length in meters.'
        this.optional :hazardous_goods, type: Symbol, values: [:explosive, :gas, :flammable, :combustible, :organic, :poison, :radio_active, :corrosive, :poisonous_inhalation, :harmful_to_water, :other], desc: 'List of hazardous materials in the vehicle.'
        this.optional :max_walk_distance, type: Float, default: 750, desc: 'Max distance by walk.'
        this.optional :approach, type: Symbol, values: [:unrestricted, :curb], default: :unrestricted, desc: 'Arrive/Leave in the traffic direction.'
        this.optional :snap, type: Float, desc: 'Snap waypoint to junction close by snap distance.'
        this.optional :strict_restriction, type: Boolean, desc: 'Strict compliance with truck limitations.'

        this.optional(:duration, type: Float, desc: 'Maximum tour duration')
        this.optional(:skills, type: Array[Array[String]], desc: 'Particular abilities which could be handle by the vehicle')

        this.optional(:unavailable_work_day_indices, type: Array[Integer], desc: '[planning] Express the exceptionnals indices of unavailabilty')
        this.optional(:unavailable_work_date, type: Array, desc: '[planning] Express the exceptionnals days of unavailability')
        this.mutually_exclusive :unavailable_work_day_indices, :unavailable_work_date

        this.optional(:start_point_id, type: String, desc: 'Begin of the tour')
        this.optional(:end_point_id, type: String, desc: 'End of the tour')
        this.optional(:capacities, type: Array, desc: 'Define the limit of entities the vehicle could carry') do
          Vrp.vrp_request_capacity(self)
        end

        this.optional(:sequence_timewindows, type: Array, desc: '[planning] Define the vehicle work schedule over a period') do
          Vrp.vrp_request_timewindow(self)
        end
        this.optional(:timewindow, type: Hash, desc: 'Time window whithin the vehicle may be on route') do
          Vrp.vrp_request_timewindow(self)
        end
        this.mutually_exclusive :sequence_timewindows, :timewindow

        this.optional(:rest_ids, type: Array[String], desc: 'Breaks whithin the tour')
      end

      def self.vrp_request_service(this)
        this.requires(:id, type: String)
        this.optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8)')

        this.optional(:visits_number, type: Integer, desc: 'Total number of visits over the complete schedule (including the unavailable visit indices)')

        this.optional(:unavailable_visit_indices, type: Array[Integer], desc: '[planning] unavailable indices of visit')

        this.optional(:unavailable_visit_day_indices, type: Array[Integer], desc: '[planning] Express the exceptionnals days indices of unavailabilty')
        this.optional(:unavailable_visit_day_date, type: Array, desc: '[planning] Express the exceptionnals days of unavailability')
        this.mutually_exclusive :unavailable_visit_day_indices, :unavailable_visit_day_date

        this.optional(:minimum_lapse, type: Integer, desc: 'Minimum day lapse between two visits')
        this.optional(:maximum_lapse, type: Integer, desc: 'Maximum day lapse between two visits')

        this.optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the service is assigned')
        this.optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this service')

        this.optional(:type, type: Symbol, desc: 'service, pickup or delivery')
        this.requires(:activity, type: Hash, desc: 'Details of the activity performed to accomplish the current service') do
          Vrp.vrp_request_activity(self)
        end
        this.optional(:quantities, type: Array, desc: 'Define the entities which are taken or dropped') do
          Vrp.vrp_request_quantity(self)
        end
      end

      def self.vrp_request_shipment(this)
        this.requires(:id, type: String, desc: '')
        this.optional(:priority, type: Integer, values: 0..8, desc: 'Priority assigned to the service in case of conflict to assign every jobs (from 0 to 8)')
        this.optional(:sticky_vehicle_ids, type: Array[String], desc: 'Defined to which vehicle the shipment is assigned')
        this.optional(:skills, type: Array[String], desc: 'Particular abilities required by a vehicle to perform this shipment')
        this.requires(:pickup, type: Hash, desc: 'Activity of collection') do
          Vrp.vrp_request_activity(self)
        end
        this.requires(:delivery, type: Hash, desc: 'Activity of drop off') do
          Vrp.vrp_request_activity(self)
        end
        this.optional(:quantities, type: Array, desc: 'Define the entities which are taken and dropped') do
          Vrp.vrp_request_quantity(self)
        end
      end

      def self.vrp_request_relation(this)
        this.requires(:id, type: String, desc: '')
        this.requires(:type, type: String, desc: 'same_vehicle, sequence, direct_sequence, minimum_day_lapse or maximum_day_lapse')
        this.optional(:lapse, type: Integer, desc: 'Only used in case of minimum and maximum day lapse')
        this.requires(:linked_ids, type: Array[String], desc: '')
      end

      def self.vrp_request_preprocessing(this)
        this.optional(:cluster_threshold, type: Float, desc: 'Regroup close points which constitute a cluster into a single geolocated point')
        this.optional(:force_cluster, type: Boolean, desc: 'Force to cluster visits even if containing timewindows and quantities')
        this.optional(:prefer_short_segment, type: Boolean, desc: 'Could allow to pass multiple time in the same street but deliver in a single row')
      end

      def self.vrp_request_resolution(this)
        this.optional(:duration, type: Integer, desc: 'Maximum duration of resolution')
        this.optional(:iterations, type: Integer, desc: 'Maximum number of iterations (Jsprit only)')
        this.optional(:iterations_without_improvment, type: Integer, desc: 'Maximum number of iterations without improvment from the best solution already found')
        this.optional(:stable_iterations, type: Integer, desc: 'maximum number of iterations without variation in the solve bigger than the defined coefficient (Jsprit only)')
        this.optional(:stable_coefficient, type: Float, desc: 'variation coefficient related to stable_iterations (Jsprit only)')
        this.optional(:initial_time_out, type: Integer, desc: 'minimum solve duration before the solve could stop (x10 in order to find the first solution) (ORtools only)')
        this.optional(:time_out_multiplier, type: Integer, desc: 'the solve could stop itself if the solve duration without finding a new solution is greater than the time currently elapsed multiplicate by this parameter (ORtools only)')
        this.optional(:vehicle_limit, type: Integer, desc: 'Limit the maxiumum number of vehicles within a solution')
        this.at_least_one_of :duration, :iterations, :iterations_without_improvment, :stable_iterations, :stable_coefficient, :initial_time_out
      end

      def self.vrp_request_restitution(this)
        this.optional(:geometry, type: Boolean, desc: 'Allow to return the polyline of each route')
        this.optional(:geometry_polyline, type: Boolean, desc: 'Encode the polyline')
        this.optional(:intermediate_solutions, type: Boolean, desc: 'Return intermediate solutions if available')
      end

      def self.vrp_request_schedule(this)
        this.optional(:range_indices, type: Hash, desc: '[planning] Day indices within the plan has to be build')
        this.optional(:range_date, type: Hash, desc: '[planning] Define the total period to consider') do
          Vrp.vrp_request_date_range(self)
        end

        this.mutually_exclusive :range_indices, :range_date
        this.optional(:unavailable_indices, type: Array[Integer], desc: '[planning] Exclude some days indices from the resolution')
        this.optional(:unavailable_date, type: Array[Date], desc: '[planning] Exclude some days from the resolution')
        this.mutually_exclusive :unavailable_indices, :unavailable_date
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
            optional(:vrp, type: Hash) do
              optional(:matrices, type: Array, desc: 'Define all the distances between each point of problem') do
                Vrp.vrp_request_matrices(self)
              end

              optional(:points, type: Array, desc: 'Particular place in the map') do
                Vrp.vrp_request_point(self)
              end

              optional(:units, type: Array, desc: 'The name of a Capacity/Quantity') do
                Vrp.vrp_request_unit(self)
              end

              optional(:rests, type: Array, desc: 'Break within a vehicle tour') do
                Vrp.vrp_request_rest(self)
              end

              optional(:zones, type: Array, desc: '') do
                Vrp.vrp_request_zone(self)
              end

              requires(:vehicles, type: Array, desc: 'Usually represent a work day of a particular driver/vehicle') do
                Vrp.vrp_request_vehicle(self)
              end

              optional(:services, type: Array, desc: 'Independant activity, which does not require a context') do
                Vrp.vrp_request_service(self)
              end
              optional(:shipments, type: Array, desc: 'Link directly one activity of collection to another of drop off') do
                Vrp.vrp_request_shipment(self)
              end
              at_least_one_of :services, :shipments

              optional(:relations, type: Array, desc: '') do
                Vrp.vrp_request_relation(self)
              end

              optional(:configuration, type: Hash, desc: 'Describe the limitations of the solve in term of computation') do
                optional(:preprocessing, type: Hash, desc: 'Parameters independant from the search') do
                  Vrp.vrp_request_preprocessing(self)
                end
                optional(:resolution, type: Hash, desc: 'Parameters used to stop the search') do
                  Vrp.vrp_request_resolution(self)
                end
                optional(:restitution, type: Hash, desc: 'Restitution paramaters') do
                  Vrp.vrp_request_restitution(self)
                end
                optional(:schedule, type: Hash, desc: 'Describe the general settings of a schedule') do
                  Vrp.vrp_request_schedule(self)
                end
              end
            end
          }
          post do
            begin
              if ENV['DUMP_VRP']
                path = 'test/fixtures/' + ENV['DUMP_VRP'].gsub(/[^a-z0-9\-]+/i, '_')
                File.write(path + '.json', {vrp: params[:vrp]}.to_json)
              end
              vrp = ::Models::Vrp.create({})
              [:matrices, :units, :points, :rests, :zones, :vehicles, :services, :shipments, :relations, :configuration].each{ |key|
                (vrp.send "#{key}=", params[:vrp][key]) if params[:vrp][key]
              }
              if !vrp.valid?
                error!({status: 'Model Validation Error', detail: vrp.errors}, 400)
              else
                checksum = Digest::MD5.hexdigest Marshal.dump(params[:vrp])
                APIBase.dump_vrp_cache.write([params[:api_key], checksum].join("_"), {vrp: params[:vrp]}.to_json)
                ret = OptimizerWrapper.wrapper_vrp(params[:api_key], APIBase.services(params[:api_key]), vrp, checksum)
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
              if job.killed? || Resque::Plugins::Status::Hash.should_kill?(id)
                status 404
                error!({status: 'Not Found', detail: "Not found job with id='#{id}'"}, 404)
              elsif job.failed?
                status 202
                present({
                  solutions: [solution['result']],
                  job: {
                    id: id,
                    status: :failed,
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
              solution = OptimizerWrapper::Result.get(id) || {}
              if solution && !solution.empty?
              status 202
              job.status = "killed"
              present({
                solutions: [solution['result']],
                job: {
                  id: id,
                  status: :killed,
                  avancement: job.message,
                  graph: solution['graph']
                }
              }, with: Grape::Presenters::Presenter)
              else
                status 202
                present({
                  job: {
                    id: id,
                    status: :killed,
                  }
                }, with: Grape::Presenters::Presenter)
              end
              OptimizerWrapper.job_remove(params[:api_key], id)
            end
          end
        end
      end
    end
  end
end
