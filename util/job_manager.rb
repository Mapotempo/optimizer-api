# Copyright © Mapotempo, 2018
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
require 'i18n'
require 'resque'
require 'resque-status'
require 'redis'
require 'json'
require 'thread'

module OptimizerWrapper
  class Job
    include Resque::Plugins::Status

    def perform
      tick('Starting job') # Important to kill job before any code

      services_vrps = Marshal.load(Base64.decode64(options['services_vrps']))
      ask_restitution_csv = services_vrps.any?{ |s_v| s_v[:vrp].restitution_csv }
      result = OptimizerWrapper.define_process(services_vrps, self.uuid) { |wrapper, avancement, total, message, cost, time, solution|
        @killed && wrapper.kill && return
        @wrapper = wrapper
        at(avancement, total || 1, (message || '') + (avancement ? " #{avancement}" : '') + (avancement && total ? "/#{total}" : '') + (cost ? " cost: #{cost}" : ''))
        if avancement && cost
          p = Result.get(self.uuid) || { 'graph' => [] }
          p['graph'] = [] if !p.key?('graph')
          p['csv'] = true if ask_restitution_csv
          p['graph'] << { iteration: avancement, cost: cost, time: time }
          p['result'] = solution if solution
          Result.set(self.uuid, p)
        end
      }

      # Add values related to the current solve status
      p = Result.get(self.uuid) || {}
      p['csv'] = true if ask_restitution_csv
      p['result'] = [result].flatten #TODO define process must only return an array (Need tests edit)
      if services_vrps.size == 1 && p['graph'] && !p['graph'].empty?
        p['result'].first['iterations'] = p['graph'].last['iteration']
        p['result'].first['elapsed'] = p['graph'].last['time']
      end
      Result.set(self.uuid, p)
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def on_killed
      @wrapper && @wrapper.kill
      @killed = true
    end
  end

  class ProblemError < StandardError
    attr_reader :data

    def initialize(data = [])
      @data = data
    end
  end
  class DiscordantProblemError < ProblemError; end
  class UnsupportedProblemError < ProblemError; end
  class UnsupportedRouterModeError < StandardError; end
  class RouterWrapperError < StandardError; end
  class SchedulingHeuristicError < StandardError; end

  class Result
    def self.set(key, value)
      OptimizerWrapper::REDIS.set(key, value.to_json)
    end

    def self.get(key)
      result = OptimizerWrapper::REDIS.get(key)
      if result
        JSON.parse(result.force_encoding(Encoding::UTF_8)) # On some env string is encoded as ASCII
      end
    end

    def self.exist(key)
      OptimizerWrapper::REDIS.exists(key)
    end

    def self.remove(api_key, key)
      OptimizerWrapper::REDIS.del(key)
      OptimizerWrapper::REDIS.lrem(api_key, 0, key)
    end
  end

  class JobList
    def self.add(api_key, job_id)
      OptimizerWrapper::REDIS.rpush(api_key, job_id)
    end

    def self.get(api_key)
      OptimizerWrapper::REDIS.lrange(api_key, 0, -1)
    end
  end
end
