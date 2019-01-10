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

require './lib/helper.rb'
require './lib/interpreters/periodic_visits.rb'
require './lib/clusterers/average_tree_linkage.rb'
require './lib/clusterers/balanced_kmeans.rb'

module Interpreters
  class SplitClustering
    def self.custom_distance(a, b)
      fly_distance = Helper::flying_distance(a, b)
      # units_distance = (0..unit_sets.size - 1).any? { |index| a[3 + index] + b[3 + index] == 1 } ? 2**56 : 0
      # timewindows_distance = a[2].overlaps?(b[2]) ? 0 : 2**56
      fly_distance #+ units_distance + timewindows_distance
    end

    def self.output_clusters(all_vrps, vehicles, two_stages)
      file = File.new('generated_clusters.csv', 'w+')
      file << "name,lat,lng,tags,start depot,end depot\n"
      if two_stages
        # clustering for each vehicle and each day
        vehicles.each_with_index{ |vehicle, v_index|
          all_vrps.select{ |service| service[:vrp][:vehicles][0][:id] == vehicle[:id] }.each_with_index{ |sub_pb, s_index|
            sub_pb[:vrp][:services].each{ |service|
              file << "#{service[:id]},#{service[:activity][:point][:location][:lat]},#{service[:activity][:point][:location][:lon]},v#{v_index}_pb#{s_index},#{sub_pb[:vrp][:vehicles].first[:start_point_id]},#{sub_pb[:vrp][:vehicles].first[:end_point_id]}\n"
            }
          }
        }
      else
        # clustering for each vehicle
        all_vrps.each_with_index{ |sub_pb, s_index|
          sub_pb[:vrp][:services].each{ |service|
            file << "#{service[:id]},#{service[:activity][:point][:location][:lat]},#{service[:activity][:point][:location][:lon]},#{s_index},#{sub_pb[:vrp][:vehicles].first[:start_point_id]},#{sub_pb[:vrp][:vehicles].first[:end_point_id]}\n"
          }
        }
      end
      file.close
    end

    def self.split_clusters(services_vrps, job = nil, &block)
      all_vrps = services_vrps.collect{ |service_vrp|
        vrp = service_vrp[:vrp]
        if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
          current_vrps = [service_vrp]
          vrp.preprocessing_partitions.each{ |partition|
            cut_symbol = partition[:metric] == :duration || partition[:metric] == :visits || vrp.units.any?{ |unit| unit.id.to_sym == partition[:metric] } ? partition[:metric] : :duration

            case partition[:method]
            when 'balanced_kmeans'
              generated_vrps = current_vrps.collect{ |s_v|
                current_vrp = s_v[:vrp]
                current_vrp.vehicles = list_vehicles(current_vrp.vehicles.first) if partition[:entity] == 'work_day'
                split_balanced_kmeans(s_v, current_vrp, current_vrp.vehicles.size, cut_symbol, partition[:entity])
              }
              current_vrps = generated_vrps.flatten
            when 'hierarchical_tree'
              generated_vrps = current_vrps.collect{ |s_v|
                current_vrp = s_v[:vrp]
                current_vrp.vehicles = list_vehicles(current_vrp.vehicles.first) if partition[:entity] == 'work_day'
                split_hierarchical(s_v, current_vrp, current_vrp.vehicles.size, cut_symbol, partition[:entity])
              }
              current_vrps = generated_vrps.flatten
            else
              raise OptimizerWrapper::UnsupportedProblemError.new("Unknown partition method #{vrp.preprocessing_partition_method}")
            end
          }
          current_vrps
        elsif vrp.preprocessing_partition_method
          cut_symbol = vrp.preprocessing_partition_metric == :duration ||
          vrp.preprocessing_partition_metric == :visits || vrp.units.any?{ |unit| unit.id.to_sym == vrp.preprocessing_partition_metric } ? vrp.preprocessing_partition_metric : :duration
          case vrp.preprocessing_partition_method
          when 'balanced_kmeans'
           split_balanced_kmeans(service_vrp, vrp, vrp.vehicles.size, cut_symbol)
          when 'hierarchical_tree'
            split_hierarchical(service_vrp, vrp, vrp.vehicles.size, cut_symbol)
          else
            raise OptimizerWrapper::UnsupportedProblemError.new("Unknown partition method #{vrp.preprocessing_partition_method}")
          end

        elsif vrp.preprocessing_max_split_size && vrp.vehicles.size > 1 && vrp.shipments.size == 0 && service_vrp[:problem_size] > vrp.preprocessing_max_split_size &&
        vrp.services.size > vrp.preprocessing_max_split_size && !vrp.schedule_range_indices && !vrp.schedule_range_date
          problem_size = vrp.services.size + vrp.shipments.size

          points = vrp.services.collect.with_index{ |service, index|
            service.activity.point.matrix_index = index
            [service.activity.point.location.lat, service.activity.point.location.lon]
          }

          result_cluster = clustering(vrp, 2)

          sub_first = build_partial_vrp(vrp, result_cluster[0])
          sub_first.resolution_duration = vrp.resolution_duration / problem_size * (sub_first.services.size + sub_first.shipments.size)
          sub_first.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size * (sub_first.services.size + sub_first.shipments.size) if vrp.resolution_minimum_duration || vrp.resolution_initial_time_out

          sub_second = build_partial_vrp(vrp, result_cluster[1]) if result_cluster[1]
          sub_second.resolution_duration = (vrp.resolution_duration / problem_size) * (sub_second.services.size + sub_second.shipments.size) if sub_second
          sub_first.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size * (sub_first.services.size + sub_first.shipments.size) if sub_second && (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out)

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

      two_stages = services_vrps[0][:vrp].preprocessing_partitions.size == 2
      output_clusters(all_vrps, services_vrps[0][:vrp][:vehicles], two_stages) if services_vrps[0][:vrp][:debug_output_clusters_in_csv]

      all_vrps
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

    def self.count_metric(graph, parent, symbol)
      value = parent.nil? ? 0 : graph[parent][:unit_metrics][symbol]
      value + (parent.nil? ? 0 : (count_metric(graph, graph[parent][:left], symbol) + count_metric(graph, graph[parent][:right], symbol)))
    end

    def self.collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics, max_cut_metrics = nil)
      data_items = []

      vrp.points.each{ |point|
        unit_quantities = {}
        unit_symbols.each{ |unit| unit_quantities[unit] = 0 }
        related_services = vrp.services.select{ |service| service[:activity][:point_id] == point[:id] }
        related_services.each{ |service|
          unit_quantities[:visits] += 1
          cumulated_metrics[:visits] += 1
          unit_quantities[:duration] += service[:activity][:duration] * service[:visits_number]
          cumulated_metrics[:duration] += service[:activity][:duration] * service[:visits_number]

          service.quantities.each{ |quantity|
            unit_quantities[quantity.unit_id.to_sym] += quantity.value * service[:visits_number]
            cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * service[:visits_number]
          }
        }
        if max_cut_metrics
          unit_symbols.each{ |unit|
            max_cut_metrics[unit] = [unit_quantities[unit], max_cut_metrics[unit]].max
          }
        end

        next if related_services.empty?
        data_items << [point.location.lat, point.location.lon, point.id, unit_quantities]
      }

      if max_cut_metrics
        [data_items, cumulated_metrics, max_cut_metrics]
      else
        [data_items, cumulated_metrics]
      end
    end

    def self.create_sub_pbs(service_vrp, vrp, clusters, vehicle_for_cluster, clusterer = nil)
      sub_pbs = []
      points_seen = []
      clusters.delete([])
      clusters.each_with_index{ |cluster, index|
        services_list = []
        if clusterer
          cluster.each{ |node|
            point_id = clusterer.graph[node][:point]
            vrp.services.select{ |serv| serv[:activity][:point_id] == point_id }.each{ |service|
              points_seen << service[:id]
              services_list << service[:id]
            }
          }
        else
          cluster.data_items.each{ |data_item|
            point_id = data_item[2]
            vrp.services.select{ |serv| serv[:activity][:point_id] == point_id }.each{ |service|
              points_seen << service[:id]
              services_list << service[:id]
            }
          }
        end
        vrp_to_send = build_partial_vrp(vrp, services_list)
        vrp_to_send[:vehicles] = [vehicle_for_cluster[index]]
        sub_pbs << {
          service: service_vrp[:service],
          vrp: vrp_to_send,
          fleet_id: service_vrp[:fleet_id],
          problem_size: service_vrp[:problem_size]
        }
      }
      sub_pbs
    end

    def self.kmeans_process(c_max_iterations, max_iterations, nb_clusters, data_items, unit_symbols, cut_symbol, metric_limit, vrp)
      c = BalancedKmeans.new
      c.max_iterations = c_max_iterations
      c.centroid_indices = vrp[:preprocessing_kmeans_centroids] if vrp[:preprocessing_kmeans_centroids] && entity != 'work_day'

      biggest_cluster_size = 0
      clusters = []
      iteration = 0
      while biggest_cluster_size < nb_clusters && iteration < max_iterations
        c.build(DataSet.new(data_items: data_items), unit_symbols, nb_clusters, cut_symbol, metric_limit, vrp.debug_output_kmeans_centroids)
        c.clusters.delete([])
        if c.clusters.size > biggest_cluster_size
          biggest_cluster_size = c.clusters.size
          clusters = c.clusters
        end
        iteration += 1
      end

      clusters
    end

    def self.list_vehicles(vehicle)
      vehicle_list = []
      if vehicle[:timewindow]
        (0..6).each{ |day|
          tw = Marshal::load(Marshal.dump(vehicle[:timewindow]))
          tw[:day_index] = day
          new_vehicle = Marshal::load(Marshal.dump(vehicle))
          new_vehicle[:timewindow] = tw
          vehicle_list << new_vehicle
        }
      elsif vehicle[:sequence_timewindows]
        vehicle[:sequence_timewindows].each_with_index{ |tw, index|
          new_vehicle = Marshal::load(Marshal.dump(vehicle))
          new_vehicle[:sequence_timewindows] = [tw]
          vehicle_list << new_vehicle
        }
      end
      vehicle_list
    end

    def self.assign_vehicle_to_clusters(vehicles, points, clusters, entity = '', kmeans = true)
      vehicle_for_cluster = {}
      if entity == 'work_day'
        vehicles.each_with_index{ |vehicle, i|
          vehicle_for_cluster[i] = vehicle
        }
      else
        available_clusters = []
        clusters.each_with_index{ |cluster, i|
          available_clusters << {
            id: i,
            cluster: kmeans ? cluster.data_items : cluster
          }
        }

        vehicles.each{ |vehicle|
          values = []
          if !available_clusters.empty?
            available_clusters.each{ |cluster_data|
              cluster = cluster_data[:cluster]
              value = nil

              # if all vehicles do not have the same number of depots, this can not be the best way
              start_lat = points.find{ |p| p[:id] == vehicle.start_point_id }[:location][:lat] if vehicle.start_point_id
              start_lon = points.find{ |p| p[:id] == vehicle.start_point_id }[:location][:lon] if vehicle.start_point_id
              end_lat = points.find{ |p| p[:id] == vehicle.end_point_id }[:location][:lat] if vehicle.end_point_id
              end_lon = points.find{ |p| p[:id] == vehicle.end_point_id }[:location][:lon] if vehicle.end_point_id

              cluster.each{ |point|
                s_lat = point[0]
                s_lon = point[1]

                sum_distance = Helper.flying_distance([start_lat, start_lon], [s_lat, s_lon]) + Helper.flying_distance([end_lat, end_lon], [s_lat, s_lon])
                value = sum_distance if value.nil?
                value = [value, sum_distance].min
              }

              values << value
            }
            smallest_value_index = values.find_index(values.min)
            vehicle_for_cluster[available_clusters[smallest_value_index][:id]] = vehicle
            available_clusters.delete(available_clusters[smallest_value_index])
          end
        }
      end

      vehicle_for_cluster
    end

    def self.remove_from_upper(graph, node, symbol, value_to_remove)
      if graph.key?(node)
        graph[node][:unit_metrics][symbol] -= value_to_remove
        remove_from_upper(graph, graph[node][:parent], symbol, value_to_remove)
      end
    end

    def self.tree_leafs(graph, node)
      if node.nil?
        [nil]
      elsif (graph[node][:level]).zero?
         [node]
       else
         [tree_leafs(graph, graph[node][:left]), tree_leafs(graph, graph[node][:right])]
       end
    end

    def self.tree_leafs_delete(graph, node)
      returned = if node.nil?
        []
      elsif (graph[node][:level]).zero?
        [node]
      else
        [tree_leafs(graph, graph[node][:left]), tree_leafs(graph, graph[node][:right])]
      end
      graph.delete(node)
      returned
    end

    def self.split_balanced_kmeans(service_vrp, vrp, nb_clusters, cut_symbol = :duration, entity = "")
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] }
        cumulated_metrics = {}
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }

        data_items, cumulated_metrics = collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics)

        clusters = kmeans_process(200, 30, nb_clusters, data_items, unit_symbols, cut_symbol, cumulated_metrics[cut_symbol] / nb_clusters, vrp)
        clusters.delete_if{ |cluster| cluster.data_items.empty? }
        vehicle_for_cluster = assign_vehicle_to_clusters(vrp.vehicles, vrp.points, clusters, entity)
        create_sub_pbs(service_vrp, vrp, clusters, vehicle_for_cluster)
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end

    def self.split_hierarchical(service_vrp, vrp, nb_clusters, cut_symbol = :duration, entity = "")
      # splits using hierarchical tree method
      if vrp.services.all?{ |service| service[:activity] }
        max_cut_metrics = {}
        cumulated_metrics = {}

        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }
        unit_symbols.map{ |unit| max_cut_metrics[unit] = 0 }

        data_items, cumulated_metrics, max_cut_metrics = collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics, max_cut_metrics)

        custom_distance = lambda do |a, b|
          custom_distance(a, b)
        end
        c = AverageTreeLinkage.new
        c.distance_function = custom_distance
        start_timer = Time.now
        clusterer = c.build(DataSet.new(data_items: data_items), unit_symbols)
        end_timer = Time.now
        puts "Timer #{end_timer - start_timer}"

        metric_limit = cumulated_metrics[cut_symbol] / nb_clusters
        # raise OptimizerWrapper::DiscordantProblemError.new("Unfitting cluster split metric. Maximum value is greater than average") if max_cut_metrics[cut_symbol] > metric_limit

        graph = Marshal.load(Marshal.dump(clusterer.graph.compact))

        # Tree cut process
        clusters = []
        max_level = graph.values.collect{ |value| value[:level] }.max

        # Top Down cut
        # current_level = max_level
        # while current_level >= 0
        #   graph.select{ |k, v| v[:level] == current_level }.each{ |k, v|
        #     next if v[:unit_metrics][cut_symbol] > 1.1 * metric_limit && current_level != 0
        #     clusters << tree_leafs_delete(graph, k).flatten.compact
        #   }
        #   current_level -= 1
        # end

        # Bottom Up cut
        (0..max_level).each{ |current_level|
          graph.select{ |k, v| v[:level] == current_level }.each{ |k, v|
            next if v[:unit_metrics][cut_symbol] < metric_limit && current_level != max_level
            clusters << tree_leafs(graph, k).flatten.compact
            next if current_level == max_level
            remove_from_upper(graph, graph[k][:parent], cut_symbol, v[:unit_metrics][cut_symbol])
            if k == graph[v[:parent]][:left]
              graph[v[:parent]][:left] = nil
            else
              graph[v[:parent]][:right] = nil
            end
          }
        }

        clusters.delete([])
        modified_clusters = clusters.collect{ |cluster|
          cluster.collect{ |node|
            point = vrp.points.find{ |pt| pt[:id] == clusterer.graph[node][:point] }
            [point[:location][:lat], point[:location][:lon]]
          }
        }
        vehicle_for_cluster = assign_vehicle_to_clusters(vrp.vehicles, vrp.points, modified_clusters, entity, false)
        create_sub_pbs(service_vrp, vrp, clusters, vehicle_for_cluster, clusterer)
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end
  end
end
