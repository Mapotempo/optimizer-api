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

module Ai4r
  module Clusterers
    class CompleteLinkageMaxDistance < CompleteLinkage
      # Monkey patch : limit by inter-cluster distance in place of clusters number
      attr_reader :compatibility_matrix, :max_distance

      def build(data_set, max_distance)
        @data_set = data_set

        @max_distance = max_distance

        @compatibility_matrix = create_compatibility_matrix

        @index_clusters = create_initial_index_clusters
        create_distance_matrix(data_set)
        while @index_clusters.length > 1
          ci, cj, min_distance = get_closest_clusters(@index_clusters)
          break if min_distance > @max_distance

          update_distance_matrix(ci, cj)
          merge_clusters(ci, cj, @index_clusters)
        end
        @clusters = build_clusters_from_index_clusters @index_clusters

        self
      end

      # Create a partial compatibility matrix:
      def create_compatibility_matrix
        Array.new(@data_set.data_items.length - 1){ |index| Array.new(index + 1, true) }
      end

      # Similar to the original update_distance_matrix, however, it calls
      # update_compatibility_matrix before updating the distance matrix
      # and uses the compatibility information to not to calculate the
      # linkage distance if not necessary.
      def update_distance_matrix(ci, cj)
        ci, cj = cj, ci if cj > ci

        update_compatibility_matrix(ci, cj)

        distances_to_new_cluster = []
        new_clusters_compatibility = @compatibility_matrix.last
        (0..cj - 1).each do |cx|
          distances_to_new_cluster << (new_clusters_compatibility[cx] ? [@distance_matrix[ci - 1][cx], @distance_matrix[cj - 1][cx]].max : @max_distance + 1)
        end
        (cj + 1..ci - 1).each do |cx|
          distances_to_new_cluster << (new_clusters_compatibility[cx - 1] ? [@distance_matrix[ci - 1][cx], @distance_matrix[cx - 1][cj]].max : @max_distance + 1)
        end
        (ci + 1..@distance_matrix.length).each do |cx|
          distances_to_new_cluster << (new_clusters_compatibility[cx - 2] ? [@distance_matrix[cx - 1][ci], @distance_matrix[cx - 1][cj]].max : @max_distance + 1)
        end

        if cj.zero? && ci == 1
          @distance_matrix.delete_at(1)
          @distance_matrix.delete_at(0)
        elsif cj.zero?
          @distance_matrix.delete_at(ci - 1)
          @distance_matrix.delete_at(0)
        else
          @distance_matrix.delete_at(ci - 1)
          @distance_matrix.delete_at(cj - 1)
        end
        @distance_matrix.each do |d|
          d.delete_at(ci)
          d.delete_at(cj)
        end
        @distance_matrix << distances_to_new_cluster
      end

      # ci and cj are the indexes of the clusters that are going to
      # be merged. We need to update the compatibility matrix accordingly.
      def update_compatibility_matrix(ci, cj)
        ci, cj = cj, ci if cj > ci

        compatibility_of_new_cluster = []
        (0..cj - 1).each do |cx|
          compatibility_of_new_cluster << @compatibility_matrix[ci - 1][cx] && @compatibility_matrix[cj - 1][cx]
        end
        (cj + 1..ci - 1).each do |cx|
          compatibility_of_new_cluster << @compatibility_matrix[ci - 1][cx] && @compatibility_matrix[cx - 1][cj]
        end
        (ci + 1..@compatibility_matrix.length).each do |cx|
          compatibility_of_new_cluster << @compatibility_matrix[cx - 1][ci] && @compatibility_matrix[cx - 1][cj]
        end

        if cj.zero? && ci == 1
          @compatibility_matrix.delete_at(1)
          @compatibility_matrix.delete_at(0)
        elsif cj.zero?
          @compatibility_matrix.delete_at(ci - 1)
          @compatibility_matrix.delete_at(0)
        else
          @compatibility_matrix.delete_at(ci - 1)
          @compatibility_matrix.delete_at(cj - 1)
        end
        @compatibility_matrix.each do |d|
          d.delete_at(ci)
          d.delete_at(cj)
        end
        @compatibility_matrix << compatibility_of_new_cluster
      end

      # Returns ans array with the indexes of the two closest
      # clusters => [index_cluster_a, index_cluster_b]
      def get_closest_clusters(index_clusters)
        min_distance = 1.0 / 0
        closest_clusters = [1, 0]
        (index_clusters.size - 1).times do |index_a|
          (index_a + 1).times do |index_b|
            next unless @compatibility_matrix[index_a][index_b]

            cluster_distance = @distance_matrix[index_a][index_b]

            if cluster_distance > @max_distance
              @compatibility_matrix[index_a][index_b] = false
            elsif cluster_distance < min_distance
              closest_clusters = [index_a + 1, index_b]
              min_distance = cluster_distance
            end
          end
        end

        [closest_clusters[0], closest_clusters[1], min_distance]
      end
    end
  end
end
