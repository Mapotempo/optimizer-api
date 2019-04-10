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
require './lib/helper.rb'

module Ai4r
  module Clusterers
    class BalancedKmeans < KMeans

      parameters_info max_iterations: "Maximum number of iterations to " \
        "build the clusterer. By default it is uncapped.",
        centroid_function: "Custom implementation to calculate the " \
          "centroid of a cluster. It must be a closure receiving an array of " \
          "data sets, and return an array of data items, representing the " \
          "centroids of for each data set. " \
          "By default, this algorithm returns a data items using the mode "\
          "or mean of each attribute on each data set.",
        centroid_indices: "Indices of data items (indexed from 0) to be " \
          "the initial centroids.  Otherwise, the initial centroids will be " \
          "assigned randomly from the data set.",
        on_empty: "Action to take if a cluster becomes empty, with values " \
          "'eliminate' (the default action, eliminate the empty cluster), " \
          "'terminate' (terminate with error), 'random' (relocate the " \
          "empty cluster to a random point), 'outlier' (relocate the " \
          "empty cluster to the point furthest from its centroid)."

      # Build a new clusterer, using data examples found in data_set.
      # Items will be clustered in "number_of_clusters" different
      # clusters.

      def build(data_set, unit_symbols, number_of_clusters, cut_symbol, cut_limit, output_centroids, incompatibility_set = nil)
        @data_set = data_set
        @unit_symbols = unit_symbols
        @cut_symbol = cut_symbol
        @cut_limit = cut_limit
        @number_of_clusters = number_of_clusters
        @output_centroids = output_centroids
        @incompatibility_set = incompatibility_set
        raise ArgumentError, 'Length of centroid indices array differs from the specified number of clusters' unless @centroid_indices.empty? || @centroid_indices.length == @number_of_clusters
        raise ArgumentError, 'Invalid value for on_empty' unless @on_empty == 'eliminate' || @on_empty == 'terminate' || @on_empty == 'random' || @on_empty == 'outlier'
        @iterations = 0

        # calc_initial_clusters_metrics
        calc_initial_centroids

        until stop_criteria_met
          calculate_membership_clusters
          recompute_centroids
        end

        self
      end

      def recompute_centroids
        @old_centroids = @centroids
        data_sticky = @centroids.collect{ |data| data[4] }
        data_skill = @centroids.collect{ |data| data[5] }
        data_size = @centroids.collect{ |data| data[6] }
        @centroids.collect!{ |centroid|
          centroid[4] = nil
          centroid[5] = nil
          centroid[6] = nil
          centroid.compact
        }
        @iterations += 1
        @centroids = @centroid_function.call(@clusters)
        @old_centroids.each_with_index{ |data, index|
          data[4] = data_sticky[index]
          data[5] = data_skill[index]
          data[6] = data_size[index]
        }
        @centroids.each_with_index{ |data, index|
          data[4] = data_sticky[index]
          data[5] = data_skill[index]
          data[6] = data_size[index]
        }
        @centroids.each_with_index{ |centroid, index|
          @centroid_indices[index] = @data_set.data_items.find_index{ |data| data[2] == centroid[2] }
        }
      end

      # Classifies the given data item, returning the cluster index it belongs
      # to (0-based).
      def eval(data_item)
        get_min_index(@centroids.collect.with_index{ |centroid, cluster_index|
          distance(data_item, centroid, cluster_index)
        })
      end

      protected

      def distance(a, b, cluster_index)
        fly_distance = Helper::flying_distance(a, b)
        cut_value = @cluster_metrics[cluster_index][@cut_symbol].to_f
        # b[6] contains the weight associated to the current centroid. share represents the sum of all of the weight over the problem.
        share = @centroids.collect{ |centroid| centroid[6] }.sum if b[6]
        limit = if @cut_limit.is_a? Array
          @cut_limit[cluster_index]
        else
          @cut_limit
        end
        balance = if (a[4] && b[4] && b[4] != a[4]) || (a[5] && b[5] && (b[5] & a[5]).size < b[5].size) # if service sticky or skills are different than centroids sticky/skills, or if services skills have no match
          2 ** 32
        elsif cut_value > limit
          ((cut_value - limit) / limit) * 1000 * fly_distance
        else
          0
        end

        fly_distance + balance
      end

      def calculate_membership_clusters
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new :data_labels => @data_set.data_labels
        end
        @cluster_indices = Array.new(@number_of_clusters) {[]}

        @data_set.data_items.each_with_index do |data_item, data_index|
          c = eval(data_item)
          @clusters[c] << data_item
          @cluster_indices[c] << data_index if @on_empty == 'outlier'
          @unit_symbols.each{ |unit|
            if unit != :visits && data_item[3][:visits] != 1
              @cluster_metrics[c][unit] += data_item[3][unit]
            else
              @cluster_metrics[c][unit] += data_item[3][unit]
            end
          }
        end
        manage_empty_clusters if has_empty_cluster?
      end

      def calc_initial_centroids
        @centroids, @cluster_metrics, @old_centroids = [], [], nil
        if @centroid_indices.empty?
          populate_centroids('random')
        else
          populate_centroids('indices')
        end
      end

      def populate_centroids(populate_method, number_of_clusters=@number_of_clusters)
        tried_indexes = []
        case populate_method
        when 'random' # for initial assignment (without the :centroid_indices option) and for reassignment of empty cluster centroids (with :on_empty option 'random')
          while @centroids.length < number_of_clusters &&
              tried_indexes.length < @data_set.data_items.length
            @cluster_metrics << {}
            @unit_symbols.each{ |unit|
              @cluster_metrics.last[unit] = 0
            }
            random_index = rand(@data_set.data_items.length)
            if !tried_indexes.include?(random_index)
              tried_indexes << random_index
              if !@centroids.include? @data_set.data_items[random_index]
                @centroids << @data_set.data_items[random_index]
              end
            end
          end
          if @output_centroids
            puts "[DEBUG] kmeans_centroids : #{tried_indexes}"
          end
        when 'indices' # for initial assignment only (with the :centroid_indices option)
          @centroid_indices.each do |index|
            raise ArgumentError, "Invalid centroid index #{index}" unless (index.is_a? Integer) && index >=0 && index < @data_set.data_items.length
            if !tried_indexes.include?(index)
              @cluster_metrics << {}
              @unit_symbols.each{ |unit|
                @cluster_metrics.last[unit] = 0
              }
              tried_indexes << index
              if !@centroids.include? @data_set.data_items[index]
                @centroids << @data_set.data_items[index]
              end
            end
          end
        when 'outlier' # for reassignment of empty cluster centroids only (with :on_empty option 'outlier')
          sorted_data_indices = sort_data_indices_by_dist_to_centroid
          i = sorted_data_indices.length - 1 # the last item is the furthest from its centroid
          while @centroids.length < number_of_clusters &&
              tried_indexes.length < @data_set.data_items.length
            @cluster_metrics << {}
            @unit_symbols.each{ |unit|
              @cluster_metrics.last[unit] = 0
            }
            outlier_index = sorted_data_indices[i]
            if !tried_indexes.include?(outlier_index)
              tried_indexes << outlier_index
              if !@centroids.include? @data_set.data_items[outlier_index]
                @centroids << @data_set.data_items[outlier_index]
              end
            end
            i > 0 ? i -= 1 : break
          end
        end
        @number_of_clusters = @centroids.length
      end

      def eliminate_empty_clusters
        old_clusters, old_centroids, old_cluster_indices, old_cluster_metrics = @clusters, @centroids, @cluster_indices, @cluster_metrics
        @clusters, @centroids, @cluster_indices = [], [], []
        @number_of_clusters.times do |i|
          next if old_clusters[i].data_items.empty?
          @clusters << old_clusters[i]
          @cluster_indices << old_cluster_indices[i]
          @centroids << old_centroids[i]
          @cluster_metrics << old_cluster_metrics[i]
        end
        @number_of_clusters = @centroids.length
      end

      def stop_criteria_met
        @old_centroids == @centroids ||
          (@max_iterations && (@max_iterations <= @iterations))
      end
    end
  end
end
