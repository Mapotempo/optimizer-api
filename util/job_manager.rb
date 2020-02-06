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

      log "Starting job... #{options['checksum']}"

      job_started_at = Time.now
      key_print = options['api_key'].rpartition('-')[0]
      key_print = options['api_key'][0..3] if key_print.empty?
      Raven.tags_context(key_print: key_print, vrp_checksum: options['checksum'])
      Raven.user_context(api_key: options['api_key']) # Filtered in sentry if user_context

      # Get the vrp
      services_vrps =
        Marshal.load(Base64.decode64(self.options['services_vrps'])) # rubocop:disable Security/MarshalLoad
      log "Vrp size: #{services_vrps.size} Key print: #{key_print} Names: #{services_vrps.map{ |sv| sv[:vrp].name }}"
      Raven.extra_context(
        vrps: services_vrps.map{ |sv|
          {
            name: sv[:vrp].name,
            vehicles: sv[:vrp].vehicles.size,
            activities: sv[:vrp].services.size,
            relations: sv[:vrp].relations.size,
          }
        },
        config: {
          max_split_size: services_vrps.first[:vrp].configuration&.preprocessing&.max_split_size,
          partitions: services_vrps.first[:vrp].configuration&.preprocessing&.partitions&.size,
          schedule: !services_vrps.first[:vrp].configuration&.schedule&.range_indices.nil?,
          random_seed: services_vrps.first[:vrp].configuration&.resolution&.random_seed,
        }
      )

      # The worker is about to launch the optimization, we can delete the vrp from the job
      self.options['services_vrps'] = nil

      # Re-set the job on Redis
      value = JSON.parse(OptimizerWrapper::REDIS.get(Resque::Plugins::Status::Hash.status_key(self.uuid)))
      value['name'] = nil
      value['options']['services_vrps'] = nil
      # Expire is defined resque config
      OptimizerWrapper::REDIS.set(Resque::Plugins::Status::Hash.status_key(self.uuid),
                                  Resque::Plugins::Status::Hash.encode(value))

      ask_restitution_csv = services_vrps.any?{ |s_v| s_v[:vrp].configuration.restitution.csv }
      ask_restitution_geojson = services_vrps.flat_map{ |s_v| s_v[:vrp].configuration.restitution.geometry }.uniq
      final_solutions =
        OptimizerWrapper.define_main_process(
          services_vrps, self.uuid
        ) { |wrapper, avancement, total, message, cost, time, solution|
          if [wrapper, avancement, total, message, cost, time, solution].compact.empty? # if all nil
            tick # call tick in case job is killed
            next # if not go back to optimization
          end
          at(
            avancement, total || 1,
            (message || '') +
              (avancement ? " #{avancement}" : '') +
              (avancement && total ? "/#{total}" : '') +
              (cost ? " cost: #{cost}" : '')
          )

          log "avancement: #{message} #{avancement}"
          if avancement && cost
            p = Result.get(self.uuid) || { graph: [] }
            p[:graph] ||= []
            p[:configuration] = {
              csv: ask_restitution_csv,
              geometry: ask_restitution_geojson
            }
            p[:graph] << { iteration: avancement, cost: cost, time: time }
            p[:result] = [solution.vrp_result].flatten if solution
            begin
              Result.set(self.uuid, p)
            rescue Redis::BaseError => e
              log "Could not set an intermediate result due to the following error: #{e}", level: :warning
            end
          end
        }
      log "Ending job... #{options['checksum']}"
      best_solution = final_solutions.min(&:count_assigned_services)
      # WARNING: the following log is used for server performance comparison automation
      log "Elapsed time: #{(Time.now - job_started_at).round(2)}s Vrp size: #{services_vrps.size} "\
          "Key print: #{key_print} Names: #{services_vrps.map{ |sv| sv[:vrp].name }} "\
          "Checksum: #{options['checksum']} "\
          "Random seed: #{services_vrps.first[:vrp].configuration&.resolution&.random_seed} "\
          "Assigned services: #{best_solution&.count_assigned_services} "\
          "Unassigned services: #{best_solution&.count_unassigned_services} "\
          "Used routes: #{best_solution&.count_used_routes}"

      # Add values related to the current solve status
      p = Result.get(self.uuid) || {}
      p[:configuration] = {
        csv: ask_restitution_csv,
        geometry: ask_restitution_geojson
      }
      p[:result] = final_solutions.vrp_result
      if services_vrps.size == 1 && p && p[:result].any? && p[:graph]&.any?
        p[:result].first[:iterations] = p[:graph].last[:iteration]
        p[:result].first[:elapsed] = p[:graph].last[:time]
      end
      begin
        Result.set(self.uuid, p)
      rescue Redis::BaseError => e
        log "Couldn't set the last result due to the following error (trying again in 2 minutes): #{e}", level: :warning
        sleep 120 # Try setting the result one last time without rescue since this is the last result
        Result.set(self.uuid, p)
      end
    end

    def on_failure(e)
      log "#{e.class.name}: #{e}\n\t#{e.backtrace.join("\n\t")}", level: :fatal
      Raven.capture_exception(e)
      raise e
    end

    def on_killed
      # Process is already killed nothing to do
      log 'Job killed'
    end
  end

  class Result
    def self.time_spent(value)
      @time_spent ||= 0
      @time_spent += value
    end

    def self.set(key, value)
      OptimizerWrapper::REDIS.set key, value.to_json
      OptimizerWrapper::REDIS.expire key, (
        ENV['REDIS_RESULT_TTL_DAYS'].blank? ? 7.days : ENV['REDIS_RESULT_TTL_DAYS'].to_i.days
      )
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
