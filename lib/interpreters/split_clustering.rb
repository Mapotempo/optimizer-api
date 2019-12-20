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

require './lib/clusterers/average_tree_linkage.rb'
require './lib/clusterers/balanced_kmeans.rb'
require './lib/helper.rb'
require './lib/interpreters/periodic_visits.rb'
require './lib/output_helper.rb'

module Interpreters
  class SplitClustering
    # TODO: private method
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
        elsif !vrp.scheduling? &&
              vrp.preprocessing_max_split_size && vrp.vehicles.size > 1 &&
              vrp.shipments.size == ship_candidates.size &&
              (ship_candidates.size + vrp.services.size - empties_or_fills.size) > vrp.preprocessing_max_split_size
          split_results << split_solve(service_vrp, &block)
          nil
        else
          {
            service: service_vrp[:service],
            vrp: vrp,
            level: (service_vrp[:level] || 0)
          }
        end
      }.flatten.compact
      two_stages = services_vrps[0][:vrp].preprocessing_partitions.size == 2

      OutputHelper::Clustering.generate_files(all_service_vrps, two_stages, job) if OptimizerWrapper.config[:debug][:output_clusters] && services_vrps.size < all_service_vrps.size

      [all_service_vrps, split_results]
    rescue => e
      log "#{e}\n\t\t#{e.backtrace[0..5].join("\n\t\t")}", level: :fatal
      raise
    end

    def self.generate_split_vrps(service_vrp, job = nil, block)
      log '--> generate_split_vrps', level: :debug
      vrp = service_vrp[:vrp]
      if vrp.preprocessing_partitions && !vrp.preprocessing_partitions.empty?
        current_service_vrps = [service_vrp]
        vrp.preprocessing_partitions.each_with_index{ |partition, partition_index|
          cut_symbol = partition[:metric] == :duration || partition[:metric] == :visits || vrp.units.any?{ |unit| unit.id.to_sym == partition[:metric] } ? partition[:metric] : :duration

          case partition[:method]
          when 'balanced_kmeans'
            generated_service_vrps = current_service_vrps.collect.with_index{ |s_v, s_v_i|
              block&.call(nil, nil, nil, "clustering phase #{partition_index + 1}/#{vrp.preprocessing_partitions.size} - step #{s_v_i + 1}/#{current_service_vrps.size}", nil, nil, nil)

              # TODO : global variable to know if work_day entity
              s_v[:vrp].vehicles = list_vehicles(s_v[:vrp].vehicles) if partition[:entity] == 'work_day'
              options = { cut_symbol: cut_symbol, entity: partition[:entity] }
              options[:restarts] = partition[:restarts] if partition[:restarts]
              split_balanced_kmeans(s_v, s_v[:vrp].vehicles.size, options)
            }
            current_service_vrps = generated_service_vrps.flatten
          when 'hierarchical_tree'
            generated_service_vrps = current_service_vrps.collect{ |s_v|
              current_vrp = s_v[:vrp]
              current_vrp.vehicles = list_vehicles([current_vrp.vehicles.first]) if partition[:entity] == 'work_day'
              split_hierarchical(s_v, current_vrp, current_vrp.vehicles.size, cut_symbol: cut_symbol, entity: partition[:entity])
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
          split_balanced_kmeans(service_vrp, vrp.vehicles.size, cut_symbol: cut_symbol)
        when 'hierarchical_tree'
          split_hierarchical(service_vrp, vrp.vehicles.size, cut_symbol: cut_symbol)
        else
          raise OptimizerWrapper::UnsupportedProblemError.new("Unknown partition method #{vrp.preprocessing_partition_method}")
        end
      end
    end

    def self.split_solve(service_vrp, job = nil, &block)
      vrp = service_vrp[:vrp]
      available_vehicle_ids = vrp.vehicles.collect(&:id)
      log "available_vehicle_ids: #{available_vehicle_ids.size} - #{available_vehicle_ids}", level: :debug

      problem_size = vrp.services.size + vrp.shipments.size
      empties_or_fills = (vrp.services.select{ |service| service.quantities.any?(&:fill) } +
                          vrp.services.select{ |service| service.quantities.any?(&:empty) }).uniq
      vrp.services -= empties_or_fills
      sub_service_vrps = split_balanced_kmeans(service_vrp, 2)

      result = []
      sub_service_vrps.sort_by{ |sub_service_vrp| -sub_service_vrp[:vrp].services.size }.each_with_index{ |sub_service_vrp, index|
        sub_vrp = sub_service_vrp[:vrp]
        sub_vrp.resolution_duration = vrp.resolution_duration / problem_size * (sub_vrp.services.size + sub_vrp.shipments.size)
        if vrp.resolution_minimum_duration || vrp.resolution_initial_time_out
          sub_vrp.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out) / problem_size * (sub_vrp.services.size + sub_vrp.shipments.size)
        end
        sub_vrp.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (0.10 + sub_vrp.services.size.to_f / vrp.services.size)).to_i
        sub_problem = {
          vrp: sub_vrp,
          service: service_vrp[:service]
        }
        sub_vrp.services += empties_or_fills
        sub_vrp.points += empties_or_fills.map{ |empti_of_fill| vrp.points.find{ |point| empti_of_fill.activity.point.id == point.id }}
        sub_vrp.vehicles.select!{ |vehicle| available_vehicle_ids.include?(vehicle.id) }

        sub_result = OptimizerWrapper.define_process([sub_problem], job, &block)

        remove_poor_routes(sub_vrp, sub_result)

        log "sub vrp (size: #{sub_problem[:vrp][:services].size}) uses #{sub_result[:routes].map{ |route| route[:vehicle_id] }.size} vehicles #{sub_result[:routes].map{ |route| route[:vehicle_id] }}, unassigned: #{sub_result[:unassigned].size}"
        raise 'Incorrect activities count' if sub_vrp.visits != sub_result[:routes].flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact.size + sub_result[:unassigned].map{ |u| u[:service_id] }.compact.size

        available_vehicle_ids.delete_if{ |id| sub_result[:routes].collect{ |route| route[:vehicle_id] }.include?(id) }
        empties_or_fills_used = remove_used_empties_and_refills(sub_vrp, sub_result).compact
        empties_or_fills -= empties_or_fills_used
        sub_problem[:vrp].services -= empties_or_fills_used
        empties_or_fills_remaining = empties_or_fills - empties_or_fills_used
        sub_result[:unassigned].delete_if{ |activity| empties_or_fills_remaining.map(&:id).include?(activity[:service_id]) } if index.zero?
        result = Helper.merge_results([result, sub_result])
      }
      vrp.services += empties_or_fills

      result
    end

    def self.remove_poor_routes(vrp, result)
      if result
        remove_empty_routes(result)
        remove_poorly_populated_routes(vrp, result, 0.2) if !Interpreters::Dichotomious.dichotomious_candidate?({vrp: vrp, service: :ortools})
      end
    end

    def self.remove_empty_routes(result)
      result[:routes].delete_if{ |route| route[:activities].none?{ |activity| activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] }}
    end

    def self.remove_poorly_populated_routes(vrp, result, limit)
      result[:routes].delete_if{ |route|
        vehicle = vrp.vehicles.find{ |current_vehicle| current_vehicle.id == route[:vehicle_id] }
        loads = route[:activities].last[:detail][:quantities]
        load_flag = vehicle.capacities.empty? || vehicle.capacities.all?{ |capacity|
          current_load = loads.find{ |unit_load| unit_load[:unit] == capacity.unit.id }
          current_load[:current_load] / capacity.limit < limit if capacity.limit && current_load && capacity.limit > 0
        }
        vehicle_worktime = vehicle.duration || vehicle.timewindow&.start && vehicle.timewindow&.end && (vehicle.timewindow.end - vehicle.timewindow.start) #can be nil!
        route_duration = route[:total_time] || (route[:activities].last[:begin_time] - route[:activities].first[:begin_time])

        log "route #{route[:vehicle_id]} time: #{route_duration}/#{vehicle_worktime} percent: #{((route_duration / (vehicle_worktime || route_duration).to_f) * 100).to_i}%", level: :debug

        time_flag = vehicle_worktime && route_duration < limit * vehicle_worktime

        if load_flag && time_flag
          number_of_services_in_the_route = route[:activities].map{ |a| a.slice(:service_id, :pickup_shipment_id, :delivery_shipment_id, :detail).compact if a[:service_id] || a[:pickup_shipment_id] || a[:delivery_shipment_id] }.compact.size

          log "route #{route[:vehicle_id]} is emptied: #{number_of_services_in_the_route} services are now unassigned.", level: :warn

          result[:unassigned] += route[:activities].map{ |a| a.slice(:service_id, :pickup_shipment_id, :delivery_shipment_id, :detail).compact if a[:service_id] || a[:pickup_shipment_id] || a[:delivery_shipment_id] }.compact
          true
        end
      }
    end

    def self.update_matrix(original_matrices, sub_vrp, matrix_indices)
      sub_vrp.matrices.each_with_index{ |matrix, index|
        [:time, :distance].each{ |dimension|
          matrix[dimension] = sub_vrp.vehicles.first.matrix_blend(original_matrices[index], matrix_indices, [dimension], cost_time_multiplier: 1, cost_distance_multiplier: 1)
        }
      }
    end

    def self.update_matrix_index(vrp)
      vrp.points.each_with_index{ |point, index|
        point.matrix_index = index
      }
    end

    def self.build_partial_service_vrp(service_vrp, partial_service_ids, available_vehicle_ids = nil)
      log '---> build_partial_service_vrp', level: :debug
      tic = Time.now
      # WARNING: Below we do marshal dump load but we continue using original objects
      # That is, if these objects are modified in sub_vrp then they will be modified in vrp too.
      # However, since original objects are coming from the data and we shouldn't be modifiying them, this doesn't pose a problem.
      # TOD0: Here we do Marshal.load/dump but we continue to use the original objects (and there is no bugs related to that)
      # That means we don't need hard copy of obejcts we just need to cut the connection between arrays (like services points etc) that we want to modify.
      vrp = service_vrp[:vrp]
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      # TODO: Within Scheduling Vehicles require to have unduplicated ids
      if available_vehicle_ids
        sub_vrp.vehicles.delete_if{ |vehicle| available_vehicle_ids.exclude?(vehicle[:id]) }
        sub_vrp.routes.delete_if{ |r| available_vehicle_ids.exclude? r.vehicle_id }
      end
      sub_vrp.services = sub_vrp.services.select{ |service| partial_service_ids.include?(service.id) }.compact
      sub_vrp.shipments = sub_vrp.shipments.select{ |shipment| partial_service_ids.include?(shipment.id) }.compact
      points_ids = sub_vrp.services.map{ |s| s.activity.point.id }.uniq.compact | sub_vrp.shipments.flat_map{ |s| [s.pickup.point.id, s.delivery.point.id] }.uniq.compact
      sub_vrp.rests = sub_vrp.rests.select{ |r| sub_vrp.vehicles.flat_map{ |v| v.rests.map(&:id) }.include? r.id }
      sub_vrp.relations = sub_vrp.relations.select{ |r| r.linked_ids.all? { |id| sub_vrp.services.any? { |s| s.id == id } || sub_vrp.shipments.any? { |s| id == s.id + 'delivery' || id == s.id + 'pickup' } } }
      sub_vrp.points = sub_vrp.points.select{ |p| points_ids.include? p.id }.compact
      sub_vrp.points += sub_vrp.vehicles.flat_map{ |vehicle| [vehicle.start_point, vehicle.end_point] }.compact

      if !sub_vrp.matrices&.empty?
        matrix_indices = sub_vrp.points.map{ |point| point.matrix_index }
        update_matrix_index(sub_vrp)
        update_matrix(sub_vrp.matrices, sub_vrp, matrix_indices)
      end

      log "<--- build_partial_service_vrp takes #{Time.now - tic}", level: :debug
      {
        vrp: sub_vrp,
        service: service_vrp[:service]
      }
    end

    # TODO: private method, reduce params
    def self.kmeans_process(centroids, nb_clusters, data_items, unit_symbols, limits, options = {}, &block)
      biggest_cluster_size = 0
      clusters = []
      centroids_characteristics = []
      restart = 0
      best_limit_score = nil
      c = nil
      score_hash = {}
      while restart < options[:restarts]
        log "Restart #{restart}/#{options[:restarts]}", level: :debug
        c = BalancedKmeans.new
        c.max_iterations = options[:max_iterations]
        c.centroid_indices = centroids if centroids && centroids.size == nb_clusters
        c.on_empty = 'random'
        c.expected_characteristics = options[:expected_characteristics] if options[:expected_characteristics]
        c.strict_limitations = limits[:strict_limit]

        ratio = 0.9 + 0.1 * (options[:restarts] - restart) / options[:restarts].to_f
        ratio_metric = limits[:metric_limit].dup
        if ratio_metric.is_a?(Array)
          ratio_metric.each{ |metric|
            metric[:limit] *= ratio
          }
        else
          ratio_metric[:limit] *= ratio
        end

        c.distance_function = options[:distance_function]

        c.incompatibility_function = options[:incompatibility_function]

        c.build(DataSet.new(data_items: data_items), unit_symbols, nb_clusters, options[:cut_symbol], ratio_metric, options)

        c.clusters.delete([])
        values = c.clusters.collect{ |cluster| cluster.data_items.collect{ |i| i[3][options[:cut_symbol]] }.sum.to_i }
        limit_score = (0..c.cluster_metrics.size - 1).collect{ |cluster_index|
          centroid_coords = [c.centroids[cluster_index][0], c.centroids[cluster_index][1]]
          distance_to_centroid = c.clusters[cluster_index].data_items.collect{ |item| custom_distance([item[0], item[1]], centroid_coords) }.sum
          ml = limits[:metric_limit].is_a?(Array) ? ratio_metric[cluster_index][:limit] : limits[:metric_limit][:limit]
          if c.clusters[cluster_index].data_items.size == 1
            2**32
          elsif ml.zero? # Why is it possible?
            distance_to_centroid
          else
            cluster_metric = c.clusters[cluster_index].data_items.collect{ |i| i[3][options[:cut_symbol]] }.sum.to_f
            # TODO: large clusters having great difference with target metric should have a large (bad) score
            #distance_to_centroid * ((cluster_metric - ml).abs / ml)
            balancing_coeff = if options[:entity] == 'work_day'
                                1.0
                              else
                                0.6
                              end
            (1.0 - balancing_coeff) * distance_to_centroid + balancing_coeff * ((cluster_metric - ml).abs / ml) * distance_to_centroid
          end
        }.sum
        checksum = Digest::MD5.hexdigest Marshal.dump(values)
        if !score_hash.has_key?(checksum)
          log "Restart: #{restart} score: #{limit_score} ratio_metric: #{ratio_metric} iterations: #{c.iterations}", level: :debug
          log "Balance: #{values.min}   #{values.max}    #{values.min - values.max}    #{(values.sum / values.size).to_i}    #{((values.max - values.min) * 100.0 / values.max).round(2)}%", level: :debug
          score_hash[checksum] = { iterations: c.iterations, limit_score: limit_score, restart: restart, ratio_metric: ratio_metric, min: values.min, max: values.max, sum: values.sum, size: values.size }
        end
        restart += 1
        empty_clusters_score = c.cluster_metrics.size < nb_clusters && (c.cluster_metrics.size..nb_clusters - 1).collect{ |cluster_index|
          limits[:metric_limit].is_a?(Array) ? limits[:metric_limit][cluster_index][:limit] : limits[:metric_limit][:limit]
        }.reduce(&:+) || 0
        limit_score += empty_clusters_score
        if best_limit_score.nil? || c.clusters.size > biggest_cluster_size || (c.clusters.size >= biggest_cluster_size && limit_score < best_limit_score)
          best_limit_score = limit_score
          log best_limit_score.to_s + ' -> New best cluster metric (' + c.cluster_metrics.collect{ |cluster_metric| cluster_metric[options[:cut_symbol]] }.join(', ') + ')'
          biggest_cluster_size = c.clusters.size
          clusters = c.clusters
          centroids = c.centroid_indices
          centroids_characteristics = c.centroids.collect{ |centroid| centroid[4] }
        end
        c.centroid_indices = [] if c.centroid_indices.size < nb_clusters
      end

      [clusters, centroids, centroids_characteristics]
    end

    def self.split_balanced_kmeans(service_vrp, nb_clusters, options = {}, &block)
      log '--> split_balanced_kmeans', level: :debug

      if options[:entity] && nb_clusters != service_vrp[:vrp].vehicles.size
        raise OptimizerWrapper::ClusteringError, 'Usage of options[:entity] requires that number of clusters (nb_clusters) is equal to number of vehicles in the vrp.'
      end

      default_options = { max_iterations: 300, restarts: 50, cut_symbol: :duration }
      options = default_options.merge(options)
      vrp = service_vrp[:vrp]
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] } && nb_clusters > 1
        cumulated_metrics = Hash.new(0)
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits

        if options[:entity] == 'work_day' || !vrp.matrices.empty?
          vrp.compute_matrix if vrp.matrices.empty?

          options[:distance_function] = lambda do |data_item_a, data_item_b|
            vrp.matrices[0][:time][data_item_a[3][:matrix_index]][data_item_b[3][:matrix_index]]
          end
        end

        options[:incompatibility_function] = lambda do |data_item, centroid|
          return false if compatible_characteristics?(data_item[4], centroid[4])

          true
        end

        data_items, cumulated_metrics, linked_objects = collect_data_items_metrics(vrp, options[:entity], unit_symbols, cumulated_metrics)
        limits = { metric_limit: centroid_limits(vrp, nb_clusters, data_items, cumulated_metrics, options[:cut_symbol], options[:entity]),
                   strict_limit: centroid_strict_limits(vrp) }
        centroids = vrp[:preprocessing_kmeans_centroids] if vrp[:preprocessing_kmeans_centroids] && options[:entity] != 'work_day'

        raise OptimizerWrapper::UnsupportedProblemError, 'Cannot use balanced kmeans if there are vehicles with alternative skills' if vrp.vehicles.any?{ |v| v[:skills].any?{ |skill| skill.is_a?(Array) } && v[:skills].size > 1 }

        tic = Time.now

        options[:expected_characteristics] = generate_expected_characteristics(vrp.vehicles)
        clusters, _centroids, centroid_characteristics = kmeans_process(centroids, nb_clusters, data_items, unit_symbols, limits, options, &block)

        toc = Time.now

        result_items = clusters.delete_if{ |cluster| cluster.data_items.empty? }.collect{ |cluster|
          cluster.data_items.flat_map{ |i|
            linked_objects[i[2]]
          }
        }
        log "Balanced K-Means (#{toc - tic}sec): split #{data_items.size} into #{clusters.map{ |c| "#{c.data_items.size}(#{c.data_items.map{ |i| i[3][options[:cut_symbol]] || 0 }.inject(0, :+)})" }.join(' & ')}"
        cluster_vehicles = assign_vehicle_to_clusters(centroid_characteristics, nil, nil, clusters) if options[:entity] == 'work_day' || options[:entity] == 'vehicle'

        result_items.collect.with_index{ |result_item, result_index|
          build_partial_service_vrp(service_vrp, result_item, cluster_vehicles && cluster_vehicles[result_index])
        }
      else
        log 'Split not available when services have no activity or cluster size is less than 2', level: :error
        # TODO : remove marshal dump
        # ensure test_instance_800unaffected_clustered and test_instance_800unaffected_clustered_same_point work
        [Marshal.load(Marshal.dump(service_vrp))]
      end
    end

    def self.split_hierarchical(service_vrp, nb_clusters, options = {})
      options[:cut_symbol] = :duration if options[:cut_symbol].nil?
      vrp = service_vrp[:vrp]
      # Split using hierarchical tree method
      if vrp.services.all?{ |service| service[:activity] }
        max_cut_metrics = Hash.new(0)
        cumulated_metrics = Hash.new(0)

        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits

        data_items, cumulated_metrics, linked_objects = collect_data_items_metrics(vrp, options[:entity], unit_symbols, cumulated_metrics, max_cut_metrics)

        custom_distance = lambda do |a, b|
          custom_distance(a, b)
        end
        c = AverageTreeLinkage.new
        c.distance_function = custom_distance
        start_timer = Time.now
        clusterer = c.build(DataSet.new(data_items: data_items), unit_symbols)
        end_timer = Time.now

        metric_limit = cumulated_metrics[options[:cut_symbol]] / nb_clusters
        # raise OptimizerWrapper::DiscordantProblemError.new("Unfitting cluster split metric. Maximum value is greater than average") if max_cut_metrics[options[:cut_symbol]] > metric_limit

        graph = Marshal.load(Marshal.dump(clusterer.graph.compact))

        # Tree cut process
        clusters = []
        max_level = graph.values.collect{ |value| value[:level] }.max

        # Top Down cut
        # current_level = max_level
        # while current_level >= 0
        #   graph.select{ |k, v| v[:level] == current_level }.each{ |k, v|
        #     next if v[:unit_metrics][options[:cut_symbol]] > 1.1 * metric_limit && current_level != 0
        #     clusters << tree_leafs_delete(graph, k).flatten.compact
        #   }
        #   current_level -= 1
        # end

        # Bottom Up cut
        (0..max_level).each{ |current_level|
          graph.select{ |_k, v| v[:level] == current_level }.each{ |k, v|
            next if v[:unit_metrics][options[:cut_symbol]] < metric_limit && current_level != max_level

            clusters << tree_leafs(graph, k).flatten.compact
            next if current_level == max_level

            remove_from_upper(graph, graph[k][:parent], options[:cut_symbol], v[:unit_metrics][options[:cut_symbol]])
            if k == graph[v[:parent]][:left]
              graph[v[:parent]][:left] = nil
            else
              graph[v[:parent]][:right] = nil
            end
          }
        }

        clusters.delete([])
        result_items = clusters.delete_if{ |cluster| cluster.data_items.empty? }.collect{ |i|
          linked_objects[i[2]]
        }.flatten

        log "Hierarchical Tree (#{end_timer - start_timer}sec): split #{data_items.size} into #{clusters.collect{ |cluster| cluster.data_items.size }.join(' & ')}"
        cluster_vehicles = assign_vehicle_to_clusters([[]] * vrp.vehicles.size, vrp.vehicles, vrp.points, clusters)
        adjust_clusters(clusters, limits, options[:cut_symbol], centroids, data_items) if options[:entity] == 'work_day'
        result_items.collect.with_index{ |result_item, result_index|
          build_partial_service_vrp(service_vrp, result_item, cluster_vehicles && cluster_vehicles[result_index])
        }
      else
        log 'Split hierarchical not available when services have no activity', level: :error
        [service_vrp]
      end
    end

    def self.list_vehicles(vehicles)
      vehicle_list = []
      vehicles.each{ |vehicle|
        if vehicle[:timewindow]
          (0..6).each{ |day|
            tw = Marshal.load(Marshal.dump(vehicle[:timewindow]))
            tw[:day_index] = day
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle.id = "#{vehicle.id}_#{day}"
            new_vehicle.original_id =  vehicle.id
            new_vehicle[:timewindow] = tw
            vehicle_list << new_vehicle
          }
        elsif vehicle[:sequence_timewindows]
          vehicle[:sequence_timewindows].each_with_index{ |tw, tw_i|
            new_vehicle = Marshal.load(Marshal.dump(vehicle))
            new_vehicle[:sequence_timewindows] = [tw]
            new_vehicle.id = "#{vehicle.id}_#{tw_i}"
            new_vehicle.original_id = vehicle.id
            vehicle_list << new_vehicle
          }
        end
      }
      vehicle_list.each(&:ignore_computed_data)
      vehicle_list
    end

    module ClassMethods
      private

      def custom_distance(a, b)
        fly_distance = Helper.flying_distance(a, b)
        # units_distance = (0..unit_sets.size - 1).any? { |index| a[3 + index] + b[3 + index] == 1 } ? 2**56 : 0
        # timewindows_distance = a[2].overlaps?(b[2]) ? 0 : 2**56
        fly_distance #+ units_distance + timewindows_distance
      end

      def compute_day_skills(timewindows)
        if timewindows.nil? || timewindows.empty? || timewindows.any?{ |tw| tw[:day_index].nil? }
          [0, 1, 2, 3, 4, 5, 6].collect{ |avail_day|
            "#{avail_day}_day_skill"
          }
        else
          timewindows.collect{ |tw| tw[:day_index] }.uniq.collect{ |avail_day|
            "#{avail_day}_day_skill"
          }
        end
      end

      def count_metric(graph, parent, symbol)
        value = parent.nil? ? 0 : graph[parent][:unit_metrics][symbol]
        value + (parent.nil? ? 0 : (count_metric(graph, graph[parent][:left], symbol) + count_metric(graph, graph[parent][:right], symbol)))
      end

      def compatible_characteristics?(service_chars, vehicle_chars)
        # Incompatile service and vehicle
        # if the vehicle cannot serve the service due to sticky_vehicle_id
        return false if !service_chars[:v_id].empty? && (service_chars[:v_id] & vehicle_chars[:v_id]).empty?

        # if the service needs a skill that the vehicle doesn't have
        return false if !(service_chars[:skills] - vehicle_chars[:skills]).empty?

        # if service and vehicle have no matching days
        return false if (service_chars[:days] & vehicle_chars[:days]).empty?

        true # if not, they are compatible
      end

      def collect_data_items_metrics(vrp, entity, unit_symbols, cumulated_metrics, max_cut_metrics = nil)
        data_items = []
        linked_objects = {}

        vehicles_characteristics = generate_expected_characteristics(vrp.vehicles)
        vehicle_units = vrp.vehicles.collect{ |v| v.capacities.to_a.collect{ |capacity| capacity.unit.id } }.flatten.uniq
        depot_ids = vrp.vehicles.collect{ |vehicle| [vehicle.start_point_id, vehicle.end_point_id] }.flatten.compact.uniq

        (vrp.services + vrp.shipments).group_by{ |s|
          if s.activity
            s.activity.point
          elsif s.delivery.point && depot_ids.include?(s.pickup.point.id)
            s.delivery.point.id
          elsif s.pickup.point && depot_ids.include?(s.delivery.point.id)
            s.pickup.point.id
          end
        }.each{ |point, set_at_point|
          next if !point

          set_at_point.group_by{ |s|
            related_skills = s.skills.to_a
            timewindows = s.activity&.timewindows || (s.pickup ? s.pickup.timewindows : s.delivery.timewindows)
            day_skills = compute_day_skills(timewindows)

            s_characteristics = {
              v_id: [s[:sticky_vehicle_ids]].flatten.compact,
              skills: related_skills,
              days: day_skills
            }

            if vehicles_characteristics.none?{ |v_characteristics| compatible_characteristics?(s_characteristics, v_characteristics) }
              #TODO: These cases need to be eliminted during preprocessing phases.
              log "There are no vehicles that can serve service #{s.id}.", level: :warn
            end

            s_characteristics
          }.each_with_index{ |(characteristics, sub_set), sub_set_index|
            unit_quantities = Hash.new(0)

            if entity == 'work_day' || !vrp.matrices.empty? #use matrix
              unit_quantities[:matrix_index] += point[:matrix_index]
            end

            sub_set.sort_by{ |s| - s.visits_number }.each_with_index{ |s, i|
              unit_quantities[:visits] += s.visits_number
              cumulated_metrics[:visits] += s.visits_number
              s_setup_duration = s.activity ? s.activity.setup_duration : (s.pickup ? s.pickup.setup_duration : s.delivery.setup_duration)
              s_duration = s.activity ? s.activity.duration : (s.pickup ? s.pickup.duration : s.delivery.duration)
              duration = ((i.zero? ? s_setup_duration : 0) + s_duration) * s.visits_number
              unit_quantities[:duration] += duration
              cumulated_metrics[:duration] += duration
              s.quantities.each{ |quantity|
                next if !vehicle_units.include? quantity.unit.id

                unit_quantities[quantity.unit_id.to_sym] += quantity.value * s.visits_number
                cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * s.visits_number
              }
            }

            linked_objects["#{point.id}_#{sub_set_index}"] = sub_set.collect{ |object| object[:id] }
            # TODO : group sticky and skills (in expected characteristics too)
            data_items << [point.location.lat, point.location.lon, "#{point.id}_#{sub_set_index}", unit_quantities, characteristics, nil, 0]
          }

          next if !max_cut_metrics

          unit_symbols.each{ |unit|
            max_cut_metrics[unit] = [unit_quantities[unit], max_cut_metrics[unit]].max
          }
        }

        if max_cut_metrics
          [data_items, cumulated_metrics, linked_objects, max_cut_metrics]
        else
          [data_items, cumulated_metrics, linked_objects]
        end
      end

      def generate_expected_characteristics(vehicles)
        vehicles.collect{ |v|
          tw = [v.timewindow || v.sequence_timewindows].flatten.compact
          {
            v_id: [v.id],
            skills: v.skills.flatten.uniq, # TODO : improve case with alternative skills. Current implementation collects all skill sets into one
            days: compute_day_skills(tw)
          }
        }
      end

      def assign_vehicle_to_clusters(clusters_characteristics, vehicles, points, clusters)
        if !vehicles.nil? || !points.nil?
          #TODO: This function is only implemented for balanced_kmeans
          #it needs to be implemented for hierarchical_tree split case
          raise 'This function is not ready for hierarchical_tree split case'
        end

        cluster_vehicle_ids = Array.new(clusters.size){ [] }

        (0..clusters.size - 1).each{ |cluster_index|
          cluster_vehicle_ids[cluster_index] = clusters_characteristics[cluster_index][:v_id]
        }

        cluster_vehicle_ids
      end

      # Adjust cluster if they are disparate - only called when entity == 'work_day'
      def adjust_clusters(clusters, limits, cut_symbol, centroids, data_items)
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
      def find_cluster(clusters, original_cluster, cut_symbol, data_to_insert, limit)
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

      def find_compatible_vehicles(cluster_to_affect, vehicles, available_clusters, vehicles_cluster_distance, entity, available_ids)
        compatible_vehicles = []
        violating = []
        all_days = [0, 1, 2, 3, 4, 5, 6]
        available_ids[:vehicle].each{ |v_i|
          vehicle = vehicles[v_i]

          conflict_with_clusters = vehicle[:skills].collect{ |skill| available_ids[:cluster].collect{ |i| available_clusters[i][:skills].include?(skill) ? available_clusters[i][:number_items] : 0 } }.flatten.sum
          conflict_with_clusters -= (available_clusters[cluster_to_affect][:skills] - vehicle.skills).size * available_clusters[cluster_to_affect][:number_items]
          violating << v_i if !(available_clusters[cluster_to_affect][:skills] - vehicle.skills).empty?

          days = [vehicle[:timewindow] ? (vehicle[:timewindow][:day_index] || all_days) : (vehicle[:sequence_timewindows].collect{ |tw| tw[:day_index] || all_days }) ].flatten.uniq
          conflict_with_clusters = days.collect{ |day| available_ids[:cluster].collect{ |i| available_clusters[i][:days_conflict][day] } }.flatten.sum
          conflict_with_clusters -= available_clusters[cluster_to_affect][:days_conflict][days.first] if days.size == 1 # 0 if no conflict between service and vehicle day
          violating << v_i if days.none?{ |day| available_clusters[cluster_to_affect][:day_skills].none?{ |skill| skill.include?(day.to_s) } }

          # TODO : test case with skills

          compatible_vehicles << [v_i, vehicles_cluster_distance[v_i][cluster_to_affect] * (1 - conflict_with_clusters / 100.0)]
        }

        if violating.size < available_ids[:vehicle].size
          # some vehicles are fully compatible
          compatible_vehicles.delete_if{ |v| violating.include?(v.first) }
        end

        compatible_vehicles
      end

      def remove_from_upper(graph, node, symbol, value_to_remove)
        if graph.has_key?(node)
          graph[node][:unit_metrics][symbol] -= value_to_remove
          remove_from_upper(graph, graph[node][:parent], symbol, value_to_remove)
        end
      end

      def remove_used_empties_and_refills(vrp, result)
        result[:routes].collect{ |route|
          current_service = nil
          route[:activities].select{ |activity| activity[:service_id] }.collect{ |activity|
            current_service = vrp.services.find{ |service| service[:id] == activity[:service_id] }
            current_service if current_service && current_service.quantities.any?(&:fill) || current_service.quantities.any?(&:empty)
          }
        }.flatten
      end

      def tree_leafs(graph, node)
        if node.nil?
          [nil]
        elsif (graph[node][:level]).zero?
           [node]
         else
           [tree_leafs(graph, graph[node][:left]), tree_leafs(graph, graph[node][:right])]
         end
      end

      def tree_leafs_delete(graph, node)
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

      def unsquared_matrix(vrp, a_indices, b_indices, dimension)
        current_matrix = vrp.matrices.find{ |matrix| matrix.id == vrp.vehicles.first.matrix_id }
        a_indices.map{ |a|
          b_indices.map { |b|
            current_matrix[dimension][b][a]
          }
        }
      end

      def centroid_limits(vrp, nb_clusters, data_items, cumulated_metrics, cut_symbol, entity)
        limits = []

        if entity == 'vehicle' && vrp.vehicles.all?{ |vehicle| vehicle[:sequence_timewindows] }
          if vrp.matrices.empty?
            single_location_array = [[vrp.vehicles[0].start_point.location.lat, vrp.vehicles[0].start_point.location.lon]]
            locations = data_items.collect{ |point| [point[0], point[1]] }
            log "matrix computation #{single_location_array.size}x#{locations.size} & #{locations.size}x#{single_location_array.size}"
            time_matrix_from_depot = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], single_location_array, locations).first
            time_matrix_to_depot = OptimizerWrapper.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], locations, single_location_array).first
          else
            single_index_array = [vrp.vehicles[0].start_point.matrix_index]
            point_indices = data_items.map{ |point| point[3][:matrix_index] }
            time_matrix_from_depot = unsquared_matrix(vrp, single_index_array, point_indices, :time)
            time_matrix_to_depot = unsquared_matrix(vrp, point_indices, single_index_array, :time)
          end

          data_items.each_with_index{ |point, index|
            point[3][:duration_from_and_to_depot] = time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
          }

          vrp.vehicles.sort_by!{ |vehicle| vehicle.sequence_timewindows.size }

          r_start = vrp.schedule_range_indices[:start]
          r_end = vrp.schedule_range_indices[:end]

          total_work_time = vrp.total_work_time.to_f

          vrp.vehicles.each{ |vehicle|
            limits << {
                        limit: cumulated_metrics[cut_symbol].to_f * (vehicle.total_work_time_in_range(r_start, r_end) / total_work_time),
                        total_work_time: vehicle.total_work_time_in_range(r_start, r_end),
                        total_work_days: vehicle.total_work_days_in_range(r_start, r_end)
                      }
          }
        else
          limits = { limit: cumulated_metrics[cut_symbol] / nb_clusters }
        end
        limits
      end

      def centroid_strict_limits(vrp)
        units = vrp.vehicles.collect{ |v| v[:capacities]&.collect{ |c| c[:unit_id] } }.flatten.compact.uniq # ignore units not referenced in vehicle capacities
        vrp.vehicles.collect.with_index{ |vehicle, v_i|
          schedule_indices = vrp.schedule_indices
          vehicle_working_days = schedule_indices ? vehicle.total_work_days_in_range(vrp.schedule_indices[0], vrp.schedule_indices[1]) : 1
          total_duration = schedule_indices ? vrp.total_work_times[v_i] : vehicle.work_duration
          s_l = { duration: total_duration }
          units.each{ |unit|
            s_l[unit.to_sym] = (vehicle[:capacities].any?{ |u| u[:unit_id] == unit } ? vehicle[:capacities].find{ |u| u[:unit_id] == unit }[:limit] : 0) * vehicle_working_days
          }
          s_l[:visits] = s_l[:visits] || vrp.visits
          s_l
        }
      end
    end

    extend ClassMethods
  end
end
