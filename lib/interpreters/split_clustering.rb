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
      split_results = []
      all_vrps = services_vrps.collect{ |service_vrp|
        vrp = service_vrp[:vrp]
        empties_or_fills = (vrp.services.select{ |service| service.quantities.any?{ |quantity| quantity.fill }} +
                            vrp.services.select{ |service| service.quantities.any?{ |quantity| quantity.empty }}).uniq
        if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
          generate_split_vrps(service_vrp, job, block)
        elsif vrp.preprocessing_max_split_size && vrp.vehicles.size > 1 && vrp.shipments.size == 0 && vrp.services.size - empties_or_fills.size > vrp.preprocessing_max_split_size &&
             !vrp.schedule_range_indices && !vrp.schedule_range_date
          split_results << split_solve(service_vrp)
          nil
        else
          {
            service: service_vrp[:service],
            vrp: vrp
          }
        end
      }.compact
      two_stages = services_vrps[0][:vrp].preprocessing_partitions.size == 2
      output_clusters(all_vrps, services_vrps[0][:vrp][:vehicles], two_stages) if services_vrps[0][:vrp][:debug_output_clusters_in_csv]
      [all_vrps, split_results]
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def self.generate_split_vrps(service_vrp, job = nil, block)
      vrp = service_vrp[:vrp]
      if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
        current_vrps = [service_vrp]
        vrp.preprocessing_partitions.each{ |partition|
          cut_symbol = partition[:metric] == :duration || partition[:metric] == :visits || vrp.units.any?{ |unit| unit.id.to_sym == partition[:metric] } ? partition[:metric] : :duration

          case partition[:method]
          when 'balanced_kmeans'
            generated_vrps = current_vrps.collect{ |s_v|
              current_vrp = s_v[:vrp]
              current_vrp.vehicles = list_vehicles(current_vrp.vehicles) if partition[:entity] == 'work_day'
              split_balanced_kmeans(s_v, current_vrp, current_vrp.vehicles.size, cut_symbol, partition[:entity])
            }
            current_vrps = generated_vrps.flatten
          when 'hierarchical_tree'
            generated_vrps = current_vrps.collect{ |s_v|
              current_vrp = s_v[:vrp]
              current_vrp.vehicles = list_vehicles([current_vrp.vehicles.first]) if partition[:entity] == 'work_day'
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
      end
    end

    def self.merge_results(results)
      results.flatten!
      {
        solvers: results.flat_map{ |r| r && r[:solvers] }.compact,
        cost: results.map{ |r| r && r[:cost] }.compact.reduce(&:+),
        routes: results.flat_map{ |r| r && r[:routes] }.compact,
        unassigned: results.flat_map{ |r| r && r[:unassigned] }.compact,
        elapsed: results.map{ |r| r && r[:elapsed] || 0 }.reduce(&:+),
        total_time: results.map{ |r| r && r[:total_travel_time] }.compact.reduce(&:+),
        total_value: results.map{ |r| r && r[:total_travel_value] }.compact.reduce(&:+),
        total_distance: results.map{ |r| r && r[:total_distance] }.compact.reduce(&:+)
      }
    end

    def self.split_solve(service_vrp, job = nil, &block)
      vrp = service_vrp[:vrp]
      problem_size = vrp.services.size + vrp.shipments.size
      empties_or_fills = (vrp.services.select{ |service| service.quantities.any?{ |quantity| quantity.fill }} +
                          vrp.services.select{ |service| service.quantities.any?{ |quantity| quantity.empty }}).uniq

      vrp.services -= empties_or_fills

      points = vrp.services.collect.with_index{ |service, index|
        service.activity.point.matrix_index = index
        [service.activity.point.location.lat, service.activity.point.location.lon]
      }
      available_vehicles = vrp.vehicles.collect{ |vehicle| vehicle.id }
      result_cluster = clustering(vrp, 2)

      sub_first = build_partial_vrp(vrp, result_cluster[0], available_vehicles)
      sub_first.resolution_duration = vrp.resolution_duration / problem_size * (sub_first.services.size + sub_first.shipments.size)
      sub_first.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size *
                                              (sub_first.services.size + sub_first.shipments.size) if vrp.resolution_minimum_duration || vrp.resolution_initial_time_out
      sub_first.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (0.05 + sub_first.services.size.to_f / vrp.services.size)).to_i
      sub_first.preprocessing_split_number -= vrp.preprocessing_split_number / 2.0
      # Reintroduce fills and empties
      sub_first.services += empties_or_fills

      first_side = [{
        service: service_vrp[:service],
        vrp: sub_first
      }]
      first_result = merge_results([OptimizerWrapper::define_process(first_side, job)])
      remove_poor_routes(sub_first, first_result)
      empties_or_fills -= remove_used_empties_and_refills(sub_first, first_result)
      available_vehicles.delete_if{ |id| first_result[:routes].collect{ |route| route[:vehicle_id] }.include?(id) }

      sub_second = build_partial_vrp(vrp, result_cluster[1], available_vehicles) if result_cluster[1]
      if sub_second
        sub_second.resolution_duration = (vrp.resolution_duration / problem_size) * (sub_second.services.size + sub_second.shipments.size)
        sub_second.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size *
                                                 (sub_second.services.size + sub_second.shipments.size) if (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out)
        sub_second.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (0.05 + sub_second.services.size.to_f / vrp.services.size)).to_i
        sub_second.preprocessing_split_number = vrp.preprocessing_split_number
        # Reintroduce fills and empties
        sub_second.services += empties_or_fills

        second_side = [{
          service: service_vrp[:service],
          vrp: sub_second
        }]
        second_result = merge_results([OptimizerWrapper::define_process(second_side, job)])
        remove_poor_routes(sub_second, second_result)
        available_vehicles.delete_if{ |id| first_result[:routes].collect{ |route| route[:vehicle_id] }.include?(id) }

        merge_results([first_result, second_result])
      end
    end

    def self.remove_used_empties_and_refills(vrp, result)
      result[:routes].collect{ |route|
        current_service = nil
        current_point = nil
        route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity|
          current_service = vrp.services.find{ |service| service[:id] == activity[:service_id] }
          current_service if current_service && current_service.quantities.any?{ |quantity| quantity.fill } || current_service.quantities.any?{ |quantity| quantity.empty }
        }
      }.flatten
    end

    def self.remove_poor_routes(vrp, result)
      if result
        remove_empty_routes(result)
        remove_poorly_populated_routes(vrp, result)
      end
    end

    def self.remove_empty_routes(result)
      result[:routes].delete_if{ |route| route[:activities].none?{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] }}
    end

    def self.remove_poorly_populated_routes(vrp, result)
      result[:routes].delete_if{ |route|
        vehicle = vrp.vehicles.find{ |vehicle| vehicle.id == route[:vehicle_id] }
        loads = route[:activities].last[:detail][:quantities]
        load_flag = vehicle.capacities.empty? || vehicle.capacities.all?{ |capacity|
          current_load = loads.find{ |unit_load| unit_load[:unit] == capacity.unit.id }
          current_load[:value] / capacity.limit < 0.2 if capacity.limit && current_load && capacity.limit > 0
        }
        time_flag = vehicle.timewindow.end.nil? || vehicle.timewindow.start.nil? ||
        (route[:activities].last[:begin_time] - route[:activities].first[:begin_time]) < 0.3 * (vehicle.timewindow.end - vehicle.timewindow.start).to_f
        result[:unassigned] += route[:activities].select{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] } if load_flag && time_flag
        load_flag && time_flag
      }
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

    def self.build_partial_vrp(vrp, cluster_services, available_vehicles = nil)
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      services = vrp.services.select{ |service| cluster_services.include?(service.id) }.compact
      points_ids = services.map{ |s| s.activity.point.id }.uniq.compact
      sub_vrp.services = services
      sub_vrp.vehicles.delete_if{ |vehicle| !available_vehicles.include?(vehicle.id) } if available_vehicles
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
        data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, nil, nil]
      }

      if max_cut_metrics
        [data_items, cumulated_metrics, max_cut_metrics]
      else
        [data_items, cumulated_metrics]
      end
    end

    def self.create_sub_pbs(service_vrp, vrp, clusters, clusterer = nil)
      sub_pbs = []
      points_seen = []
      clusters.delete([])
      clusters.each{ |cluster|
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
        sub_pbs << {
          service: service_vrp[:service],
          vrp: vrp_to_send
        }
      }
      sub_pbs
    end

    def self.kmeans_process(centroids, c_max_iterations, max_iterations, nb_clusters, data_items, unit_symbols, cut_symbol, metric_limit, vrp, incompatibility_set = nil)
      c = BalancedKmeans.new
      c.max_iterations = c_max_iterations
      c.centroid_indices = centroids if centroids

      biggest_cluster_size = 0
      clusters = []
      iteration = 0
      while biggest_cluster_size < nb_clusters && iteration < max_iterations
        c.build(DataSet.new(data_items: data_items), unit_symbols, nb_clusters, cut_symbol, metric_limit, vrp.debug_output_kmeans_centroids, incompatibility_set)
        c.clusters.delete([])
        if c.clusters.size > biggest_cluster_size
          biggest_cluster_size = c.clusters.size
          clusters = c.clusters
          centroids = c.centroid_indices
        end
        iteration += 1
      end
      clusters
    end

    def self.list_vehicles(vehicles)
      vehicle_list = []
      vehicles.each{ |vehicle|
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
      vehicle_list
    end

    def self.assign_vehicle_to_clusters(vehicles, points, clusters, entity = '', kmeans = true)
      vehicle_for_cluster = {}
      if entity == 'work_day' || entity == 'vehicle' && vehicles.collect{ |vehicle| vehicle[:sequence_timewindows] && vehicle[:sequence_timewindows].size }.compact.uniq.size > 1
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

    def self.affect_vehicle(sub_pbs, vehicle_for_cluster, clusters)
      vec = []
      sub_pbs.each_with_index{ |spb, i|
        if clusters[i].data_items.compact.any?{ |data| data[5] }
          spb[:vrp][:vehicles] = [vehicle_for_cluster.find{ |day, vehicle| clusters[i].data_items.compact.all?{ |data| data[5].nil? || ([vehicle[:sequence_timewindows].first[:day_index]] & data[5]).size > 0 }}[1]]
          vehicle_for_cluster.delete_if{ |day, vehicle| vehicle[:sequence_timewindows].first[:day_index] == spb[:vrp][:vehicles][0][:sequence_timewindows][0][:day_index] }
        else
          spb[:vrp][:vehicles] = [vehicle_for_cluster[i]]
        end
      }
      sub_pbs
    end

    def self.split_balanced_kmeans(service_vrp, vrp, nb_clusters, cut_symbol = :duration, entity = "")
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] }
        cumulated_metrics = {}
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }

        data_items, cumulated_metrics = collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics)
        centroids = []
        limits = []
        if entity == 'vehicle' && vrp.vehicles.all?{ |vehicle| vehicle[:sequence_timewindows] } && vrp.vehicles.collect{ |vehicle| vehicle[:sequence_timewindows].size }.uniq.size != 1
          vrp.vehicles.sort_by!{ |vehicle| vehicle[:sequence_timewindows].size }
          share = vrp.vehicles.collect{ |vehicle| vehicle[:sequence_timewindows].size }.sum if entity == 'vehicle'
          vrp.vehicles.each_with_index{ |vehicle, index|
            centroids << index
            data_items[index][6] = vehicle[:sequence_timewindows].size
            limits << cumulated_metrics[cut_symbol].to_f / (share.to_f / data_items[index][6].to_f)
          }
        elsif entity == 'work_day' && vrp.vehicles.all?{ |vehicle| vehicle[:sequence_timewindows] }
          data_items.each{ |data|
            data[5] = vrp.services.find{ |service| service.activity.point_id == data[2] }.activity.timewindows.collect{ |timewindow| timewindow[:day_index] }.uniq
          }
          data_items.sort_by!{ |data| data[5].size }.reverse!
          centroids_skills = data_items.collect{ |data| data[5] }.uniq
          skills_index = 0
          vrp.vehicles.each_with_index{ |vehicle, index|
            skills_index += 1 if vrp.vehicles.size - centroids_skills.size < index
            centroids += [data_items.index(data_items.find{ |data| data[5] == centroids_skills[skills_index] && !centroids.include?(data_items.index(data)) })]
          }
          limits = cumulated_metrics[cut_symbol] / nb_clusters
        else
          limits = cumulated_metrics[cut_symbol] / nb_clusters
        end
        centroids = vrp[:preprocessing_kmeans_centroids] if vrp[:preprocessing_kmeans_centroids] && entity != 'work_day'

        clusters = kmeans_process(centroids, 200, 30, nb_clusters, data_items, unit_symbols, cut_symbol, limits, vrp)
        clusters.delete_if{ |cluster| cluster.data_items.empty? }
        vehicle_for_cluster = assign_vehicle_to_clusters(vrp.vehicles, vrp.points, clusters, entity)
        adjust_clusters(clusters, limits, cut_symbol, centroids, data_items) if entity == 'work_day'
        sub_pbs = create_sub_pbs(service_vrp, vrp, clusters)
        affect_vehicle(sub_pbs, vehicle_for_cluster, clusters)
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end

    # Adjust cluster if they are disparate - only called when entity == 'work_day'
    def self.adjust_clusters(clusters, limits, cut_symbol, centroids, data_items)
      clusters.each_with_index{ |cluster, index|
        centroids[index] = data_items[centroids[index]]
      }
      clusters.each_with_index{ |cluster, index|
        count = 0
        cluster.data_items.sort_by!{ |data| Helper::flying_distance(data, centroids[index]) }
        cluster.data_items.each{ |data|
          count += data[3][cut_symbol]
          if count > limits && !centroids.include?(data)
            c = find_cluster(clusters, cluster, cut_symbol, data, limits)
            if c
              cluster.data_items.delete(data)
              c.data_items.insert(c.data_items.size, data)
              count -= data[3][cut_symbol]
            end
          end
        }
      }
    end

    # Find the nearest cluster to add data_to_insert - because the other is full
    def self.find_cluster(clusters, original_cluster, cut_symbol, data_to_insert, limit)
      c = nil
      dist = 2 ** 32
      clusters.each{ |cluster|
        next if cluster == original_cluster
        cluster.data_items.each{ |data|
          if dist > Helper::flying_distance(data, data_to_insert) && cluster.data_items.collect{ |data| data[3][cut_symbol] }.sum < limit &&
             cluster.data_items.all?{ |d| data_to_insert[5].nil? || d[5] && (data_to_insert[5] & d[5]).size >= d[5].size }
            dist = Helper::flying_distance(data, data_to_insert)
            c = cluster
          end
        }
      }

      c
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
        create_sub_pbs(service_vrp, vrp, clusters, clusterer)
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end
  end
end
