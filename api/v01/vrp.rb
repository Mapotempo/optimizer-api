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

require './api/v01/api_base'

require_all './api/v01/entities'

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

      # rubocop:disable Metrics/BlockLength
      namespace :vrp do
        helpers VrpInput, VrpConfiguration, VrpMisc, VrpMissions, VrpShared, VrpVehicles
        resource :submit do
          desc 'Submit VRP problem', {

            nickname: 'submit_vrp',
            success: [{
              code: 200,
              message: 'The VRP has been processed synchronously',
              model: VrpSyncJob
            }, {
              code: 201,
              message: 'The VRP has been placed in a queue to be processed',
              model: VrpAsyncJob
            }],
            failure: [{
                code: 400,
                message: 'Bad Request',
                model: ::Api::V01::Status
              }, {
                code: 401,
                message: 'Unauthorized',
                model: ::Api::V01::Status
              }, {
                code: 402,
                message: "Subscription expired. Please contact support (#{::OptimizerWrapper.config[:product_support_email]}) or sales (#{::OptimizerWrapper.config[:product_sales_email]}) to extend your access period.",
                model: ::Api::V01::Status
              }, {
                code: 413,
                message: "Exceeded limit authorized for your account. Please contact support (#{::OptimizerWrapper.config[:product_support_email]}) or sales (#{::OptimizerWrapper.config[:product_sales_email]}) to increase limits.",
                model: ::Api::V01::Status
            }],
            detail: 'Submit vehicle routing problem. If the problem can be quickly solved, the solution is returned in the response. In other case, the response provides a job identifier in a queue: you need to perfom another request to fetch vrp job status and solution.'
          }
          params {
            use(:input)
          }
          post do
            # Api key is not declared as part of the VRP and must be handled carefully and separatly from other parameters
            api_key = params[:api_key]
            profile = APIBase.profile(api_key)
            d_params = declared(params, include_missing: false)
            checksum = Digest::MD5.hexdigest d_params.to_json

            Raven.tags_context(vrp_checksum: checksum)
            key_print = params[:api_key].rpartition('-')[0]
            key_print = params[:api_key][0..3] if key_print.empty?
            Raven.tags_context(key_print: key_print)
            Raven.user_context(api_key: params[:api_key]) # Filtered in sentry if user_context

            vrp_params = d_params[:points] ? d_params : d_params[:vrp]
            APIBase.dump_vrp_dir.write([key_print, vrp_params[:name] || "no_vrp_name", checksum].compact.join('_'), d_params.to_json) if OptimizerWrapper.config[:dump][:vrp]

            Raven.extra_context(vrp_name: vrp_params[:name])

            params_limit = profile[:params_limit].merge(OptimizerWrapper.access[api_key][:params_limit] || {})
            params_limit.each{ |key, value|
              next if vrp_params[key].nil? || value.nil? || vrp_params[key].size <= value

              error!({
                message: "Exceeded #{key} limit authorized for your account: #{value}. Please contact support (#{::OptimizerWrapper.config[:product_support_email]}) or sales (#{::OptimizerWrapper.config[:product_sales_email]}) to increase limits."
              }, 413)
            }

            vrp = ::Models::Vrp.create(vrp_params)
            count :optimize, true, vrp.transactions

            if !vrp.valid? || vrp_params.nil? || vrp_params.keys.empty?
              vrp.errors.add(:empty_file, message: 'JSON file is empty') if vrp_params.nil?
              vrp.errors.add(:empty_vrp, message: 'VRP structure is empty') if vrp_params&.keys&.empty?
              error!("Model Validation Error: #{vrp.errors}", 400)
            else
              vrp.router = OptimizerWrapper.router(OptimizerWrapper.access[api_key][:router_api_key] || profile[:router_api_key]) if OptimizerWrapper.access[api_key][:router_api_key] || profile[:router_api_key]
              ret = OptimizerWrapper.wrapper_vrp(api_key, profile, vrp, checksum)
              count_incr :optimize, transactions: vrp.transactions
              if ret.is_a?(String)
                status 201
                present({ job: { id: ret, status: :queued }}, with: VrpResult)
              elsif ret.is_a?(Array)
                status 200
                solutions = ret.vrp_result.each(&:deep_symbolize_keys!)
                if vrp.configuration.restitution.csv
                  env['api.format'] = :csv # To override json default format
                  present(OutputHelper::Result.build_csv(solutions), type: CSV)
                else
                  present({
                            solutions: solutions,
                            geojsons: OutputHelper::Result.generate_geometry({ result: solutions }),
                            job: { status: :completed }
                          }, with: VrpResult)
                end
              else
                error!('Internal Server Error', 500)
              end
            end
          ensure
            ::Models.delete_all
          end
        end

        resource :validate do
          desc 'Validate VRP problem', {
            nickname: 'validate_vrp',
            success: [{
              code: 200,
              message: 'Vrp has been validated'
            }],
            failure: [{
                code: 400,
                message: 'Bad Request',
                model: ::Api::V01::Status
              }]
          }
          params {
            use(:input)
          }
          post do
            d_params = declared(params, include_missing: false) # Filtered in sentry if user_context
            vrp_params = d_params[:points] ? d_params : d_params[:vrp]
            ::Models::Vrp.create(vrp_params)
            present(d_params)
          end
        ensure
          ::Models.delete_all
        end

        resource :jobs do
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
          get ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)
            stored_result = APIBase.dump_vrp_dir.read([id, params[:api_key], 'solution'].join('_'))
            result_object = stored_result && Oj.load(stored_result) rescue Marshal.load(stored_result) # rubocop:disable Security/MarshalLoad, Style/RescueModifier

            if result_object.nil? && (job.nil? || job.killed? || Resque::Plugins::Status::Hash.should_kill?(id) || job['options']['api_key'] != params[:api_key])
              status 404
              error!({ message: "Job with id='#{id}' not found" }, 404)
            end

            result_object ||= OptimizerWrapper::Result.get(id) || {}
            output_format = params[:format]&.to_sym || ((result_object[:configuration] && result_object[:configuration][:csv]) ? :csv : env['api.format'])

            if job&.completed? # job can still be nil if we have the solution from the dump
              APIBase.dump_vrp_dir.write([id, params[:api_key], 'solution'].join('_'), Oj.dump(result_object)) if stored_result.nil? && OptimizerWrapper.config[:dump][:solution]
              OptimizerWrapper.job_remove(params[:api_key], id)
            end

            status 200

            if output_format == :csv && (job.nil? || job.completed?) # At this step, if the job is nil then it has already been retrieved into the result store
              env['api.format'] = :csv # To override json default format
              present(OutputHelper::Result.build_csv(result_object[:result]), type: CSV)
            else
              present({
                solutions: result_object[:result],
                job: {
                  id: id,
                  status: job&.status&.to_sym || :completed, # :queued, :working, :completed, :failed
                  avancement: job&.message,
                  graph: result_object[:graph]
                },
                geojsons: OutputHelper::Result.generate_geometry(result_object)
              }, with: VrpResult)
            end
            # set nil to release memory because puma keeps the grape api endpoint object alive
            stored_result = nil # rubocop:disable Lint/UselessAssignment
            result_object = nil # rubocop:disable Lint/UselessAssignment
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
            success: {
              code: 202,
              model: VrpResult
            },
            failure: [
              { code: 404, message: 'Not Found', model: ::Api::V01::Status }
            ],
            detail: 'Kill the job. This operation may have delay, since if the job is working it will be killed during the next iteration.'
          }
          params {
            requires :id, type: String, desc: 'Job id returned by creating VRP problem.'
          }
          delete ':id' do
            id = params[:id]
            job = Resque::Plugins::Status::Hash.get(id)

            if !job || job.killed? || Resque::Plugins::Status::Hash.should_kill?(id) || job['options']['api_key'] != params[:api_key]
              status 404
              error!({ message: "Job with id='#{id}' not found" }, 404)
            else
              OptimizerWrapper.job_kill(params[:api_key], id) if job.killable?

              result_object = OptimizerWrapper::Result.get(id)

              status 202
              if result_object && !result_object.empty?
                output_format = params[:format]&.to_sym || ((result_object[:configuration] && result_object[:configuration][:csv]) ? :csv : env['api.format'])
                if output_format == :csv
                  present(OutputHelper::Result.build_csv(result_object[:result]), type: CSV)
                else
                  present({
                    solutions: result_object[:result],
                    job: {
                      id: id,
                      status: :killed,
                      avancement: job.message,
                      graph: result_object[:graph]
                    },
                    geojsons: OutputHelper::Result.generate_geometry(result_object)
                  }, with: VrpResult)
                end
              else
                present({
                  job: {
                    id: id,
                    status: :killed,
                  }
                }, with: VrpResult)
              end
              result_object = nil # rubocop:disable Lint/UselessAssignment
              OptimizerWrapper.job_remove(params[:api_key], id)
            end
          end
        end
      end
      # rubocop:enable Metrics/BlockLength
    end
  end
end
