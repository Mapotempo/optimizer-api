# Copyright © Mapotempo, 2017
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

require 'ai4r'
include Ai4r::Data
include Ai4r::Clusterers

module Interpreters
  class SplitClustering

    def initialize(vrp)
      @initial_vrp_duration = vrp.resolution_duration/vrp.vehicles.size if vrp.resolution_duration
      @initial_vrp_time_out = vrp.resolution_initial_time_out/vrp.vehicles.size if vrp.resolution_initial_time_out
      @free_vehicles = vrp.vehicles
      @used_vehicles = []
      @initial_visits = vrp.services.size
    end

    def split_clusters(services_vrps, job = nil, &block)
      all_vrps = services_vrps.collect{ |services_vrp|
        vrp = services_vrp[:vrp]

        if vrp.preprocessing_max_split_size && vrp.shipments.size == 0 && @initial_visits > vrp.preprocessing_max_split_size
          if vrp.services.size > vrp.preprocessing_max_split_size
            points = vrp.services.collect.with_index{ |service, index|
              service.activity.point.matrix_index = index
              [service.activity.point.location.lat, service.activity.point.location.lon]
            }

            result_cluster = clustering(vrp, 2)

            sub_first = build_partial_vrp(vrp, result_cluster[0])

            sub_second = build_partial_vrp(vrp, result_cluster[1])

            deeper_search = [{
              service: services_vrp[:service],
              vrp: sub_first
            }, {
              service: services_vrp[:service],
              vrp: sub_second
            }]
            split_clusters(deeper_search, job)
          else
            sub_vrp = Marshal::load(Marshal.dump(vrp))
            sub_vrp.id = Random.new
            unassigned_size = 0

            sub_vrp.vehicles = @free_vehicles.collect{ |vehicle|
              vehicle.matrix_id = nil
              sub_vrp.rests << vrp.rests.select{ |r| vehicle.rests.map(&:id).include? r.id } if !vehicle.rests.empty?
              vehicle
            }

            sub_vrp.resolution_initial_time_out = 1000
            sub_vrp.resolution_duration = @initial_vrp_duration * sub_vrp.vehicles.size if @initial_vrp_duration

            result = OptimizerWrapper.solve([{
              service: services_vrp[:service],
              vrp: sub_vrp
            }], job)

            current_usefull_vehicle = sub_vrp.vehicles.select{ |vehicle|
              associated_route = result[:routes].find{ |route| route[:vehicle_id] == vehicle.id }
              associated_route[:activities].any?{ |activity| activity[:service_id] } if associated_route
            }

            sub_vrp.vehicles = current_usefull_vehicle
            @free_vehicles -= current_usefull_vehicle
            @used_vehicles += current_usefull_vehicle

            sub_vrp.resolution_duration = @initial_vrp_duration * sub_vrp.vehicles.size if @initial_vrp_duration
            sub_vrp.resolution_initial_time_out = @initial_vrp_time_out * sub_vrp.vehicles.size if @initial_vrp_time_out
            {
              service: services_vrp[:service],
              vrp: sub_vrp
            }
          end
        else
          {
            service: services_vrp[:service],
            vrp: vrp
          }
        end
      }.flatten
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def clustering(vrp, n)
      vector = vrp.services.collect{ |service|
        [service.id, service.activity.point.location.lat, service.activity.point.location.lon]
      }
      data_set = DataSet.new(data_items: vector.size.times.collect{ |i| [i] })
      c = KMeans.new
      c.set_parameters(max_iterations: 100)
      c.centroid_function = lambda do |data_sets|
        data_sets.collect{ |data_set|
          data_set.data_items.min_by{ |i|
            data_set.data_items.sum{ |j|
              c.distance_function.call(i, j)**2
            }
          }
        }
      end

      c.distance_function = lambda do |a, b|
        a = a[0]
        b = b[0]
        Math.sqrt((vector[a][1] - vector[b][1])**2 + (vector[a][2] - vector[b][2])**2)
      end

      clusterer = c.build(data_set, n)

      result = clusterer.clusters.collect { |cluster|
        cluster.data_items.collect{ |i|
          vector[i[0]][0]
        }
      }
      puts "Split #{vrp.services.size} into #{result[0].size} & #{result[1].size}"
      result
    end

    def build_partial_vrp(vrp, cluster_services)
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      services = vrp.services.select{ |service| cluster_services.include?(service.id) }.compact
      points_ids = services.map{ |s| s.activity.point.id }.uniq.compact
      sub_vrp.services = services
      points = sub_vrp.services.collect.with_index{ |service, i|
        service.activity.point.matrix_index = i
        [service.activity.point.location.lat, service.activity.point.location.lon]
      }
      sub_vrp.points = (vrp.points.select{ |p| points_ids.include? p.id } + vrp.vehicles.collect{ |vehicle| [vehicle.start_point, vehicle.end_point] }.flatten ).compact.uniq
      sub_vrp
    end
  end
end
