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
      attr_reader :iterations
      attr_reader :cut_limit

      parameters_info vehicles_infos: 'Attributes of each cluster to generate. If centroid_indices are provided
                      then vehicles_infos should be ordered according to centroid_indices order',
                      distance_matrix: 'Distance matrix to use to compute distance between two data_items',
                      compatibility_function: 'Custom implementation of a compatibility_function.'\
                        'It must be a closure receiving a data item and a centroid and return a '\
                        'boolean (true: if compatible and false: if incompatible). '\
                        'By default, this implementation uses a function which always returns true.'

      def build(data_set, cut_symbol, cut_ratio = 1.0, options = {})
        # Build a new clusterer, using data items found in data_set.
        # Items will be clustered in "number_of_clusters" different
        # clusters. Each item is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_quantities -> for each unit, quantity associated to this item
        #    index 4 : characteristics -> { v_id: sticky_vehicle_ids, skills: skills, days: day_skills, matrix_index: matrix_index }

        ### return clean errors if unconsistent data ###
        if distance_matrix
          if vehicles_infos.any?{ |v_i| v_i[:depot].size != 1 } ||
             data_set.data_items.any?{ |item| !item[4][:matrix_index] }
            raise ArgumentError, 'Matrix provided : matrix index should be provided for all vehicle_info and all item'
          end
        elsif vehicles_infos.any?{ |v_i| v_i[:depot].compact.size != 2 } ||
              data_set.data_items.any?{ |item| !(item[0] && item[1]) }
          raise ArgumentError, 'No matrix provided : lattitude and longitude should be provided for all vehicle_info and all item'
        end

        if data_set.data_items.any?{ |item| item[3].nil? || !item[3].has_key?(cut_symbol) }
          raise ArgumentError, 'Cut symbol corresponding unit should be provided for all item'
        end

        raise ArgumentError, 'Should provide max_iterations' if @max_iterations.nil?

        ### default values ###
        data_set.data_items.each{ |item|
          item[4][:v_id] ||= []
          item[4][:skills] ||= []
          item[4][:days] ||= ['0_day_skill', '1_day_skill', '2_day_skill', '3_day_skill', '4_day_skill', '5_day_skill', '6_day_skill']
        }

        vehicles_infos.each{ |vehicle_info|
          vehicle_info[:total_work_days] ||= 1
          vehicle_info[:skills] ||= []
          vehicle_info[:days] ||= ['0_day_skill', '1_day_skill', '2_day_skill', '3_day_skill', '4_day_skill', '5_day_skill', '6_day_skill']
        }

        ### values ###
        @data_set = data_set
        @cut_symbol = cut_symbol
        @unit_symbols = if @vehicles_infos.all?{ |c| c[:capacities] }
          @vehicles_infos.collect{ |c| c[:capacities].keys }.flatten.uniq
        else
          [cut_symbol]
        end
        @number_of_clusters = [@vehicles_infos.size, data_set.data_items.collect{ |data_item| [data_item[0], data_item[1]] }.uniq.size].min

        compute_distance_from_and_to_depot(@vehicles_infos, @data_set, distance_matrix)
        @strict_limitations, @cut_limit = compute_limits(cut_symbol, cut_ratio, @vehicles_infos, @data_set.data_items, options[:entity])
        @remaining_skills = @vehicles_infos.dup

        @manage_empty_clusters_iterations = 0

        @distance_function ||= lambda do |a, b|
          if @distance_matrix
            @distance_matrix[a[4][:matrix_index]][b[4][:matrix_index]]
          else
            Helper.flying_distance(a, b)
          end
        end

        @compatibility_function ||= lambda do |data_item, centroid|
          if compatible_characteristics?(data_item[4], centroid[4])
            true
          else
            false
          end
        end

        ### algo start ###
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
          recompute_centroids
        end

        if options[:last_iteration_balance_rate]
          @rate_balance = options[:last_iteration_balance_rate]

          update_cut_limit

          calculate_membership_clusters
        end
      end

      def recompute_centroids
        @old_centroids_lat_lon = @centroids.collect{ |centroid| [centroid[0], centroid[1]] }

        @centroids.each_with_index{ |centroid, index|
          centroid[0] = Statistics.mean(@clusters[index], 0)
          centroid[1] = Statistics.mean(@clusters[index], 1)

          point_closest_to_centroid_center = clusters[index].data_items.min_by{ |data_point| Helper.flying_distance(centroid, data_point) }

          # correct the matrix_index of the centroid with the index of the point_closest_to_centroid_center
          centroid[4][:matrix_index] = point_closest_to_centroid_center[4][:matrix_index] if centroid[4][:matrix_index]

          next unless @cut_symbol

          # move the data_points closest to the centroid centers to the top of the data_items list so that balancing can start early
          @data_set.data_items.insert(0, @data_set.data_items.delete(point_closest_to_centroid_center))

          # correct the distance_from_and_to_depot info of the new cluster with the average of the points
          centroid[4][:duration_from_and_to_depot][index] = @clusters[index].data_items.map{ |d| d[4][:duration_from_and_to_depot][index] }.reduce(&:+) / @clusters[index].data_items.size.to_f
        }

        @iterations += 1
      end

      # Classifies the given data item, returning the cluster index it belongs
      # to (0-based).
      def evaluate(data_item)
        get_min_index(@centroids.collect.with_index{ |centroid, cluster_index|
          dist = distance(data_item, centroid, cluster_index)

          unless @compatibility_function.call(data_item, centroid)
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

        cut_value = @centroids[cluster_index][3][@cut_symbol].to_f
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
        @centroids.each{ |centroid| centroid[3] = Hash.new(0) }
        @clusters = Array.new(@number_of_clusters) do
          Ai4r::Data::DataSet.new data_labels: @data_set.data_labels
        end
        @cluster_indices = Array.new(@number_of_clusters){ [] }

        @total_assigned_cut_load = 0
        @percent_assigned_cut_load = 0
        @apply_balancing = false
        @data_set.data_items.each{ |data_item|
          cluster_index = evaluate(data_item)
          @clusters[cluster_index] << data_item
          update_metrics(data_item, cluster_index)
        }

        manage_empty_clusters if has_empty_cluster?
      end

      def calc_initial_centroids
        @centroids, @old_centroids_lat_lon = [], nil
        if @centroid_indices.empty?
          populate_centroids('random')
        else
          populate_centroids('indices')
        end
      end

      def populate_centroids(populate_method, number_of_clusters = @number_of_clusters)
        # Generate centroids based on remaining_skills available
        # Similarly with data_items, each centroid is defined by :
        #    index 0 : latitude
        #    index 1 : longitude
        #    index 2 : item_id
        #    index 3 : unit_fullfillment -> for each unit, quantity contained in corresponding cluster
        #    index 4 : characterisits -> { v_id: sticky_vehicle_ids, skills: skills, days: day_skills, matrix_index: matrix_index }
        raise ArgumentError, 'No vehicles_infos provided' if @remaining_skills.nil?

        case populate_method
        when 'random'
          while @centroids.length < number_of_clusters
            skills = @remaining_skills.first.dup

            # Find the items which are not already used, and specifically need the skill set of this cluster
            compatible_items = @data_set.data_items.select{ |item|
              !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                !item[4].empty? &&
                !(item[4][:v_id].empty? && item[4][:skills].empty?) &&
                @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
            }

            if compatible_items.empty?
              # If there are no items which specifically needs these skills,
              # then find all the items that can be assigned to this cluster
              compatible_items = @data_set.data_items.select{ |item|
                !@centroids.collect{ |centroid| centroid[2] }.flatten.include?(item[2]) &&
                  @compatibility_function.call(item, [0, 0, 0, 0, skills, 0])
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

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot].collect{ |value| value }
            @centroids << [item[0], item[1], item[2], Hash.new(0), skills]

            @remaining_skills&.delete_at(0)

            @data_set.data_items.insert(0, @data_set.data_items.delete(item))
          end
        when 'indices' # for initial assignment only (with the :centroid_indices option)
          raise ArgumentError, 'Same centroid_index provided several times' if @centroid_indices.size != @centroid_indices.uniq.size

          raise ArgumentError, 'Wrong number of initial centroids provided' if @centroid_indices.size != @number_of_clusters

          insert_at_begining = []
          @centroid_indices.each do |index|
            raise ArgumentError, 'Invalid centroid index' unless (index.is_a? Integer) && index >= 0 && index < @data_set.data_items.length

            skills = @remaining_skills.first.dup
            item = @data_set.data_items[index]
            raise ArgumentError, 'Centroids indices and vehicles_infos do not match' unless @compatibility_function.call(item, [nil, nil, nil, nil, skills])

            skills[:matrix_index] = item[4][:matrix_index]
            skills[:duration_from_and_to_depot] = item[4][:duration_from_and_to_depot].collect{ |value| value }
            @centroids << [item[0], item[1], item[2], Hash.new(0), skills]

            @remaining_skills&.delete_at(0)
            insert_at_begining << item
          end

          insert_at_begining.each{ |i|
            @data_set.data_items.insert(0, @data_set.data_items.delete(i))
          }
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
          @remaining_skills = @vehicles_infos.dup
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
          same_centroid_distance_moving_average(Math.sqrt(@iterations).to_i) || # Check if there is a loop of size Math.sqrt(@iterations)
          (@max_iterations && (@max_iterations <= @iterations))
      end

      private

      def compute_vehicle_work_time_with
        coef = @centroids.map.with_index{ |centroid, index|
          @vehicles_infos[index][:total_work_time] / ([centroid[4][:duration_from_and_to_depot][index], 1].max * @vehicles_infos[index][:total_work_days])
        }.min

        # TODO: The following filter is there to not to affect the existing functionality.
        # However, we should improve the functioanlity and make it less arbitrary.
        coef = if coef > 1.5
                 1.5
               elsif coef > 1.0
                 1.0
               else
                 coef * 0.9 # To make sure the limit will not become 0.
               end

        @centroids.map.with_index{ |centroid, index|
          @vehicles_infos[index][:total_work_time] - coef * centroid[4][:duration_from_and_to_depot][index] * @vehicles_infos[index][:total_work_days]
        }
      end

      def update_cut_limit
        return if @rate_balance == 0.0 || @cut_symbol.nil? || @cut_symbol != :duration || !@cut_limit.is_a?(Array)

        # TODO: This functionality is implemented only for duration cut_symbol. Make sure it doesn't interfere with other cut_symbols
        vehicle_work_time = compute_vehicle_work_time_with
        total_vehicle_work_times = vehicle_work_time.reduce(&:+).to_f
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

        false
      end

      def update_metrics(data_item, cluster_index)
        @unit_symbols.each{ |unit|
          @centroids[cluster_index][3][unit] += data_item[3][unit]

          next if unit != @cut_symbol

          @total_assigned_cut_load += data_item[3][unit]
          @percent_assigned_cut_load = @total_assigned_cut_load / @total_cut_load.to_f
          if !@apply_balancing && @centroids.all?{ |centroid| centroid[3][@cut_symbol].positive? }
            @apply_balancing = true
          end
        }
      end

      def capactity_violation?(item, cluster_index)
        return false if @strict_limitations.empty?

        @centroids[cluster_index][3].any?{ |unit, value|
          value + item[3][unit] > (@strict_limitations[cluster_index][unit] || 0)
        }
      end

      def compatible_characteristics?(service_chars, vehicle_chars)
        # Compatile service and vehicle
        # if the vehicle cannot serve the service due to sticky_vehicle_id
        return false if !service_chars[:v_id].empty? && (service_chars[:v_id] & vehicle_chars[:v_id]).empty?

        # if the service needs a skill that the vehicle doesn't have
        return false if !(service_chars[:skills] - vehicle_chars[:skills]).empty?

        # if service and vehicle have no matching days
        return false if (service_chars[:days] & vehicle_chars[:days]).empty?

        true # if not, they are compatible
      end
    end

    def compute_distance_from_and_to_depot(vehicles_infos, data_set, matrix)
      return if data_set.data_items.all?{ |item| item[4][:duration_from_and_to_depot] }

      data_set.data_items.each{ |point|
        point[4][:duration_from_and_to_depot] = []
      }

      vehicles_infos.each{ |vehicle_info|
        if matrix # matrix_index
          single_index_array = vehicle_info[:depot]
          point_indices = data_set.data_items.map{ |point| point[4][:matrix_index] }
          time_matrix_from_depot = Helper.unsquared_matrix(matrix, single_index_array, point_indices)
          time_matrix_to_depot = Helper.unsquared_matrix(matrix, point_indices, single_index_array)
        else
          items_locations = data_set.data_items.collect{ |point| [point[0], point[1]] }
          time_matrix_from_depot = [items_locations.collect{ |item_location|
            Helper.euclidean_distance(vehicle_info[:depot], item_location)
          }]
          time_matrix_to_depot = items_locations.collect{ |item_location|
            [Helper.euclidean_distance(item_location, vehicle_info[:depot])]
          }
        end

        data_set.data_items.each_with_index{ |point, index|
          point[4][:duration_from_and_to_depot] << time_matrix_from_depot[0][index] + time_matrix_to_depot[index][0]
        }
      }
    end

    def unsquared_matrix(matrix, a_indices, b_indices)
      a_indices.map{ |a|
        b_indices.map { |b|
          matrix[b][a]
        }
      }
    end

    def compute_limits(cut_symbol, cut_ratio, vehicles_infos, data_items, entity = :vehicle)
      cumulated_metrics = Hash.new(0)

      (@unit_symbols || [cut_symbol]).each{ |unit|
        cumulated_metrics[unit.to_sym] = data_items.collect{ |item| item[3][unit] || 0 }.reduce(&:+)
      }

      strict_limits = if vehicles_infos.none?{ |v_i| v_i[:capacities] }
        []
      else
        vehicles_infos.collect{ |cluster|
          s_l = {}
          cumulated_metrics.keys.each{ |unit|
            s_l[unit] = (cluster[:capacities].has_key?(unit) ? cluster[:capacities][unit] : 0)
          }
          s_l
        }
      end

      total_work_time = vehicles_infos.map{ |cluster| cluster[:total_work_time] }.reduce(&:+).to_f
      metric_limits = if entity == :vehicle && total_work_time.positive?
        vehicles_infos.collect{ |cluster|
          { limit: cut_ratio * (cumulated_metrics[cut_symbol].to_f * (cluster[:total_work_time] / total_work_time)) }
        }
      else
        { limit: cut_ratio * (cumulated_metrics[cut_symbol] / vehicles_infos.size) }
      end

      [strict_limits, metric_limits]
    end
  end
end
