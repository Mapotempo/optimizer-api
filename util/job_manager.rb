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
# frozen_string_literal: true

require './util/error.rb'
require './util/config.rb'

module OptimizerWrapper
  class Job
    include Resque::Plugins::Status

    @@current_job_id = nil

    def self.current_job_id
      @@current_job_id
    end

    def self.current_job_id=(id)
      @@current_job_id = id
    end

    def perform
      Job.current_job_id = self.uuid
      tick('Starting job') # Important to kill job before any code

      services_vrps = Marshal.load(Base64.decode64(self.options['services_vrps'])) # Get the vrp
      self.options['services_vrps'] = nil # The worker is about to launch the optimization, we can delete the vrp from the job

      # Re-set the job on Redis
      value = JSON.parse(OptimizerWrapper::REDIS.get(Resque::Plugins::Status::Hash.status_key(self.uuid)))
      value['name'] = nil
      value['options']['services_vrps'] = nil
      OptimizerWrapper::REDIS.set Resque::Plugins::Status::Hash.status_key(self.uuid), Resque::Plugins::Status::Hash.encode(value) # Expire is defined resque config

      ask_restitution_csv = services_vrps.any?{ |s_v| s_v[:vrp].restitution_csv }
      ask_restitution_geojson = services_vrps.flat_map{ |s_v| s_v[:vrp].restitution_geometry }.uniq
      result = OptimizerWrapper.define_main_process(services_vrps, self.uuid) { |wrapper, avancement, total, message, cost, time, solution|
        if [wrapper, avancement, total, message, cost, time, solution].compact.empty? # if all nil
          tick # call tick in case job is killed
          next # if not go back to optimization
        end
        at(avancement, total || 1, (message || '') + (avancement ? " #{avancement}" : '') + ((avancement && total) ? "/#{total}" : '') + (cost ? " cost: #{cost}" : ''))
        @killed && wrapper.kill && return # Stops the worker if the job is killed
        @wrapper = wrapper
        log "avancement: #{message} #{avancement}"
        if avancement && cost
          p = Result.get(self.uuid) || { graph: [] }
          p[:graph] ||= []
          p[:configuration] = {
            csv: ask_restitution_csv,
            geometry: ask_restitution_geojson
          }
          p[:graph] << { iteration: avancement, cost: cost, time: time }
          p[:result] = solution if solution
          Result.set(self.uuid, p)
        end
      }

      # Add values related to the current solve status
      p = Result.get(self.uuid) || {}
      p[:configuration] = {
        csv: ask_restitution_csv,
        geometry: ask_restitution_geojson
      }
      p[:result] = result
      if services_vrps.size == 1 && p && p[:result].any? && p[:graph]&.any?
        p[:result].first[:iterations] = p[:graph].last[:iteration]
        p[:result].first[:elapsed] = p[:graph].last[:time]
      end
      Result.set(self.uuid, p)
    rescue Resque::Plugins::Status::Killed, JobKilledError
      log 'Job Killed'
      tick('Job Killed')
      nil
    rescue StandardError => e
      log "#{e.class.name}: #{e}\n\t#{e.backtrace.join("\n\t")}", level: :fatal
      raise
    end

    def on_killed
      @wrapper&.kill
      @killed = true
    end
  end

  class Result
    def self.time_spent(value)
      @time_spent ||= 0
      @time_spent += value
    end

    def self.set(key, value)
      OptimizerWrapper::REDIS.set key, value.to_json
      OptimizerWrapper::REDIS.expire key, 7.days
    end

    def self.get(key)
      result = OptimizerWrapper::REDIS.get(key)
      return unless result

      JSON.parse(result.force_encoding(Encoding::UTF_8), symbolize_names: true)
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
