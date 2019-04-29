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
      fly_distance = Helper.flying_distance(a, b)
      # units_distance = (0..unit_sets.size - 1).any? { |index| a[3 + index] + b[3 + index] == 1 } ? 2**56 : 0
      # timewindows_distance = a[2].overlaps?(b[2]) ? 0 : 2**56
      fly_distance #+ units_distance + timewindows_distance
    end

    def self.output_clusters(all_service_vrps, vehicles, two_stages)
      file = File.new('generated_clusters.csv', 'w+')
      file << "name,lat,lng,tags,start depot,end depot\n"
      if two_stages
        # clustering for each vehicle and each day
        vehicles.each_with_index{ |vehicle, v_index|
          all_service_vrps.select{ |service| service[:vrp][:vehicles][0][:id] == vehicle[:id] }.each_with_index{ |sub_pb, s_index|
            sub_pb[:vrp][:services].each{ |service|
              file << "#{service[:id]},#{service[:activity][:point][:location][:lat]},#{service[:activity][:point][:location][:lon]},v#{v_index}_pb#{s_index},#{sub_pb[:vrp][:vehicles].first[:start_point_id]},#{sub_pb[:vrp][:vehicles].first[:end_point_id]}\n"
            }
          }
        }
      else
        # clustering for each vehicle
        all_service_vrps.each_with_index{ |sub_pb, s_index|
          sub_pb[:vrp][:services].each{ |service|
            file << "#{service[:id]},#{service[:activity][:point][:location][:lat]},#{service[:activity][:point][:location][:lon]},#{s_index},#{sub_pb[:vrp][:vehicles].first[:start_point_id]},#{sub_pb[:vrp][:vehicles].first[:end_point_id]}\n"
          }
        }
      end
      file.close
    end

    def self.split_clusters(services_vrps, job = nil, &block)
      split_results = []
      all_service_vrps = services_vrps.collect{ |service_vrp|
        vrp = service_vrp[:vrp]
        empties_or_fills = (vrp.services.select{ |service| service.quantities.any?(&:fill) } +
                            vrp.services.select{ |service| service.quantities.any?(&:empty) }).uniq
        depot_ids = vrp.vehicles.collect{ |vehicle| [vehicle.start_point_id, vehicle.end_point_id] }.flatten.compact.uniq
        ship_candidates = vrp.shipments.select{ |shipment|
          depot_ids.include?(shipment.pickup.point_id) || depot_ids.include?(shipment.delivery.point_id)
        }
        if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
          generate_split_vrps(service_vrp, job, block)
        elsif vrp.schedule_range_indices.nil? && vrp.schedule_range_date.nil? &&
              vrp.preprocessing_max_split_size && vrp.vehicles.size > 1 &&
              vrp.shipments.size == ship_candidates.size &&
              (ship_candidates.size + vrp.services.size - empties_or_fills.size) > vrp.preprocessing_max_split_size
          split_results << split_solve(service_vrp)
          nil
        else
          {
            service: service_vrp[:service],
            vrp: vrp,
            level: (service_vrp[:level] || 0)
          }
        end
      }.compact
      two_stages = services_vrps[0][:vrp].preprocessing_partitions.size == 2
      output_clusters(all_service_vrps, services_vrps[0][:vrp][:vehicles], two_stages) if services_vrps[0][:vrp][:debug_output_clusters_in_csv]
      [all_service_vrps, split_results]
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def self.generate_split_vrps(service_vrp, job = nil, block)
      vrp = service_vrp[:vrp]
      if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
        current_service_vrps = [service_vrp]
        vrp.preprocessing_partitions.each{ |partition|
          cut_symbol = partition[:metric] == :duration || partition[:metric] == :visits || vrp.units.any?{ |unit| unit.id.to_sym == partition[:metric] } ? partition[:metric] : :duration

          case partition[:method]
          when 'balanced_kmeans'
            generated_service_vrps = current_service_vrps.collect{ |s_v|
              current_vrp = s_v[:vrp]
              current_vrp.vehicles = list_vehicles([current_vrp.vehicles.first]) if partition[:entity] == 'work_day'
              split_balanced_kmeans(s_v, current_vrp.vehicles.size, cut_symbol, partition[:entity])
            }
            current_service_vrps = generated_service_vrps.flatten
          when 'hierarchical_tree'
            generated_service_vrps = current_service_vrps.collect{ |s_v|
              current_vrp = s_v[:vrp]
              current_vrp.vehicles = list_vehicles([current_vrp.vehicles.first]) if partition[:entity] == 'work_day'
              split_hierarchical(s_v, current_vrp, current_vrp.vehicles.size, cut_symbol, partition[:entity])
            }
            current_service_vrps = generated_service_vrps.flatten
          else
            raise OptimizerWrapper::UnsupportedProblemError.new("Unknown partition method #{vrp.preprocessing_partition_method}")
          end
        }
        current_service_vrps
      elsif vrp.preprocessing_partition_method
        cut_symbol = vrp.preprocessing_partition_metric == :duration || vrp.preprocessing_partition_metric == :visits ||
          vrp.units.any?{ |unit| unit.id.to_sym == vrp.preprocessing_partition_metric } ? vrp.preprocessing_partition_metric : :duration
        case vrp.preprocessing_partition_method
        when 'balanced_kmeans'
         split_balanced_kmeans(service_vrp, vrp.vehicles.size, cut_symbol)
        when 'hierarchical_tree'
          split_hierarchical(service_vrp, vrp.vehicles.size, cut_symbol)
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

      available_vehicles = vrp.vehicles.collect{ |vehicle| vehicle.id }

      problem_size = vrp.services.size + vrp.shipments.size
      empties_or_fills = (vrp.services.select{ |service| service.quantities.any?(&:fill) } +
                          vrp.services.select{ |service| service.quantities.any?(&:empty) }).uniq
      vrp.services -= empties_or_fills
      sub_service_vrps = split_balanced_kmeans(service_vrp, 2)
      result = []
      sub_service_vrps.each{ |sub_service_vrp|
        sub_vrp = sub_service_vrp[:vrp]
        sub_vrp.resolution_duration = vrp.resolution_duration / problem_size * (sub_vrp.services.size + sub_vrp.shipments.size)
        sub_vrp.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size *
                                                (sub_vrp.services.size + sub_vrp.shipments.size) if vrp.resolution_minimum_duration || vrp.resolution_initial_time_out
        sub_vrp.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (0.10 + sub_vrp.services.size.to_f / vrp.services.size)).to_i
        sub_vrp.preprocessing_split_number -= vrp.preprocessing_split_number / 2.0
        sub_problem = {
          vrp: sub_vrp,
          service: service_vrp[:service]
        }
        sub_vrp.services += empties_or_fills
        sub_vrp.vehicles.select!{ |vehicle| available_vehicles.include?(vehicle.id) }
        sub_result = OptimizerWrapper.define_process([sub_problem], job)
        remove_poor_routes(sub_vrp, sub_result)
        available_vehicles.delete_if{ |id| sub_result[:routes].collect{ |route| route[:vehicle_id] }.include?(id) }
        empties_or_fills -= remove_used_empties_and_refills(sub_vrp, sub_result)
        result = merge_results([result, sub_result])
      }
      result
    end

    def self.remove_used_empties_and_refills(vrp, result)
      result[:routes].collect{ |route|
        current_service = nil
        route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity|
          current_service = vrp.services.find{ |service| service[:id] == activity[:service_id] }
          current_service if current_service && current_service.quantities.any?(&:fill) || current_service.quantities.any?(&:empty)
        }
      }.flatten
    end

    def self.remove_poor_routes(vrp, result)
      if result
        remove_empty_routes(result)
        remove_poorly_populated_routes(vrp, result) if !Interpreters::Dichotomious.dichotomious_candidate({vrp: vrp, service: :ortools})
      end
    end

    def self.remove_empty_routes(result)
      result[:routes].delete_if{ |route| route[:activities].none?{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] }}
    end

    def self.remove_poorly_populated_routes(vrp, result)
      result[:routes].delete_if{ |route|
        vehicle = vrp.vehicles.find{ |current_vehicle| current_vehicle.id == route[:vehicle_id] }
        loads = route[:activities].last[:detail][:quantities]
        load_flag = vehicle.capacities.empty? || vehicle.capacities.all?{ |capacity|
          current_load = loads.find{ |unit_load| unit_load[:unit] == capacity.unit.id }
          current_load[:value] / capacity.limit < 0.2 if capacity.limit && current_load && capacity.limit > 0
        }
        time_flag = vehicle.timewindow.end.nil? || vehicle.timewindow.start.nil? ||
        (route[:activities].last[:begin_time] - route[:activities].first[:begin_time]) < 0.7 * (vehicle.timewindow.end - vehicle.timewindow.start).to_f
        result[:unassigned] += route[:activities].select{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] } if load_flag && time_flag
        load_flag && time_flag
      }
    end

    def self.build_partial_service_vrp(service_vrp, cluster_missions, available_vehicles = nil)
      vrp = service_vrp[:vrp]
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      services = vrp.services.select{ |service| cluster_missions.include?(service.id) }.compact
      shipments = vrp.shipments.select{ |shipment| cluster_missions.include?(shipment.id) }.compact
      # TODO: Within Scheduling Vehicles require to have unduplicated ids
      sub_vrp.vehicles = available_vehicles.collect{ |vehicle_id|
        vehicle_index = sub_vrp.vehicles.find_index{ |vehicle| vehicle.id == vehicle_id }
        vrp.vehicles.slice!(vehicle_index)
      } if available_vehicles
      points_ids = services.map{ |s| s.activity.point.id }.uniq.compact + shipments.map{ |s| [s.pickup.point.id, s.delivery.point.id] }.flatten.uniq.compact
      sub_vrp.services = services
      sub_vrp.shipments = shipments
      sub_vrp.points = (vrp.points.select{ |p| points_ids.include? p.id } + sub_vrp.vehicles.collect{ |vehicle| [vehicle.start_point, vehicle.end_point] }.flatten).compact.uniq
      {
        vrp: sub_vrp,
        service: service_vrp[:service]
      }
    end

    def self.count_metric(graph, parent, symbol)
      value = parent.nil? ? 0 : graph[parent][:unit_metrics][symbol]
      value + (parent.nil? ? 0 : (count_metric(graph, graph[parent][:left], symbol) + count_metric(graph, graph[parent][:right], symbol)))
    end

    def self.collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics, max_cut_metrics = nil)
      data_items = []

      depot_ids = vrp.vehicles.collect{ |vehicle| [vehicle.start_point_id, vehicle.end_point_id] }.flatten.compact.uniq
      points = vrp.services.collect.with_index{ |service|
        service.activity.point
      } + vrp.shipments.collect{ |shipment|
        depot_ids.include?(shipment.pickup.point.id) && shipment.delivery.point || depot_ids.include?(shipment.delivery.point.id) && shipment.pickup.point
      }.compact
      points.uniq!
      linked_objects = {}
      points.each{ |point|
        unit_quantities = {}
        unit_symbols.each{ |unit| unit_quantities[unit] = 0 }
        related_services = vrp.services.select{ |service| service.activity.point.id == point.id }
        point_objects = related_services.collect{ |service|
          unit_quantities[:visits] += 1
          cumulated_metrics[:visits] += 1
          unit_quantities[:duration] += service.activity.duration * service.visits_number
          cumulated_metrics[:duration] += service.activity.duration * service.visits_number
          service.quantities.each{ |quantity|
            unit_quantities[quantity.unit_id.to_sym] += quantity.value * service.visits_number
            cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * service.visits_number
          }
          service.id
        }
        related_pickups = vrp.shipments.select{ |shipment| shipment.pickup.point.id == point.id }
        point_objects << related_pickups.collect{ |shipment|
          unit_quantities[:visits] += 1
          cumulated_metrics[:visits] += 1
          unit_quantities[:duration] += shipment.pickup.duration
          cumulated_metrics[:duration] += shipment.pickup.duration
          shipment.quantities.each{ |quantity|
            unit_quantities[quantity.unit_id.to_sym] += quantity.value * shipment.visits_number
            cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * shipment.visits_number
          }
          shipment.id
        }

        related_deliveries = vrp.shipments.select{ |shipment| shipment.delivery.point.id == point.id }
        point_objects << related_deliveries.collect{ |shipment|
          unit_quantities[:visits] += 1
          cumulated_metrics[:visits] += 1
          unit_quantities[:duration] += shipment.pickup.duration
          cumulated_metrics[:duration] += shipment.pickup.duration
          shipment.quantities.each{ |quantity|
            unit_quantities[quantity.unit_id.to_sym] += quantity.value * shipment.visits_number
            cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * shipment.visits_number
          }
          shipment.id
        }
        linked_objects[point.id] = point_objects

        if max_cut_metrics
          unit_symbols.each{ |unit|
            max_cut_metrics[unit] = [unit_quantities[unit], max_cut_metrics[unit]].max
          }
        end

        next if related_services.empty? && related_pickups.empty? && related_deliveries.empty?
        # Data items structure
        # 0 : Latitude
        # 1 : Longitude
        # 2 : Point id
        # 3 : Unit quantities
        # 4 : Sticky vehicles
        # 5 : Skills
        # 6 : Sequence timewindows size
        data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, nil, nil]
      }

      if max_cut_metrics
        [data_items, cumulated_metrics, linked_objects, max_cut_metrics]
      else
        [data_items, cumulated_metrics, linked_objects]
      end
    end

    def self.kmeans_process(centroids, c_max_iterations, max_iterations, nb_clusters, data_items, unit_symbols, cut_symbol, metric_limit, vrp, incompatibility_set = nil)
      c = BalancedKmeans.new
      c.max_iterations = c_max_iterations
      c.centroid_indices = centroids if centroids

      biggest_cluster_size = 0
      clusters = []
      iteration = 0
      while biggest_cluster_size < nb_clusters && iteration < max_iterations
        ratio = 0.5 + 0.5 * (max_iterations - iteration) / max_iterations
        c.build(DataSet.new(data_items: data_items), unit_symbols, nb_clusters, cut_symbol, ratio * metric_limit, vrp.debug_output_kmeans_centroids, incompatibility_set)
        c.clusters.delete([])
        if c.clusters.size > biggest_cluster_size
          biggest_cluster_size = c.clusters.size
          clusters = c.clusters
          centroids = c.centroid_indices
        end
        c.centroid_indices = [] if c.centroid_indices.size < nb_clusters
        iteration += 1
      end
      clusters
    end

    def self.list_vehicles(vehicles)
      vehicle_list = []
      vehicles.each{ |vehicle|
        if vehicle[:timewindow]
          (0..6).each{ |day|
            tw = Marshal.load(Marshal.dump(vehicle[:timewindow]))
            tw[:day_index] = day
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle[:timewindow] = tw
            vehicle_list << new_vehicle
          }
        elsif vehicle[:sequence_timewindows]
          vehicle[:sequence_timewindows].each{ |tw|
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle[:sequence_timewindows] = [tw]
            vehicle_list << new_vehicle
          }
        end
      }
      vehicle_list
    end

    def self.assign_vehicle_to_clusters(vehicles, points, clusters, entity = '', kmeans = true)
      cluster_vehicles = Array.new(clusters.size, [])
      if entity == 'work_day' || entity == 'vehicle' && vehicles.collect{ |vehicle| vehicle[:sequence_timewindows] && vehicle[:sequence_timewindows].size }.compact.uniq.size >= 1
        vehicles.each_with_index{ |vehicle, i|
          cluster_vehicles[i] = [vehicle.id]
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
          next if available_clusters.empty?
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
          cluster_vehicles[available_clusters[smallest_value_index][:id]] << vehicle.id
          available_clusters.delete(available_clusters[smallest_value_index])
        }
      end

      cluster_vehicles
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

    def self.split_balanced_kmeans(service_vrp, nb_clusters, cut_symbol = :duration, entity = '')
      vrp = service_vrp[:vrp]
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] }
        cumulated_metrics = {}
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }

        data_items, cumulated_metrics, linked_objects = collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics)
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
          vrp.vehicles.each_with_index{ |_vehicle, index|
            skills_index += 1 if vrp.vehicles.size - centroids_skills.size < index
            centroids += [data_items.index(data_items.find{ |data| data[5] == centroids_skills[skills_index] && (data_items.length < nb_clusters || !centroids.include?(data_items.index(data))) })]
          }
          limits = cumulated_metrics[cut_symbol] / nb_clusters
        else
          limits = cumulated_metrics[cut_symbol] / nb_clusters
        end
        centroids = vrp[:preprocessing_kmeans_centroids] if vrp[:preprocessing_kmeans_centroids] && entity != 'work_day'

        clusters = kmeans_process(centroids, 200, 30, nb_clusters, data_items, unit_symbols, cut_symbol, limits, vrp)
        result_items = clusters.delete_if{ |cluster| cluster.data_items.empty? }.collect{ |cluster|
          cluster.data_items.collect{ |i|
            linked_objects[i[2]]
          }.flatten
        }

        puts 'Balanced K-Means : Splited ' + data_items.size.to_s + ' into ' + clusters.collect{ |cluster| cluster.data_items.size }.join(' & ')
        cluster_vehicles = nil
        cluster_vehicles = assign_vehicle_to_clusters(vrp.vehicles, vrp.points, clusters, entity) if entity != ''
        adjust_clusters(clusters, limits, cut_symbol, centroids, data_items) if entity == 'work_day'
        result_items.collect.with_index{ |result_item, result_index|
          build_partial_service_vrp(service_vrp, result_item, cluster_vehicles && cluster_vehicles[result_index])
        }
      else
        puts 'split hierarchical not available when services have activities'
        [service_vrp]
      end
    end

    # Adjust cluster if they are disparate - only called when entity == 'work_day'
    def self.adjust_clusters(clusters, limits, cut_symbol, centroids, data_items)
      clusters.each_with_index{ |_cluster, index|
        centroids[index] = data_items[centroids[index]]
      }
      clusters.each_with_index{ |cluster, index|
        count = 0
        cluster.data_items.sort_by!{ |data| Helper.flying_distance(data, centroids[index]) }
        cluster.data_items.each{ |data|
          count += data[3][cut_symbol]
          next if count <= limits || centroids.include?(data)
          c = find_cluster(clusters, cluster, cut_symbol, data, limits)
          next if c.nil?
          cluster.data_items.delete(data)
          c.data_items.insert(c.data_items.size, data)
          count -= data[3][cut_symbol]
        }
      }
    end

    # Find the nearest cluster to add data_to_insert - because the other is full
    def self.find_cluster(clusters, original_cluster, cut_symbol, data_to_insert, limit)
      c = nil
      dist = 2**32
      clusters.each{ |cluster|
        next if cluster == original_cluster
        cluster.data_items.each{ |data|
          if dist > Helper.flying_distance(data, data_to_insert) && cluster.data_items.collect{ |data_item| data_item[3][cut_symbol] }.sum < limit &&
             cluster.data_items.all?{ |d| data_to_insert[5].nil? || d[5] && (data_to_insert[5] & d[5]).size >= d[5].size }
            dist = Helper.flying_distance(data, data_to_insert)
            c = cluster
          end
        }
      }

      c
    end

    def self.split_hierarchical(service_vrp, nb_clusters, cut_symbol = :duration, entity = '')
      vrp = service_vrp[:vrp]
      # splits using hierarchical tree method
      if vrp.services.all?{ |service| service[:activity] }
        max_cut_metrics = {}
        cumulated_metrics = {}

        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }
        unit_symbols.map{ |unit| max_cut_metrics[unit] = 0 }

        data_items, cumulated_metrics, linked_objects, max_cut_metrics = collect_data_items_metrics(vrp, unit_symbols, cumulated_metrics, max_cut_metrics)

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
          graph.select{ |_k, v| v[:level] == current_level }.each{ |k, v|
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
        result_items = clusters.delete_if{ |cluster| cluster.data_items.empty? }.collect{ |cluster|
          cluster.data_items.collect{ |i|
            linked_objects[i[0]]
          }.flatten
        }

        puts 'Hierarchical Tree : Splited ' + data_items.size.to_s + ' into ' + clusters.collect{ |cluster| cluster.data_items.size }.join(' & ')
        cluster_vehicles = nil
        cluster_vehicles = assign_vehicle_to_clusters(vrp.vehicles, vrp.points, clusters, entity, false) if entity != ''
        adjust_clusters(clusters, limits, cut_symbol, centroids, data_items) if entity == 'work_day'
        result_items.collect.with_index{ |result_item, result_index|
          build_partial_service_vrp(service_vrp, result_item, cluster_vehicles && cluster_vehicles[result_index])
        }
      else
        puts 'split hierarchical not available when services have activities'
        [service_vrp]
      end
    end
  end
end
