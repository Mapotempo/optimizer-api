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
    def self.custom_distance(a, b)
      r = 6378.137
      deg2rad_lat_a = a[0] * Math::PI / 180
      deg2rad_lat_b = b[0] * Math::PI / 180
      deg2rad_lon_a = a[1] * Math::PI / 180
      deg2rad_lon_b = b[1] * Math::PI / 180
      lat_distance = deg2rad_lat_b - deg2rad_lat_a
      lon_distance = deg2rad_lon_b - deg2rad_lon_a

      intermediate = Math.sin(lat_distance / 2) * Math.sin(lat_distance / 2) + Math.cos(deg2rad_lat_a) * Math.cos(deg2rad_lat_b) *
                     Math.sin(lon_distance / 2) * Math.sin(lon_distance / 2)

      fly_distance = 1000 * r * 2 * Math.atan2(Math.sqrt(intermediate), Math.sqrt(1 - intermediate))
      # units_distance = (0..unit_sets.size - 1).any? { |index| a[3 + index] + b[3 + index] == 1 } ? 2**56 : 0
      # timewindows_distance = a[2].overlaps?(b[2]) ? 0 : 2**56
      fly_distance #+ units_distance + timewindows_distance
    end

    def self.split_clusters(services_vrps, job = nil, &block)
      all_vrps = services_vrps.collect{ |service_vrp|
        vrp = service_vrp[:vrp]
        if vrp.preprocessing_apply_hierarchical_split
          split_hierarchical(service_vrp, vrp, 5) #give right nb of days : compute it in split_hierarchical ?
        elsif vrp.preprocessing_max_split_size && vrp.vehicles.size > 1 && vrp.shipments.size == 0 && service_vrp[:problem_size] > vrp.preprocessing_max_split_size &&
        vrp.services.size > vrp.preprocessing_max_split_size && !vrp.schedule_range_indices && !vrp.schedule_range_date
          points = vrp.services.collect.with_index{ |service, index|
            service.activity.point.matrix_index = index
            [service.activity.point.location.lat, service.activity.point.location.lon]
          }

          result_cluster = clustering(vrp, 2)

          sub_first = build_partial_vrp(vrp, result_cluster[0])

          sub_second = build_partial_vrp(vrp, result_cluster[1]) if result_cluster[1]

          deeper_search = [{
            service: service_vrp[:service],
            vrp: sub_first,
            fleet_id: service_vrp[:fleet_id],
            problem_size: service_vrp[:problem_size]
          }]
          deeper_search << {
            service: service_vrp[:service],
            vrp: sub_second,
            fleet_id: service_vrp[:fleet_id],
            problem_size: service_vrp[:problem_size]
          } if sub_second
          split_clusters(deeper_search, job)
        else
          {
            service: service_vrp[:service],
            vrp: vrp,
            fleet_id: service_vrp[:fleet_id],
            problem_size: service_vrp[:problem_size]
          }
        end
      }.flatten
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def self.clustering(vrp, n)
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

      result = clusterer.clusters.collect{ |cluster|
        cluster.data_items.collect{ |i|
          vector[i[0]][0]
        }
      }
      puts "Split #{vrp.services.size} into #{result[0].size} & #{result[1] ? result[1].size : 0}"
      result
    end

    def self.build_partial_vrp(vrp, cluster_services)
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      services = vrp.services.select{ |service| cluster_services.include?(service.id) }.compact
      points_ids = services.map{ |s| s.activity.point.id }.uniq.compact
      sub_vrp.services = services
      sub_vrp.points = (vrp.points.select{ |p| points_ids.include? p.id } + vrp.vehicles.collect{ |vehicle| [vehicle.start_point, vehicle.end_point] }.flatten ).compact.uniq
      sub_vrp
    end

    def self.split_hierarchical(service_vrp, vrp, nb_days) # donner nombre jours, nb véhicules...
      nb_clusters = vrp.vehicles.collect{ |vehicle| vehicle.sequence_timewindows && vehicle.sequence_timewindows.size || 7 }.inject(:+)

      # splits using hierarchical tree method
      # nb jours dépenden nb jours dispo pour chaque véhicule. Il faut donner bon véhicule (avec ses tws notamment) à chaque ss-pb.

      # total_qties = vrp.services.collect{ |service| service[:quantities].collect{ |qte| qte[:value] } }.flatten.sum
      # weight_limit = (total_qties / nb_clusters).ceil

      if vrp.services.all?{ |service| service[:activity] }

        cumulated_duration = vrp.services.collect{ |service| service[:activity][:duration] * service[:visits_number] }.sum

        graph = {}
        branches = {} # key will be the leaf of the branch

        # one node per point
        vrp.points.each_with_index{ |point, index|
          # computed_qties = 0
          point_duration = 0
          related_services = vrp.services.select{ |service| service[:activity][:point_id] == point[:id] }
          related_services.each{ |service|
            point_duration += service[:activity][:duration]
            # if service[:quantities]
            #   service[:quantities].each{ |unit|
            #     computed_qties += unit[:value]
            #   }
            # end
          }

          next if related_services.empty?
          # if computed_qties > 0 || vrp.services.any?{ |service| service[:activity][:point_id] == point[:id] } && vrp.services.none?{ |service| service[:activity][:point_id] == point[:id] && service[:quantities] && service[:quantities].none?{ |qte| qte[:value] > 0 } }
          graph[index] = {
            points: [point[:id]],
            # weight: computed_qties
            duration: point_duration
          }
          branches[index] = {
            nodes: [index]
          }
        }

        duration_limit = [cumulated_duration / nb_clusters, graph.collect{ |node, data| data[:duration] + 1 }.max].max

        node_counter = graph.size + 1
        nodes_to_see = graph.keys

        while nodes_to_see.size > nb_clusters
          # hierarchical tree logic
          merging_values = {}

          (0..nodes_to_see.size - 2).each{ |n|
            node = nodes_to_see[n]
            (n + 1..nodes_to_see.size - 1).each{ |o|
              other_node = nodes_to_see[o]
              avg = 0.0
              nb_values = 0
              graph[node][:points].each{ |first|
                first_point = vrp.points.find{ |point| point[:id] == first }
                graph[other_node][:points].each{ |second|

                  second_point = vrp.points.find{ |point| point[:id] == second }
                  avg += custom_distance([first_point[:location][:lat], first_point[:location][:lon]], [second_point[:location][:lat], second_point[:location][:lon]])
                  nb_values += 1
                }
              }
              merging_values[avg/nb_values] = [node, other_node]
            }
          }

          fusion_index = merging_values.keys.min

          # merge nodes
          first_node, second_node = merging_values[fusion_index]
          graph[node_counter] = {
            points: graph[first_node][:points] + graph[second_node][:points],
            # weight: graph[first_node][:weight] + graph[second_node][:weight]
            duration: graph[first_node][:duration] + graph[second_node][:duration]
          }

          branches.select{ |k, value| value[:nodes].include?(first_node) }.each{ |k, value|
            value[:nodes] << node_counter
          }
          branches.select{ |k, value| value[:nodes].include?(second_node) }.each{ |k, value|
            value[:nodes] << node_counter
          }
          # branches.find{ |k, branch| branch[:nodes].include?(second_node) }[1][:nodes] << node_counter

          nodes_to_see.delete(first_node)
          nodes_to_see.delete(second_node)
          nodes_to_see << node_counter
          node_counter += 1
        end

        nodes_kept = branches.collect{ |k, data| data[:nodes].last }.uniq!
        # which nodes we keep ?
        # nodes_kept = []
        # branches.each{ |k, branch|
        #   puts "#{branch}"
        #   # nodes_kept << (branch[:nodes].select{ |node| graph[node][:computed_time] < duration_limit }.max || branch[:nodes].first)
        #   nodes_kept << branch[:nodes].select{ |node| graph[node][:duration] < duration_limit }.max
        #   puts "#{nodes_kept.last}"
        # }
        # nodes_kept.compact!
        # nodes_kept.uniq!

        # each node corresponds to a cluster
        vehicle_to_use = 0
        vehicle_list = []
        vrp.vehicles.each{ |vehicle|
          if vehicle[:timewindow]
            (0..6).each{ |day|
              tw = Marshal::load(Marshal.dump(vehicle[:timewindow]))
              tw[:day_index] = day
              new_vehicle = Marshal::load(Marshal.dump(vehicle))
              new_vehicle[:timewindow] = tw
              vehicle_list << new_vehicle
            }
          elsif vehicle[:sequence_timewindows]
            vehicle[:sequence_timewindows].each{ |tw|
              new_vehicle = Marshal::load(Marshal.dump(vehicle))
              new_vehicle[:sequence_timewindows] = [tw]
              vehicle_list << new_vehicle
            }
          end
        }
        sub_pbs = []
        points_seen = []
        file = File.new("service_with_tags.csv", "w+")
        file << "name,lat,lng,tags,duration \n"
        nodes_kept.each_with_index{ |node, index|
          services_list = []
          graph[node][:points].each{ |point|
            vrp.services.select{ |serv| serv[:activity][:point_id] == point }.each{ |service|
              file << "#{service[:id]},#{service[:activity][:point][:location][:lat]},#{service[:activity][:point][:location][:lon]},#{index},#{service[:activity][:duration] * service[:visits_number] } \n"
              points_seen << service[:id]
              services_list << service[:id]
            }
          }
          vrp_to_send = build_partial_vrp(vrp, services_list)
          vrp_to_send[:vehicles] = [vehicle_list[vehicle_to_use]]
          sub_pbs << {
            service: service_vrp[:service],
            vrp: vrp_to_send,
            fleet_id: service_vrp[:fleet_id],
            problem_size: service_vrp[:problem_size]
          }
          vehicle_to_use += 1
        }
        file.close

        sub_pbs
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end
  end
end
