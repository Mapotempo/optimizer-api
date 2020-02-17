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

require 'ai4r'

module Ai4r
  module Clusterers
    class AverageTreeLinkage < AverageLinkage
      attr_reader :graph

      def build(data_set, unit_symbols, number_of_clusters = 1, **options)
        @data_set = data_set
        distance = options[:distance] || (1.0 / 0)
        @graph = {}
        @cluster_node_index = {}
        @data_set.data_items.each.with_index{ |data, index|
          @cluster_node_index[index] = 0
          @graph[index] = {
            point: data[2],
            level: 0,
            parent: nil,
            left: nil,
            right: nil,
            unit_metrics: data[3]
          }
        }
        node_counter = @data_set.data_items.size

        @index_clusters = create_initial_index_clusters
        @level_clusters, @node_clusters = create_initial_index_clusters_additional
        create_distance_matrix(data_set)
        while @index_clusters.length > number_of_clusters
          ci, cj = get_closest_clusters(@index_clusters)
          break if read_distance_matrix(ci, cj) > distance

          update_distance_matrix(ci, cj)
          @graph[@node_clusters[ci]][:parent] = node_counter
          @graph[@node_clusters[cj]][:parent] = node_counter
          merged_metrics = merge_metrics(ci, cj, unit_symbols, @graph, @node_clusters)

          @graph[node_counter] = {
            point: nil,
            level: [@level_clusters[ci], @level_clusters[cj]].max + 1,
            parent: nil,
            left: @node_clusters[ci],
            right: @node_clusters[cj],
            unit_metrics: merged_metrics
          }
          merge_clusters(ci, cj, @index_clusters)
          merge_clusters_additional(ci, cj, @level_clusters, @node_clusters, node_counter)
          node_counter += 1
        end

        @number_of_clusters = @index_clusters.length
        @distance_matrix = nil
        @clusters = build_clusters_from_index_clusters @index_clusters
        self
      end

      def merge_metrics(index_a, index_b, unit_symbols, graph, node_clusters)
        merged_metrics = {}
        unit_symbols.each{ |symbol|
          merged_metrics[symbol] = graph[node_clusters[index_a]][:unit_metrics][symbol] + graph[node_clusters[index_b]][:unit_metrics][symbol]
        }
        merged_metrics
      end

      def create_initial_index_clusters_additional
        level_clusters = []
        data_set.data_items.length.times { |_i| level_clusters << 0 }
        node_clusters = []
        data_set.data_items.length.times { |i| node_clusters << i }
        [level_clusters, node_clusters]
      end

      def merge_clusters_additional(index_a, index_b, level_clusters, node_clusters, node_counter)
        new_level_cluster = [@level_clusters[index_a], @level_clusters[index_b]].max + 1
        level_clusters.delete_at index_a
        level_clusters.delete_at index_b
        level_clusters << new_level_cluster

        new_node_cluster = node_counter
        node_clusters.delete_at index_a
        node_clusters.delete_at index_b
        node_clusters << new_node_cluster
      end

      def merge_clusters(index_a, index_b, index_clusters)
        index_a, index_b = index_b, index_a if index_b > index_a
        new_index_cluster = index_clusters[index_a] +
                            index_clusters[index_b]
        index_clusters.delete_at index_a
        index_clusters.delete_at index_b
        index_clusters << new_index_cluster
        index_clusters
      end
    end
  end
end
