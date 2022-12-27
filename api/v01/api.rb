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

require './api/v01/vrp'

class QuotaExceededError < StandardError
  attr_reader :data

  def initialize(msg, data)
    @data = data
    super(msg)
  end
end

module Api
  module V01
    class Api < Grape::API
      use HttpAcceptLanguage::Middleware

      helpers do
        def set_locale
          I18n.locale =
            if env.http_accept_language.header.nil? || env.http_accept_language.header == :unspecified
              # we keep previous behaviour
              :legacy
            else
              env.http_accept_language.compatible_language_from(I18n.available_locales.map(&:to_s)) || I18n.default_locale
            end
        end

        def redis_count
          OptimizerWrapper.config[:redis_count]
        end

        def count_time
          @count_time ||= Time.now.utc
        end

        def count_base_key(operation, period = :daily)
          [
            count_base_key_no_key(operation, period),
            [:key, params[:api_key]]
          ].map{ |a| a.join(':') }.join('_')
        end

        def count_base_key_no_key(operation, period = :daily)
          count_date =
            if period == :daily
              count_time.to_s[0..9]
            elsif period == :monthly
              count_time.to_s[0..6]
            elsif period == :yearly
              count_time.to_s[0..3]
            end
          [:optimizer, operation, count_date].compact
        end

        def count_key(operation)
          @count_key ||= count_base_key(operation) + '_' + [
            [:ip, (env['action_dispatch.remote_ip'] || request.ip).to_s],
            [:asset, params[:asset]]
          ].map{ |a| a.join(':') }.join('_')
        end

        def count(operation, raise_if_exceed = true, request_size = 1)
          return unless redis_count

          @count_val = redis_count.hgetall(count_key(operation)).symbolize_keys
          if @count_val.empty?
            @count_val = {hits: 0, transactions: 0}
            redis_count.mapped_hmset @count_key, @count_val
            redis_count.expire @count_key, 100.days
          end

          return unless raise_if_exceed

          APIBase.profile(params[:api_key])[:quotas]&.each do |quota|
            op = quota[:operation]
            next unless op.nil? || op == operation

            quota.slice(:daily, :monthly, :yearly).each do |k, v|
              count = redis_count.get(count_base_key(op, k)).to_i
              raise QuotaExceededError.new("Too many #{k} requests", limit: v, remaining: v - count, reset: k) if v && count + request_size > v
            end
          end
        end

        def count_incr(operation, options)
          return unless redis_count

          count operation, false unless @count_val
          incr = {hits: @count_val[:hits].to_i + 1}
          incr[:transactions] = @count_val[:transactions].to_i + options[:transactions] if options[:transactions]
          redis_count.mapped_hmset @count_key, incr

          return unless options[:transactions]

          APIBase.profile(params[:api_key])[:quotas]&.each do |quota|
            op = quota[:operation]
            next unless op.nil? || op == operation

            quota.slice(:daily, :monthly, :yearly).each do |k, _v|
              redis_count.incrby count_base_key(op, k), options[:transactions]
              redis_count.expire count_base_key(op, k), 366.days
            end
          end
        end

        def split_key(key)
          json = {}
          key.split('_').each do |values|
            rs = values.split(':')

            case rs[0]
            when "optimizer"
              json['service'] = rs[0]
              json['endpoint'] = rs[1]
              json['date'] = rs[2]
            when "key"
              json['key'] = rs[1]
            when "ip"
              json['ip'] = rs[1]
            when "asset"
              json['asset'] = rs[1]
            end
          end

          json
        end

        def count_current_jobs(api_key)
          OptimizerWrapper.config[:redis_resque].keys("resque:status*").count { |key|
            JSON.parse(OptimizerWrapper.config[:redis_resque].get(key))['status'] == 'queued' &&
              JSON.parse(OptimizerWrapper.config[:redis_resque].get(key))['options']['api_key'] == api_key
          }
        end

        def metric(key)
          hkey = split_key(key)

          if redis_count.type(key) == 'hash'
            hredis = redis_count.hgetall(key)
            hredis['count_current_jobs'] = count_current_jobs(hkey['key']).to_s

            {
              count_asset: hkey['asset'],
              count_date: hkey['date'],
              count_endpoint: hkey['endpoint'],
              count_hits: hredis['hits'],
              count_ip: hkey['ip'],
              count_key: hkey['key'],
              count_service: hkey['service'],
              count_transactions: hredis['transactions'],
              count_current_jobs: hredis['count_current_jobs'],
            }
          else
            log "Metrics: #{key} is not a hash" && {}
          end
        end
      end

      before do
        if !params || !::OptimizerWrapper.access(true).key?(params[:api_key])
          error!('Unauthorized', 401)
        elsif OptimizerWrapper.access[params[:api_key]][:expire_at]&.to_date&.send(:<, Date.today)
          error!("Subscription expired. Please contact support (#{::OptimizerWrapper.config[:product_support_email]}) or sales (#{::OptimizerWrapper.config[:product_sales_email]}) to extend your access period.", 402)
        end
        set_locale
      end

      rescue_from StandardError, backtrace: ENV['APP_ENV'] != 'production' do |e|
        @error = e

        warn "\n\n#{e.class} (#{e.message}):\n    " + e.backtrace.join("\n    ") + "\n\n" if ENV['APP_ENV'] != 'test'

        response = { error: e.class, message: e.message }
        if e.is_a?(RangeError) ||
           e.is_a?(RouterError) ||
           e.is_a?(ActiveHash::IdError) ||
           e.is_a?(ActiveHash::RecordNotFound) ||
           e.is_a?(Grape::Exceptions::InvalidMessageBody) ||
           e.is_a?(Grape::Exceptions::ValidationErrors) ||
           e.is_a?(OptimizerWrapper::DiscordantProblemError) ||
           e.is_a?(OptimizerWrapper::UnsupportedProblemError) ||
           e.is_a?(OptimizerWrapper::UnsupportedRouterModeError)
          response[:message] += ' ' + e.data.map { |service| service.join(', ') }.join(' | ') if e.is_a?(OptimizerWrapper::UnsupportedProblemError)
          rack_response(format_message(response, e.backtrace), 400)
        elsif e.is_a?(Grape::Exceptions::MethodNotAllowed)
          rack_response(format_message(response, e.backtrace), 405)
        elsif e.is_a?(QuotaExceededError)
          headers = { 'Content-Type' => content_type,
                      'X-RateLimit-Limit' => e.data[:limit],
                      'X-RateLimit-Remaining' => e.data[:remaining],
                      'X-RateLimit-Reset' => if e.data[:reset] == :daily
                                               count_time.to_date.next_day
                                             elsif e.data[:reset] == :monthly
                                               count_time.to_date.next_month
                                             elsif e.data[:reset] == :yearly
                                               count_time.to_date.next_year
                                             end.to_time.to_i }
          rack_response(format_message(response, nil), 429, headers)
        else
          Raven.capture_exception(e)
          rack_response(format_message(response, e.backtrace), 500)
        end
      end

      ##
      # Use to export prometheus metrics
      resource :metrics do
        desc 'Return Prometheus metrics', {}
        get do
          error!('Unauthorized', 401) unless OptimizerWrapper.access[params[:api_key]][:metrics] == true

          status 200
          present(
            redis_count.keys("*#{count_base_key_no_key('*').join(':')}*").flat_map{ |key| metric(key) }, with: Metrics
          )
        end
      end

      mount Vrp
    end
  end
end
