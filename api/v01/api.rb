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
require 'http_accept_language'

require './api/v01/vrp'

module Api
  module V01
    class Api < Grape::API
      use HttpAcceptLanguage::Middleware

      helpers do
        def set_locale
          I18n.locale = env.http_accept_language.compatible_language_from(I18n.available_locales.map(&:to_s)) || I18n.default_locale
        end

        def redis_count
          OptimizerWrapper.config[:redis_count]
        end

        def count_time
          @count_time ||= Time.now.utc
        end

        def count_key(operation)
          @count_key ||= [
            [:optimizer, operation, count_time.to_s[0..9]],
            [:key, params[:api_key]],
            [:ip, (env['action_dispatch.remote_ip'] || request.ip).to_s],
            [:asset, params[:asset]]
          ].map{ |a| a.join(':') }.join('_')
        end

        def count(operation)
          return unless redis_count
          @count_val = redis_count.hgetall(count_key(operation)).symbolize_keys
          if @count_val.empty?
            @count_val = {hits: 0, transactions: 0}
            redis_count.mapped_hmset @count_key, @count_val
            redis_count.expire @count_key, 100.days
          end
        end

        def count_incr(operation, options)
          return unless redis_count
          count operation unless @count_val
          incr = {hits: @count_val[:hits].to_i + 1}
          incr[:transactions] = @count_val[:transactions].to_i + options[:transactions] if options[:transactions]
          redis_count.mapped_hmset @count_key, incr
        end
      end

      before do
        if !params || !::OptimizerWrapper.access(true).keys.include?(params[:api_key])
          error!('401 Unauthorized', 401)
        end
        set_locale
      end

      rescue_from StandardError, backtrace: ENV['APP_ENV'] != 'production' do |e|
        @error = e

        STDERR.puts "\n\n#{e.class} (#{e.message}):\n    " + e.backtrace.join("\n    ") + "\n\n" if ENV['APP_ENV'] != 'test'

        response = { error: e.class, message: e.message }
        if e.is_a?(RangeError) ||
           e.is_a?(RouterError) ||
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
        else
          rack_response(format_message(response, e.backtrace), 500)
        end
      end

      mount Vrp
    end
  end
end
