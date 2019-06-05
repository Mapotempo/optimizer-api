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

      attr_reader :cluster_metrics

      parameters_info max_iterations: 'Maximum number of iterations to ' \
                      'build the clusterer. By default it is uncapped.',
                      centroid_function: 'Custom implementation to calculate the ' \
                        'centroid of a cluster. It must be a closure receiving an array of ' \
                        'data sets, and return an array of data items, representing the ' \
                        'centroids of for each data set. ' \
                        'By default, this algorithm returns a data items using the mode '\
                        'or mean of each attribute on each data set.',
                      centroid_indices: 'Indices of data items (indexed from 0) to be ' \
                        'the initial centroids.  Otherwise, the initial centroids will be ' \
                        'assigned randomly from the data set.',
                      on_empty: 'Action to take if a cluster becomes empty, with values ' \
                        "'eliminate' (the default action, eliminate the empty cluster), " \
                        "'terminate' (terminate with error), 'random' (relocate the " \
                        "empty cluster to a random point), 'outlier' (relocate the " \
                        "empty cluster to the point furthest from its centroid).",
                      possible_caracteristics_combination: 'Set of skills we can combine in the same cluster.',
                      impossible_day_combination: 'Maximum set of conflicting days.'

      # Build a new clusterer, using data examples found in data_set.
      # Items will be clustered in "number_of_clusters" different
      # clusters.

      def build(data_set, unit_symbols, number_of_clusters, cut_symbol, cut_limit, output_centroids, options = {})
        @data_set = data_set
        reduced_number_of_clusters = [number_of_clusters, data_set.data_items.collect{ |data_item| [data_item[0], data_item[1]] }.uniq.size].min
        unless reduced_number_of_clusters == number_of_clusters || @centroid_indices.empty?
          @centroid_indices = @centroid_indices.collect{ |centroid_index|
            [@data_set.data_items[centroid_index], centroid_index]
          }.uniq{ |item| [item.first[0], item.first[1]] }.collect(&:last)
        end
        @number_of_clusters = reduced_number_of_clusters

        @cut_limit = cut_limit
        @cut_symbol = cut_symbol
        @output_centroids = output_centroids
        @unit_symbols = unit_symbols

        @centroid_function = lambda do |clusters|
          clusters.collect{ |data_set| get_mean_or_mode(data_set) }
        end

        raise ArgumentError, 'Length of centroid indices array differs from the specified number of clusters' unless @centroid_indices.empty? || @centroid_indices.length == @number_of_clusters
        raise ArgumentError, 'Invalid value for on_empty' unless @on_empty == 'eliminate' || @on_empty == 'terminate' || @on_empty == 'random' || @on_empty == 'outlier'
        @iterations = 0

        calc_initial_centroids
        @rate_balance = 1.0
        @data_set.data_items.sort_by!{ |x| x[3][@cut_symbol] || 0 }.reverse! if @cut_symbol # TODO: This doesn't need to be in here move outside after testing
        until stop_criteria_met
          calculate_membership_clusters
          sort_clusters
          recompute_centroids
        end
        @rate_balance = options[:rate_balance] || 0.1
        calculate_membership_clusters
        sort_clusters
        recompute_centroids

        self
      end

      def num_attributes(data_items)
        return (data_items.empty?) ? 0 : data_items.first.size
      end

      # Get the sample mean
      def mean(data_items, index)
        sum = 0.0
        data_items.each { |item| sum += item[index] }
        return sum / data_items.length
      end

      # Get the sample mode.
      def mode(data_items, index)
        count = Hash.new {0}
        max_count = 0
        mode = nil
        data_items.each do |data_item|
          attr_value = data_item[index]
          attr_count = (count[attr_value] += 1)
          if attr_count > max_count
            mode = attr_value
            max_count = attr_count
          end
        end
        return mode
      end

      def mode_not_nil(data_items, index)
        count = Hash.new {0}
        max_count = 0
        mode = nil
        data_items.each do |data_item|
          attr_value = data_item[index]
          attr_count = (count[attr_value] += attr_value.nil? ? 0 : 1)
          if attr_count > max_count
            mode = attr_value
            max_count = attr_count
          end
        end
        return mode
      end

      def get_mean_or_mode(data_set)
        data_items = data_set.data_items
        mean = []
        num_attributes(data_items).times do |i|
          mean[i] =
                  if data_items.first[i].is_a?(Numeric)
                    mean(data_items, i)
                  elsif i == 4
                    mode_not_nil(data_items, i)
                  else
                    mode(data_items, i)
                  end
        end
        return mean
      end

      def recompute_centroids
        @old_centroids = @centroids
        data_sticky = @centroids.collect{ |data| data[4] }
        data_skill = @centroids.collect{ |data| data[5] }
        data_size = @centroids.collect{ |data| data[6] }
        @centroids.collect!{ |centroid|
          centroid[4] = nil
          centroid[5] = []
          centroid[6] = 0
          centroid.compact
        }
        @iterations += 1

        @centroids = @centroid_function.call(@clusters)
        @old_centroids.collect!.with_index{ |data, index|
          data_item = @data_set.data_items.find{ |data_item| data_item[2] == data[2] }
          data_item[4] = data_sticky[index]
          data_item[5] = data_skill[index]
          data_item[6] = data_size[index]
          data_item
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

      def compute_compatibility(caracteristics_a, caracteristics_b)
        # TODO : not differenciate day skills and skills and simplify
        hard_violation = false
        non_common_number = 0

        if !(caracteristics_a - caracteristics_b).empty? # all required skills are not available in centroid
          new_day_caracteristics = (caracteristics_a + caracteristics_b).select{ |car| car.include?('not_day') }.uniq
          if new_day_caracteristics.uniq.size == @impossible_day_combination.size
            hard_violation = true
          else
            non_common_number += (new_day_caracteristics - caracteristics_b).size
          end

          new_caracteristics = (caracteristics_a + caracteristics_b).reject{ |car| car.include?('not_day') }.uniq
          if !@possible_caracteristics_combination.any?{ |combination| new_caracteristics.all?{ |car| combination.include?(car) } }
            hard_violation = true
          else
            non_common_number += (new_caracteristics - caracteristics_b).size
          end
        end

        [hard_violation, non_common_number]
      end

      def distance(a, b, cluster_index)
        # TODO : rename a & b ?
        fly_distance = Helper.flying_distance(a, b)
        cut_value = @cluster_metrics[cluster_index][@cut_symbol].to_f
        limit = if @cut_limit.is_a? Array
          @cut_limit[cluster_index]
        else
          @cut_limit
        end

        # caracteristics compatibility
        hard_violation, non_common_number = a[5].empty? ? [false, 0] : compute_compatibility(a[5], b[5])
        compatibility = if a[4] && b[4] && (b[4] & a[4]).empty? || # if service sticky or skills are different than centroids sticky/skills,
                           hard_violation # or if services skills have no match
          2**32
        elsif non_common_number > 0 # if services skills have no intersection but could have one
          fly_distance * non_common_number
        else
          0
        end

        # balance between clusters computation
        balance = 1.0
        if @cluster_metrics.all?{ |cm| cm[@cut_symbol] > 0 } #&& @iterations > 0
          @average_load = @total_load / @number_of_clusters
          if @average_load / limit < 0.95
            balance = (cut_value / @average_load)**(2 * @average_load / limit)
          else
            balance = (cut_value / @average_load)
          end
          #puts "%#{(@average_load*100/limit).to_i} balance: #{balance.round(2)} current cluster load: #{cut_value} @average_load: #{@average_load}"
        end

        (fly_distance + compatibility) * balance
      end

      def calculate_membership_clusters
        @cluster_metrics = Array.new(@number_of_clusters) { Hash.new(0) }
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new :data_labels => @data_set.data_labels
        end
        @cluster_indices = Array.new(@number_of_clusters) {[]}

        @total_load = 0
        @data_set.data_items.each_with_index do |data_item, data_index|
          c = eval(data_item)
          @clusters[c] << data_item
          @cluster_indices[c] << data_index if @on_empty == 'outlier'
          @unit_symbols.each{ |unit|
            @cluster_metrics[c][unit] += data_item[3][unit]
            if unit == @cut_symbol
              @total_load += data_item[3][unit]
            end
          }
          update_centroid_properties(c, data_item) # TODO : only if missing caracteristics. Returned through eval ?
        end
        manage_empty_clusters if has_empty_cluster?
      end

      def calc_initial_centroids
        @centroid_indices = [] # TODO : move or remove
        @centroids, @old_centroids = [], nil
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
        old_clusters, old_centroids, old_cluster_indices = @clusters, @centroids, @cluster_indices
        @clusters, @centroids, @cluster_indices = [], [], []
        @number_of_clusters.times do |i|
          next if old_clusters[i].data_items.empty?
          @clusters << old_clusters[i]
          @cluster_indices << old_cluster_indices[i]
          @centroids << old_centroids[i]
        end
        @number_of_clusters = @centroids.length
      end

      def stop_criteria_met
        @old_centroids == @centroids ||
          same_centroid_distance_moving_average(Math.sqrt(@iterations).to_i) || #Check if there is a loop of size Math.sqrt(@iterations)
          (@max_iterations && (@max_iterations <= @iterations + 1))
      end

      def sort_clusters
        if @cut_limit.is_a? Array
          @limit_sorted_indices ||= @cut_limit.map.with_index{ |v, i| [i, v] }.sort_by{ |a| a[1] }.map{ |a| a[0] }
          cluster_sorted_indices = @cluster_metrics.map.with_index{ |v, i| [i, v[@cut_symbol]] }.sort_by{ |a| a[1] }.map{ |a| a[0] }
          if cluster_sorted_indices != @cluster_sorted_indices
            @cluster_sorted_indices = cluster_sorted_indices
            old_clusters = @clusters.dup
            old_centroids = @centroids.dup
            old_centroid_indices = @centroid_indices.dup
            old_cluster_metrics = @cluster_metrics.dup
            cluster_sorted_indices.each_with_index{ |i, j|
              @clusters[@limit_sorted_indices[j]] = old_clusters[i]
              @centroids[@limit_sorted_indices[j]] = old_centroids[i]
              @centroid_indices[@limit_sorted_indices[j]] = old_centroid_indices[i]
              @cluster_metrics[@limit_sorted_indices[j]] = old_cluster_metrics[i]
            }
          end
        end
      end

      private

      def same_centroid_distance_moving_average(last_n_iterations)
        if @iterations.zero?
          # Initialize the array stats array
          @last_n_average_diffs = [0.0] * (2 * last_n_iterations + 1)
          return false
        end

        # Calculate total absolute centroid movement in meters
        total_movement_meter = 0
        @number_of_clusters.times { |i|
          total_movement_meter += Helper.euclidean_distance(@old_centroids[i], @centroids[i])
        }

        # If convereged, we can stop
        return true if total_movement_meter.to_f < 1

        @last_n_average_diffs.push total_movement_meter.to_f

        # Check if there is a centroid loop of size n
        (1..last_n_iterations).each{ |n|
          last_n_iter_average_curr = @last_n_average_diffs[-n..-1].reduce(:+)
          last_n_iter_average_prev = @last_n_average_diffs[-(n + n)..-(1 + n)].reduce(:+)

          # If we make exact same moves again and again, we can stop
          return true if (last_n_iter_average_curr - last_n_iter_average_prev).abs < 1e-5
        }

        # Clean old stats
        @last_n_average_diffs.shift if @last_n_average_diffs.size > (2 * last_n_iterations + 1)

        return false
      end

      def update_centroid_properties(centroid_index, new_item)
        @centroids[centroid_index][5] |= new_item[5]
      end
    end
  end
end
