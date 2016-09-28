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
require 'thread'

require './lib/routers/router_wrapper.rb'

require 'ai4r'
include Ai4r::Data
require './lib/clusterers/complete_linkage_max_distance.rb'
include Ai4r::Clusterers
require 'sim_annealing'

module OptimizerWrapper
  REDIS = Redis.new

  def self.config
    @@c
  end

  def self.router
    @router ||= Routers::RouterWrapper.new(ActiveSupport::Cache::NullStore.new, ActiveSupport::Cache::NullStore.new, config[:router][:api_key])
  end

  def self.wrapper_vrp(api_key, services, vrp)
    service = services[:services][:vrp].find{ |s|
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
      if config[:solve_synchronously] || config[:services][service].solve_synchronous?(vrp)
        solve(service, vrp)
      else
        job_id = Job.enqueue_to(services[:queue], Job, service: service, vrp: Base64.encode64(Marshal::dump(vrp)))
        JobList.add(api_key, job_id)
        Result.get(job_id) || job_id
      end
    end
  end

  def self.solve(service, vrp, &block)
    if vrp.services.empty? && vrp.shipments.empty?
      {
        costs: 0,
        routes: []
      }
    else
      vrp_need_matrix = {
        time: vrp.need_matrix_time?,
        distance: vrp.need_matrix_distance?
      }

      need_matrix = vrp.vehicles.collect{ |vehicle|
        [vehicle, vehicle.dimensions]
      }.select{ |vehicle, dimensions|
        dimensions.find{ |dimension|
          vrp_need_matrix[dimension] && (vehicle.matrix.nil? || vehicle.matrix.send(dimension).nil?) && vehicle.send('need_matrix_' + dimension.to_s + '?')
        }
      }

      if need_matrix.size > 0
        points = vrp.points.each_with_index.collect{ |point, index|
          point.matrix_index = index
          [point.location.lat, point.location.lon]
        }

        uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
          [vehicle.router_mode.to_sym, dimensions, vehicle.speed_multiplier]
        }.uniq

        i = 0
        uniq_need_matrix = Hash[uniq_need_matrix.collect{ |mode, dimensions, speed_multiplicator|
          raise UnsupportedRouterModeError unless OptimizerWrapper.config[:router][mode]
          block.call(nil, i += 1, uniq_need_matrix.size, 'compute matrix') if block
          # set vrp.matrix_time and vrp.matrix_distance depending of dimensions order
          matrices = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][mode], mode, dimensions, points, points, speed_multiplicator: speed_multiplicator || 1)
          m = Models::Matrix.create({
            time: (matrices[dimensions.index(:time)] if dimensions.index(:time)),
            distance: (matrices[dimensions.index(:distance)] if dimensions.index(:distance))
          })
          vrp.matrices += [m]
          [[mode, dimensions, speed_multiplicator], m]
        }]

        uniq_need_matrix = need_matrix.collect{ |vehicle, dimensions|
          vehicle.matrix = uniq_need_matrix[[vehicle.router_mode.to_sym, dimensions, vehicle.speed_multiplier]]
        }
      end

      File.write('test/fixtures/' + ENV['DUMP_VRP'].gsub(/[^a-z0-9\-]+/i, '_') + '.dump', Base64.encode64(Marshal::dump(vrp))) if ENV['DUMP_VRP']

      block.call(nil, nil, nil, 'process clustering') if block && vrp.preprocessing_cluster_threshold
      cluster(vrp, vrp.preprocessing_cluster_threshold) do |vrp|
        block.call(nil, 0, nil, 'run optimization') if block
        time_start = Time.now
        result = OptimizerWrapper.config[:services][service].solve(vrp) { |wrapper, avancement, total, cost, solution|
          block.call(wrapper, avancement, total, 'run optimization, iterations', cost, (Time.now - time_start) * 1000, solution.class.name == 'Hash' && parse_result(vrp, solution)) if block
        }

        if result.class.name == 'Hash' # result.is_a?(Hash) not working
          result[:elapsed] = (Time.now - time_start) * 1000 # Can be overridden in wrappers
          parse_result(vrp, result)
        elsif result.class.name == 'String' # result.is_a?(String) not working
          raise RuntimeError.new(result)
        else
          raise RuntimeError.new('No solution provided')
        end
      end
    end
  rescue Exception => e
    puts e
    puts e.backtrace
    raise
  end

  def self.job_list(api_key)
    jobs = (JobList.get(api_key) || []).collect{ |e|
      Resque::Plugins::Status::Hash.get(e)
    }
  end

  def self.job_kill(api_key, id)
    Result.remove(api_key, id)
    Resque::Plugins::Status::Hash.kill(id)
  end

  def self.job_remove(api_key, id)
    Result.remove(api_key, id)
  end

  private

  def self.parse_result(vrp, result)
    result[:routes].each{ |r|
      if r[:end_time] && r[:start_time]
        r[:total_time] = r[:end_time] - r[:start_time]
      end
      v = vrp.vehicles.find{ |v| v.id == r[:vehicle_id] }
      if v.matrix.distance
        previous = nil
        r[:total_distance] = r[:activities].sum{ |a|
          point_id = a[:point_id] ? a[:point_id] : a[:service_id] ? vrp.services.find{ |s|
            s.id == a[:service_id]
          }.activity.point_id : a[:pickup_shipment_id] ? vrp.shipments.find{ |s|
            s.id == a[:pickup_shipment_id]
          }.pickup.point_id : a[:delivery_shipment_id] ? vrp.shipments.find{ |s|
            s.id == a[:delivery_shipment_id]
          }.delivery.point_id : nil
          if point_id
            point = vrp.points.find{ |p| p.id == point_id }.matrix_index
            if previous && point
              a[:travel_distance] = v.matrix.distance[previous][point]
            end
          end
          previous = point
          a[:travel_distance] || 0
        }
      end
    }

    if result[:routes].all?{ |r| r[:total_time] }
      result[:total_time] = result[:routes].collect{ |r|
        r[:total_time]
      }.reduce(:+)
    end

    if result[:routes].all?{ |r| r[:total_distance] }
      result[:total_distance] = result[:routes].collect{ |r|
        r[:total_distance]
      }.reduce(:+)
    end

    result
  end

  def self.cluster(vrp, cluster_threshold)
    if vrp.matrices.size > 0 && vrp.shipments.size == 0 && cluster_threshold
      original_services = Array.new(vrp.services.size){ |i| vrp.services[i].clone }
      zip_key = zip_cluster(vrp, cluster_threshold)
    end
    result = yield(vrp)
    if vrp.matrices.size > 0 && vrp.shipments.size == 0 && cluster_threshold
      vrp.services = original_services
      unzip_cluster(result, zip_key, vrp)
    else
      result
    end
  end

  def self.zip_cluster(vrp, cluster_threshold)
    return nil unless vrp.services.length > 0 && vrp.vehicles.length == 1

    data_set = DataSet.new(data_items: (0..(vrp.services.length - 1)).collect{ |i| [i] })
    c = CompleteLinkageMaxDistance.new
    matrix = vrp.matrices[0][vrp.vehicles[0].router_dimension.to_sym] # FIXME not all vehicle have the same dimension
    c.distance_function = lambda do |a, b|
      aa = vrp.services[a[0]]
      bb = vrp.services[b[0]]
      (aa.activity.timewindows.collect{ |t| [t[:start], t[:end]]} == bb.activity.timewindows.collect{ |t| [t[:start], t[:end]]} && 
        aa.activity.duration == 0 && bb.activity.duration == 0 &&
        aa.quantities.size == 0 && bb.quantities.size == 0 &&
        aa.skills == bb.skills) ?
        matrix[aa.activity.point.matrix_index][bb.activity.point.matrix_index] :
        Float::INFINITY
    end
    clusterer = c.build(data_set, cluster_threshold)

    new_size = clusterer.clusters.size

    # Build replacement list
    new_services = Array.new(new_size)
    clusterer.clusters.each_with_index do |cluster, i|
      oi = cluster.data_items[0][0]
      new_services[i] = vrp.services[oi]
    end

    # Fill new vrp
    vrp.services = new_services

    clusterer.clusters
  end

  def self.unzip_cluster(result, zip_key, original_vrp)
    return result unless zip_key

    activities = []
    activities << result[:unassigned]
    activities << result[:routes][0][:activities] if result[:routes].size > 0
    activities = activities.collect{ |activities|
      if activities
        new_activities = []
        activities.each_with_index{ |activity, idx_a|
          idx_s = original_vrp.services.index{ |s| s.id == activity[:service_id] }
          idx_z = zip_key.index{ |z| z.data_items.flatten.include? idx_s }
          if idx_z && idx_z < zip_key.length && zip_key[idx_z].data_items.length > 1
            sub = zip_key[idx_z].data_items.collect{ |i| i[0] }
            matrix = original_vrp.matrices[0][original_vrp.vehicles[0].router_dimension.to_sym]

            # Cluster start: Last non rest-without-location stop before current cluster
            start = new_activities.reverse.find{ |r| r[:service_id] }
            start_index = start ? original_vrp.services.index{ |s| s.id == start[:service_id] } : 0

            j = 0
            while(activities[idx_a + j] && !activities[idx_a + j][:service_id]) do # Next non rest-without-location stop after current cluster
              j += 1
            end

            if activities[idx_a + j] && activities[idx_a + j][:service_id]
              stop_index = original_vrp.services.index{ |s| s.id == activities[idx_a + j][:service_id] }
            else
              stop_index = original_vrp.services.length - 1
            end

            sub_size = sub.length
            min_order = if sub_size <= 5
              # Test all permutations inside cluster
              sub.permutation.collect{ |p|
                last = start_index
                sum = p.sum { |s|
                  a, last = last, s
                  matrix[original_vrp.services[a].activity.point.matrix_index][original_vrp.services[s].activity.point.matrix_index]
                } + matrix[original_vrp.services[p[-1]].activity.point.matrix_index][original_vrp.services[stop_index].activity.point.matrix_index]
                [sum, p]
              }.min_by{ |a| a[0] }[1]
            else
              # Run local optimization inside cluster
              sim_annealing = SimAnnealing::SimAnnealingVrp.new
              sim_annealing.start = start_index
              sim_annealing.stop = stop_index
              sim_annealing.matrix = matrix
              sim_annealing.vrp = original_vrp
              fact = (1..[sub_size, 8].min).reduce(1, :*) # Yes, compute factorial
              initial_order = [start_index] + sub + [stop_index]
              sub_size += 2
              r = sim_annealing.search(initial_order, fact, 100000.0, 0.999)[:vector]
              r = r.collect{ |i| initial_order[i] }
              index = r.index(start_index)
              if r[(index + 1) % sub_size] != stop_index && r[(index - 1) % sub_size] != stop_index
                # Not stop and start following
                sub
              else
                if r[(index + 1) % sub_size] == stop_index
                  r.reverse!
                  index = sub_size - 1 - index
                end
                r = index == 0 ? r : r[index..-1] + r[0..index - 1] # shift to replace start at beginning
                r[1..-2] # remove start and stop from cluster
              end
            end
            last_index = start_index
            new_activities += min_order.collect{ |index|
              a = {
                point_id: (original_vrp.services[index].activity.point_id if original_vrp.services[index].id),
                travel_distance: original_vrp.matrices[0].distance ? original_vrp.matrices[0].distance[original_vrp.services[last_index].activity.point.matrix_index][original_vrp.services[index].activity.point.matrix_index] : 0, # TODO: from matrix_distance
                # travel_start_time: 0, # TODO: from matrix_time
                # arrival_time: 0, # TODO: from matrix_time
                # departure_time: 0, # TODO: from matrix_time
                service_id: original_vrp.services[index].id
              }.delete_if { |k, v| !v }
              last_index = index
              a
            }
          else
            new_activities << activity
          end
        }.flatten
        new_activities
      end
    }
    result[:unassigned] = activities[0]
    result[:routes][0][:activities] = activities[1] if activities.size > 1
    result
  end

  class Job
    include Resque::Plugins::Status

    def perform
      service, vrp = options['service'].to_sym, Marshal.load(Base64.decode64(options['vrp']))
      OptimizerWrapper.config[:services][service].job = self.uuid

      result = OptimizerWrapper.solve(service, vrp) { |wrapper, avancement, total, message, cost, time, solution|
        @killed && wrapper.kill && return
        @wrapper = wrapper
        at(avancement, total || 1, (message || '') + (avancement ? " #{avancement}" : '') + (avancement && total ? "/#{total}" : '') + (cost ? " cost: #{cost}" : ''))
        if avancement && cost
          p = Result.get(self.uuid) || {'graph' => []}
          p['graph'] << {iteration: avancement, cost: cost, time: time}
          Result.set(self.uuid, p)
        end
        if solution
          p = Result.get(self.uuid) || {}
          p['result'] = solution
          Result.set(self.uuid, p)
        end
      }

      p = Result.get(self.uuid) || {}
      p['result'] = result
      Result.set(self.uuid, p)
    end

    def on_killed
      @wrapper && @wrapper.kill
      @killed = true
    end
  end

  class UnsupportedProblemError < StandardError; end
  class UnsupportedRouterModeError < StandardError; end

  class Result
    def self.set(key, value)
      OptimizerWrapper::REDIS.set(key, value.to_json)
    end

    def self.get(key)
      result = OptimizerWrapper::REDIS.get(key)
      if result
        JSON.parse(result)
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

module SimAnnealing
  class SimAnnealingVrp < SimAnnealing
    attr_accessor :start, :stop, :matrix, :vrp

    def euc_2d(c1, c2)
      if (c1 == start || c1 == stop) && (c2 == start || c2 == stop)
        0
      else
        matrix[vrp.services[c1].activity.point.matrix_index][vrp.services[c2].activity.point.matrix_index]
      end
    end
  end
end
