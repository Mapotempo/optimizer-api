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

require './lib/routers/router_wrapper.rb'


module OptimizerWrapper
  REDIS = Redis.new

  def self.config
    @@c
  end

  def self.router
    @router ||= Routers::RouterWrapper.new(ActiveSupport::Cache::NullStore.new, ActiveSupport::Cache::NullStore.new, config[:router][:api_key])
  end

  def self.wrapper_vrp(services, vrp)
    service = services[:vrp].find{ |s|
      inapplicable = config[:services][s].inapplicable_solve?(vrp)
      if inapplicable.empty?
        puts "Select service #{s}"
        true
      else
        puts "Skip inapplicable #{s}: #{inapplicable.join(', ')}"
        false
      end
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

      if (vrp.matrix_time.nil? && vrp.need_matrix_time?) || (vrp.matrix_distance.nil? && vrp.need_matrix_distance?)
        at(nil, [vrp.need_matrix_time?, vrp.need_matrix_distance?].count{ |m| m }.to_s, "compute matrix")
        mode = vrp.vehicles[0].router_mode.to_sym || :car
        d = [:time, :distance]
        dimensions = [d.delete(vrp.vehicles[0].router_dimension.to_sym)]
        dimensions << d[0] if vrp.send('matrix_' + d[0].to_s).nil? && vrp.send('need_matrix_' + d[0].to_s + '?')
        points = vrp.points.each_with_index.collect{ |point, index|
          point.matrix_index = index
          [point.location.lat, point.location.lon]
        }
        # set vrp.matrix_time and vrp.matrix_distance depending of dimensions order
        matrices = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][mode], mode, dimensions, points, points, speed_multiplicator: vrp.vehicles[0].speed_multiplier || 1)
        vrp.matrix_time = matrices[dimensions.index(:time)] if dimensions.index(:time)
        vrp.matrix_distance = matrices[dimensions.index(:distance)] if dimensions.index(:distance)
      end

      OptimizerWrapper.config[:services][service].job = self.uuid
      result = OptimizerWrapper.config[:services][service].solve(vrp) { |avancement, total|
        at(avancement, total || 1, "solve iterations #{avancement}" + (total ? "/#{total}" : ''))
      }
      if result.class.name == 'Hash' # result.is_a?(Hash) not working
        (result[:total_time] = result[:routes].collect{ |r| r[:end_time] - r[:start_time] }.reduce(:+)) if result[:total_time]
        result[:total_distance] = result[:routes].collect{ |r|
          previous = nil
          r[:activities].collect{ |a|
            point_id = a[:point_id] ? a[:point_id] : a[:service_id] ? vrp.services.find{ |s|
              s.id == a[:service_id]
            }.activity.point_id : a[:pickup_shipment_id] ? vrp.shipments.find{ |s|
              s.id == a[:pickup_shipment_id]
            }.pickup.point_id : a[:delivery_shipment_id] ? vrp.shipments.find{ |s|
              s.id == a[:delivery_shipment_id]
            }.delivery.point_id : nil
            vrp.points.find{ |p| p.id == point_id }.matrix_index if point_id
          }.compact.inject(0){ |sum, item|
            sum = sum + vrp.matrix_distance[previous][item] if (previous)
            previous = item
            sum
          }
        }.reduce(:+)
        Result.set(self.uuid, result)
      elsif result.class.name == 'String' # result.is_a?(String) not working
        raise RuntimeError.new(result)
      else
        raise RuntimeError.new('No solution provided')
      end
    rescue Exception => e
      puts e
      puts e.backtrace
      raise
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
