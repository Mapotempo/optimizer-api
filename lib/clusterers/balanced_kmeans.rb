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
      attr_reader :iterations

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
                        'empty cluster to a random point)',
                      expected_characteristics: 'Expected sets of characteristics for generated clusters',
                      strict_limitations: 'Values that can not be exceeded, for each cluster',
                      incompatibility_function: 'Custom implementation of an incompatibility_function.'\
                        'It must be a closure receiving a data item and a centroid and return a '\
                        'boolean (true: if incompatible and false: if compatible). '\
                        'By default, this implementation uses a function which always returns false.'

      # Build a new clusterer, using data examples found in data_set.
      # Items will be clustered in "number_of_clusters" different
      # clusters.

      def build(data_set, unit_symbols, number_of_clusters, cut_symbol, cut_limit, options = {})
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
        @unit_symbols = unit_symbols
        @remaining_skills = @expected_characteristics.dup if @expected_characteristics
        @manage_empty_clusters_iterations = 0

        @distance_function ||= lambda do |a, b|
          Helper.flying_distance(a, b)
        end

        @incompatibility_function ||= lambda do |_data_item, _centroid| # By default all items are compatible.
          false
        end

        raise ArgumentError, 'Length of centroid indices array differs from the specified number of clusters' unless @centroid_indices.empty? || @centroid_indices.length == @number_of_clusters
        raise ArgumentError, 'Invalid value for on_empty' unless @on_empty == 'eliminate' || @on_empty == 'terminate' || @on_empty == 'random' || @on_empty == 'outlier'
        @iterations = 0

        if @cut_symbol
          @total_cut_load = @data_set.data_items.inject(0) { |sum, d| sum + d[3][@cut_symbol] }
          if @total_cut_load.zero?
            @cut_symbol = nil # Disable balanacing because there is no point
          else
            @data_set.data_items.sort_by!{ |x| x[3][@cut_symbol] ? -x[3][@cut_symbol] : 0 }
            data_length = @data_set.data_items.size
            @data_set.data_items[(data_length * 0.1).to_i..(data_length * 0.90).to_i] = @data_set.data_items[(data_length * 0.1).to_i..(data_length * 0.90).to_i].shuffle!
          end
        end

        calc_initial_centroids

        @rate_balance = 0.0
        until stop_criteria_met
          @rate_balance = 1.0 - (0.2 * @iterations / @max_iterations) if @cut_symbol

          update_cut_limit

          calculate_membership_clusters
          #sort_clusters
          recompute_centroids
        end

        if options[:last_iteration_balance_rate]
          @rate_balance = options[:last_iteration_balance_rate]

          update_cut_limit

          calculate_membership_clusters
        end

        self
      end

      def recompute_centroids
        @old_centroids_lat_lon = @centroids.collect{ |centroid| [centroid[0], centroid[1]] }

        @centroids.each_with_index{ |centroid, index|
          centroid[0] = Statistics.mean(@clusters[index], 0)
          centroid[1] = Statistics.mean(@clusters[index], 1)

          point_closest_to_centroid_center = clusters[index].data_items.min_by{ |data_point| Helper::flying_distance(centroid, data_point) }

          #correct the matrix_index of the centroid with the index of the point_closest_to_centroid_center
          centroid[3][:matrix_index] = point_closest_to_centroid_center[3][:matrix_index] if centroid[3][:matrix_index]

          if @cut_symbol
            #move the data_points closest to the centroid centers to the top of the data_items list so that balancing can start early
            @data_set.data_items.insert(0, @data_set.data_items.delete(point_closest_to_centroid_center)) #move it to the top

            #correct the distance_from_and_to_depot info of the new cluster with the average of the points
            centroid[3][:duration_from_and_to_depot] = @clusters[index].data_items.map { |d| d[3][:duration_from_and_to_depot] }.sum / @clusters[index].data_items.size.to_f
          end
        }

        @centroids.each_with_index{ |centroid, index|
          @centroid_indices[index] = @data_set.data_items.find_index{ |data| data[2] == centroid[2] }
        }

        @iterations += 1
      end

      # Classifies the given data item, returning the cluster index it belongs
      # to (0-based).
      def eval(data_item)
        get_min_index(@centroids.collect.with_index{ |centroid, cluster_index|
          dist = distance(data_item, centroid, cluster_index)

          if @incompatibility_function.call(data_item, centroid)
            dist += 2**32
          end

          if capactity_violation?(data_item, cluster_index)
            dist += 2**16
          end

          dist
        })
      end

      protected

      def distance(data_item, centroid, cluster_index)
        # TODO: Move extra logic outside of the distance function.
        # The user should be able to overload 'distance' function witoud losing any functionality
        distance = @distance_function.call(data_item, centroid)

        cut_value = @cluster_metrics[cluster_index][@cut_symbol].to_f
        limit = if @cut_limit.is_a? Array
          @cut_limit[cluster_index][:limit]
        else
          @cut_limit[:limit]
        end

        # balance between clusters computation
        balance = 1.0
        if @apply_balancing
          # At this "stage" of the clustering we would expect this limit to be met
          expected_cut_limit = limit * @percent_assigned_cut_load
          # Compare "expected_cut_limit to the current cut_value
          # and penalize (or favorise) if cut_value/expected_cut_limit greater (or less) than 1.
          balance = if @percent_assigned_cut_load < 0.95
                      # First down-play the effect of balance (i.e., **power < 1)
                      # After then make it more pronounced (i.e., **power > 1)
                      (cut_value / expected_cut_limit)**((2 + @rate_balance) * @percent_assigned_cut_load)
                    else
                      # If at the end of the clustering, do not take the power
                      (cut_value / expected_cut_limit)
                    end
        end

        if @rate_balance
          (1.0 - @rate_balance) * distance + @rate_balance * distance * balance
        else
          distance * balance
        end
      end

      def calculate_membership_clusters
        @cluster_metrics = Array.new(@number_of_clusters) { Hash.new(0) }
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new :data_labels => @data_set.data_labels
        end
        @cluster_indices = Array.new(@number_of_clusters) {[]}

        @total_assigned_cut_load = 0
        @percent_assigned_cut_load = 0
        @apply_balancing = false
        @data_set.data_items.each_with_index do |data_item, data_index|
          cluster_index = eval(data_item)
          @clusters[cluster_index] << data_item
          @cluster_indices[cluster_index] << data_index if @on_empty == 'outlier'
          update_metrics(data_item, cluster_index)
        end

        manage_empty_clusters if has_empty_cluster?
      end

      def calc_initial_centroids
        @centroid_indices = [] # TODO : move or remove
        @centroids, @old_centroids_lat_lon = [], nil
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
          while @centroids.length < number_of_clusters
            skills = @remaining_skills ? @remaining_skills.first : []

            # TODO : balanced_kmeans needs to be cleaned from the vrp logic
            # such as item[4], skills and other logic specific to the usage.
            # How do clustering know what is in the fourth place in data_item?
            # How the user will know that the fourth place is skills? etc.

            # Find the items which are not already used, and specifically need the skill set of this cluster
            compatible_items = @data_set.data_items.select{ |item|
              !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                !item[4].empty? &&
                !(item[4][:v_id].empty? && item[4][:skills].empty?) &&
                !@incompatibility_function.call(item, [0, 0, 0, 0, skills, 0])
            }

            if compatible_items.empty?
              # If there are no items which specifically needs these skills,
              # then find all the items that can be assigned to this cluster
              compatible_items = @data_set.data_items.select{ |item|
                !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                  !@incompatibility_function.call(item, [0, 0, 0, 0, skills, 0])
              }
            end

            if compatible_items.empty?
              # If, still, there are no items that can be assigned to this cluster
              # initialize it with a random point
              compatible_items = @data_set.data_items.reject{ |item|
                @centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2])
              }
            end

            item = compatible_items[rand(compatible_items.size)]

            @centroids << [item[0], item[1], item[2], item[3].dup, skills, nil, 0]

            @remaining_skills&.delete_at(0)

            @data_set.data_items.insert(0, @data_set.data_items.delete(item))
          end
          log "kmeans_centroids: #{@centroids.collect{ |centroid| centroid[2] }.flatten}", level: :debug
        when 'indices' # for initial assignment only (with the :centroid_indices option)
          @centroid_indices.each do |index|
            raise ArgumentError, "Invalid centroid index #{index}" unless (index.is_a? Integer) && index >= 0 && index < @data_set.data_items.length
            raise ArgumentError, "Index used twice #{index}" if tried_indexes.include?(index)
            tried_indexes << index
            item = @data_set.data_items[index]
            unless @clusters.collect{ |cluster| cluster.data_items.collect{ |item| item[2] }}.flatten.include?(item[2])
              # TODO : is this possible ? if we did not try this index, can we have two centroids with same ID ..? throw error if yess
              skills = @remaining_skills ? @remaining_skills.first : [] # order of @centroid_indices is important, should correspond to expected_characteristics_order!
              @centroids << [item[0], item[1], item[2], item[3].dup, skills, nil, 0]
              # TODO : give different ID
              @remaining_skills.delete_at(0) if @remaining_skills
            end
          end
        end
        @number_of_clusters = @centroids.length
      end

      def manage_empty_clusters
        @manage_empty_clusters_iterations += 1
        return if self.on_empty == 'terminate' # Do nothing to terminate with error. (The empty cluster will be assigned a nil centroid, and then calculating the distance from this centroid to another point will raise an exception.)

        initial_number_of_clusters = @number_of_clusters
        if @manage_empty_clusters_iterations < @data_set.data_items.size * 2
          eliminate_empty_clusters
        else
          # try generating all clusters again
          @clusters, @centroids, @cluster_indices = [], [], []
          @remaining_skills = @expected_characteristics.dup
          @number_of_clusters = @centroids.length
        end
        return if self.on_empty == 'eliminate'
        populate_centroids(self.on_empty, initial_number_of_clusters) # Add initial_number_of_clusters - @number_of_clusters
        calculate_membership_clusters
        @manage_empty_clusters_iterations = 0
      end

      def eliminate_empty_clusters
        old_clusters, old_centroids, old_cluster_indices = @clusters, @centroids, @cluster_indices
        @clusters, @centroids, @cluster_indices = [], [], []
        @remaining_skills = []
        @number_of_clusters.times do |i|
          if old_clusters[i].data_items.empty?
            @remaining_skills << old_centroids[i][4]
          else
            @clusters << old_clusters[i]
            @cluster_indices << old_cluster_indices[i]
            @centroids << old_centroids[i]
          end
        end
        @number_of_clusters = @centroids.length
      end

      def stop_criteria_met
        @old_centroids_lat_lon == @centroids.collect{ |c| [c[0], c[1]] } ||
          same_centroid_distance_moving_average(Math.sqrt(@iterations).to_i) || #Check if there is a loop of size Math.sqrt(@iterations)
          (@max_iterations && (@max_iterations <= @iterations))
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
            old_strict_limitations = @strict_limitations.dup
            cluster_sorted_indices.each_with_index{ |i, j|
              @clusters[@limit_sorted_indices[j]] = old_clusters[i]
              @centroids[@limit_sorted_indices[j]] = old_centroids[i]
              @centroid_indices[@limit_sorted_indices[j]] = old_centroid_indices[i]
              @cluster_metrics[@limit_sorted_indices[j]] = old_cluster_metrics[i]
              @strict_limitations[@limit_sorted_indices[j]] = old_strict_limitations[i]
            }
          end
        end
      end

      private

      def compute_vehicle_work_time_with(coef)
        @centroids.map.with_index{ |centroid, index|
          @cut_limit[index][:total_work_time] - coef * centroid[3][:duration_from_and_to_depot] * @cut_limit[index][:total_work_days]
        }
      end

      def update_cut_limit
        return if @rate_balance == 0.0 || @cut_symbol.nil? || @cut_symbol != :duration || !@cut_limit.is_a?(Array)
        #TODO: This functionality is implemented only for duration cut_symbol. Make sure it doesn't interfere with other cut_symbols
        vehicle_work_time = compute_vehicle_work_time_with(1.5)
        vehicle_work_time = compute_vehicle_work_time_with(1) if vehicle_work_time.any?{ |value| value.negative? }
        total_vehicle_work_times = vehicle_work_time.sum.to_f
        @centroids.size.times{ |index|
          @cut_limit[index][:limit] = @total_cut_load * vehicle_work_time[index] / total_vehicle_work_times
        }
      end

      def same_centroid_distance_moving_average(last_n_iterations)
        if @iterations.zero?
          # Initialize the array stats array
          @last_n_average_diffs = [0.0] * (2 * last_n_iterations + 1)
          return false
        end

        # Calculate total absolute centroid movement in meters
        total_movement_meter = 0
        @number_of_clusters.times { |i|
          total_movement_meter += Helper.euclidean_distance(@old_centroids_lat_lon[i], @centroids[i])
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

      def update_metrics(data_item, cluster_index)
        @unit_symbols.each{ |unit|
          @cluster_metrics[cluster_index][unit] += data_item[3][unit]
          next if unit != @cut_symbol

          @total_assigned_cut_load += data_item[3][unit]
          @percent_assigned_cut_load = @total_assigned_cut_load / @total_cut_load.to_f
          if !@apply_balancing && @cluster_metrics.all?{ |cm| cm[@cut_symbol].positive? }
            @apply_balancing = true
            log "Balancing activated late at iteration #{@iterations} after #{(@percent_assigned_cut_load * 100).round(2)}% of the services", level: :warn if @percent_assigned_cut_load > 0.2
          end
        }
      end

      def capactity_violation?(item, cluster_index)
        return false if @strict_limitations.empty?

        @cluster_metrics[cluster_index].any?{ |unit, value|
          value + item[3][unit] > (@strict_limitations[cluster_index][unit] || 0)
        }
      end
    end
  end
end
