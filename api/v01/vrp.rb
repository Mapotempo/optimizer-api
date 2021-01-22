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
require 'csv'
require 'date'
require 'digest/md5'
require 'grape'
require 'grape-swagger'
require 'charlock_holmes'

require './api/v01/api_base'
require './api/v01/entities/status'
require './api/v01/entities/vrp_input'
require './api/v01/entities/vrp_result'

module Api
  module V01
    module CSVParser
      def self.call(object, _env)
        unless object.valid_encoding?
          detection = CharlockHolmes::EncodingDetector.detect(object)
          return false if !detection[:encoding]

          object = CharlockHolmes::Converter.convert(object, detection[:encoding], 'UTF-8')
        end
        line = object.lines.first
        split_comma, split_semicolon, split_tab = line.split(','), line.split(';'), line.split("\t")
        _split, separator = [[split_comma, ',', split_comma.size], [split_semicolon, ';', split_semicolon.size], [split_tab, "\t", split_tab.size]].max_by{ |a| a[2] }
        CSV.parse(object.force_encoding('utf-8'), col_sep: separator, headers: true).collect{ |row|
          r = row.to_h
          new_r = r.clone

          r.each_key{ |key|
            next unless key.include?('.')

            part = key.split('.', 2)
            new_r.deep_merge!(part[0] => { part[1] => r[key] })
            new_r.delete(key)
          }
          r = new_r

          json = r['json']
          if json # Open the secret short cut
            r.delete('json')
            r.deep_merge!(JSON.parse(json))
          end

          r.with_indifferent_access
        }
      end
    end

    class Vrp < APIBase
      include Grape::Extensions::Hash::ParamBuilder

      parser :csv, CSVParser

      namespace :vrp do # rubocop:disable Metrics/BlockLength
        helpers VrpInput, VrpConfiguration, VrpMisc, VrpMissions, VrpShared, VrpVehicles
        resource :submit do # rubocop:disable Metrics/BlockLength
          desc 'Submit VRP problem', {

            nickname: 'submit_vrp',
            success: VrpResult,
            failure: [
              { code: 400, message: 'Bad Request', model: ::Api::V01::Status }
            ],
            detail: 'Submit vehicle routing problem. If the problem can be quickly solved, the solution is returned in the response. In other case, the response provides a job identifier in a queue: you need to perfom another request to fetch vrp job status and solution.'
          }
          params {
            use(:input)
          }
          post do
            # Api key is not declared as part of the VRP and must be handled carefully and separatly from other parameters
            api_key = params[:api_key]
            checksum = Digest::MD5.hexdigest Marshal.dump(params)
            d_params = declared(params, include_missing: false)
            vrp_params = d_params[:points] ? d_params : d_params[:vrp]
            APIBase.dump_vrp_dir.write([api_key, vrp_params[:name], checksum].compact.join('_'), d_params.to_json) if OptimizerWrapper.config[:dump][:vrp]

            params_limit = APIBase.profile(params[:api_key])[:params_limit].merge(OptimizerWrapper.access[api_key][:params_limit] || {})
            params_limit.each{ |key, value|
              next if vrp_params[key].nil? || value.nil? || vrp_params[key].size <= value

              error!({
                message: "Exceeded #{key} limit authorized for your account: #{value}. Please contact support or sales to increase limits."
              }, 413)
            }

            vrp = ::Models::Vrp.create(vrp_params)
            count :optimize, true, vrp.transactions

            if !vrp.valid? || vrp_params.nil? || vrp_params.keys.empty?
              vrp.errors.add(:empty_file, message: 'JSON file is empty') if vrp_params.nil?
              vrp.errors.add(:empty_vrp, message: 'VRP structure is empty') if vrp_params&.keys&.empty?
              error!("Model Validation Error: #{vrp.errors}", 400)
            else
              ret = OptimizerWrapper.wrapper_vrp(api_key, APIBase.profile(api_key), vrp, checksum)
              count_incr :optimize, transactions: vrp.transactions
              if ret.is_a?(String)
                # present result, with: VrpResult
                status 201
                present({ job: { id: ret, status: :queued }}, with: Grape::Presenters::Presenter)
              elsif ret.is_a?(Hash)
                status 200
                if vrp.restitution_csv
                  present(OptimizerWrapper.build_csv(ret.deep_stringify_keys), type: CSV)
                else
                  present({ solutions: [ret], job: { status: :completed }}, with: Grape::Presenters::Presenter)
                end
              else
                error!('Internal Server Error', 500)
              end
            end
          ensure
            ::Models.delete_all
          end
        end

        resource :jobs do # rubocop:disable Metrics/BlockLength
          desc 'Fetch vrp job status', {
            nickname: 'get_job',
            success: VrpResult,
            failure: [
              { code: 404, message: 'Not Found', model: ::Api::V01::Status }
            ],
            detail: 'Get the job status and details, contains progress avancement. Return the best actual solutions currently found.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by creating VRP problem.'
          }
          get ':id' do # rubocop:disable Metrics/BlockLength
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            stored_result = APIBase.dump_vrp_dir.read([id, params[:api_key], 'solution'].join('_'))
            solution = stored_result && Marshal.load(stored_result) # rubocop:disable Security/MarshalLoad

            if solution.nil? && (job.nil? || job.killed? || Resque::Plugins::Status::Hash.should_kill?(id) || job['options']['api_key'] != params[:api_key])
              status 404
              error!({ message: "Job with id='#{id}' not found" }, 404)
            end

            solution ||= OptimizerWrapper::Result.get(id) || {}
            output_format = params[:format]&.to_sym || ((solution && solution['csv']) ? :csv : env['api.format'])
            env['api.format'] = output_format # To override json default format

            if job&.completed? # job can still be nil if we have the solution from the dump
              OptimizerWrapper.job_remove(params[:api_key], id)
              APIBase.dump_vrp_dir.write([id, params[:api_key], 'solution'].join('_'), Marshal.dump(solution)) if stored_result.nil? && OptimizerWrapper.config[:dump][:solution]
            end

            status 200

            if output_format == :csv && (job.nil? || job.completed?) # At this step, if the job is nil then it has already been retrieved into the result store
              present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
            else
              present({
                solutions: [solution['result']].flatten(1),
                job: {
                  id: id,
                  status: job&.status&.to_sym || :completed, # :queued, :working, :completed, :failed
                  avancement: job&.message,
                  graph: solution['graph']
                }
              }, with: Grape::Presenters::Presenter)
            end
          end

          desc 'List vrp jobs', {
            nickname: 'get_job_list',
            success: VrpJobsList,
            detail: 'List running or queued jobs.'
          }
          get do
            status 200
            present OptimizerWrapper.job_list(params[:api_key]), with: Grape::Presenters::Presenter
          end

          desc 'Delete vrp job', {
            nickname: 'deleteJob',
            success: { code: 204 },
            failure: [
              { code: 404, message: 'Not Found', model: ::Api::V01::Status }
            ],
            detail: 'Kill the job. This operation may have delay, since if the job is working it will be killed during the next iteration.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by creating VRP problem.'
          }
          delete ':id' do # rubocop:disable Metrics/BlockLength
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)

            if !job || job.killed? || Resque::Plugins::Status::Hash.should_kill?(id) || job['options']['api_key'] != params[:api_key]
              status 404
              error!({ message: "Job with id='#{id}' not found" }, 404)
            else
              OptimizerWrapper.job_kill(params[:api_key], id)
              job.status = 'killed'
              solution = OptimizerWrapper::Result.get(id)
              status 202
              if solution && !solution.empty?
                output_format = params[:format]&.to_sym || (solution['csv'] ? :csv : env['api.format'])
                if output_format == :csv
                  present(OptimizerWrapper.build_csv(solution['result']), type: CSV)
                else
                  present({
                    solutions: [solution['result']],
                    job: {
                      id: id,
                      status: :killed,
                      avancement: job.message,
                      graph: solution['graph']
                    }
                  }, with: Grape::Presenters::Presenter)
                end
              else
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
