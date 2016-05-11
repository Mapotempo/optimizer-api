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
require 'i18n'
require 'resque'
require 'resque-status'
require 'redis'
require 'json'

module OptimizerWrapper
  REDIS = Redis.new

  def self.config
    @@c
  end

  def self.wrapper_vrp(services, vrp)
    service = services[:vrp].find{ |s|
      config[:services][s].solve?(vrp)
    }
    if !service
      raise UnsupportedProblemError
    else
      job_id = Job.create(service: service, vrp: Base64.encode64(Marshal::dump(vrp)))
      Result.get(job_id) || job_id
    end
  end

  class Job
    include Resque::Plugins::Status

    def perform
      service, vrp = options['service'].to_sym, Marshal.load(Base64.decode64(options['vrp']))
      result = OptimizerWrapper.config[:services][service].solve(vrp) { |avancement, total|
        at(avancement, total, "#{avancement}/#{total}")
      }
      if result.class.name == 'Hash' # result.is_a?(Hash) not working
        Result.set(self.uuid, result)
      elsif result.class.name == 'String' # result.is_a?(String) not working
        raise RuntimeError.new(result)
      else
        raise RuntimeError.new('No solution provided')
      end
    end
  end

  class UnsupportedProblemError < StandardError
  end

  class Result
    def self.set(key, value)
      OptimizerWrapper::REDIS.set(key, value.to_json)
    end

    def self.get(key)
      result = OptimizerWrapper::REDIS.get(key)
      if result
        OptimizerWrapper::REDIS.set(key, nil)
        JSON.parse(result)
      end
    end
  end
end
