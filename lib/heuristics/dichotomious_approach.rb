# Copyright © Mapotempo, 2019
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

require './lib/interpreters/split_clustering.rb'
require './lib/clusterers/balanced_kmeans.rb'
require './lib/tsp_helper.rb'
require './lib/helper.rb'
require 'ai4r'

module Interpreters
  class Dichotomious

    def self.dichotomious_candidate(service_vrp)
      service_vrp[:vrp].vehicles.size > 1 &&
      service_vrp[:vrp].shipments.empty? &&
      (service_vrp[:vrp].vehicles.all?(&:force_start) || service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle[:shift_preference] == 'force_start' }) &&
      service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle.cost_late_multiplier.nil? || vehicle.cost_late_multiplier == 0 } &&
      service_vrp[:vrp].services.all?{ |service| service.activity.late_multiplier.nil? || service.activity.late_multiplier == 0 } &&
      service_vrp[:vrp].services.any?{ |service| service.activity.timewindows && !service.activity.timewindows.empty? }
    end

    def self.merge_results(results)
      results.flatten!
      {
        solvers: results.flat_map{ |r| r && r[:solvers] }.compact,
        cost: results.map{ |r| r && r[:cost] }.compact.reduce(&:+),
        routes: results.flat_map{ |r| r && r[:routes] }.compact,
        unassigned: results.flat_map{ |r| r && r[:unassigned] }.compact.uniq,
        elapsed: results.map{ |r| r && r[:elapsed] || 0 }.reduce(&:+),
        total_time: results.map{ |r| r && r[:total_travel_time] }.compact.reduce(&:+),
        total_value: results.map{ |r| r && r[:total_travel_value] }.compact.reduce(&:+),
        total_distance: results.map{ |r| r && r[:total_distance] }.compact.reduce(&:+)
      }
    end

    def self.dichotomious_heuristic(service_vrp, block = nil)
      if dichotomious_candidate(service_vrp)
        single_vrp = Marshal::load(Marshal.dump(service_vrp))
        create_config(single_vrp)
        result = OptimizerWrapper::solve([single_vrp])

        if result.nil?
          old_centroids = []
          sub_service_vrp = []
          loop do
            sub_service_vrp, centroid_indices = split(single_vrp, old_centroids.compact)
            old_centroids += Marshal::load(Marshal.dump(centroid_indices)) if centroid_indices
            break if sub_service_vrp.size == 2
          end
          results = sub_service_vrp.collect{ |lonely_vrp|
            OptimizerWrapper::define_process([lonely_vrp])
          }
          result = merge_results(results)
        end
        build_route(service_vrp, [result])
        [service_vrp[:vrp].routes, result]
      end
    end

    def self.create_config(service_vrp)
      # service_vrp[:vrp].resolution_batch_heuristic = true
      service_vrp[:vrp].restitution_allow_empty_result = true
      service_vrp[:vrp].resolution_duration = service_vrp[:vrp].resolution_duration ? service_vrp[:vrp].resolution_duration / 2 : 120000
      service_vrp[:vrp].resolution_minimum_duration = service_vrp[:vrp].resolution_minimum_duration ? service_vrp[:vrp].resolution_minimum_duration / 2 : 90000
      service_vrp[:vrp].resolution_init_duration = 45000
      service_vrp[:vrp].preprocessing_first_solution_strategy = ['local_cheapest_insertion']

      service_vrp
    end

    def self.build_route(service_vrp, results)
      routes = results.collect{ |result|
        result[:routes].collect{ |route|
          next if route[:activities].empty?
          {
            vehicle: {
              id: route[:vehicle_id]
            },
            mission_ids: route[:activities].select{ |activity| activity[:service_id] || activity[:rest_id] }.collect{ |activity|
              activity[:service_id] || activity[:rest_id]
            }
          }
        }
      }.flatten.compact
      service_vrp[:vrp].routes = routes
    end

    def self.build_services_vrps(services_vrps, routes)
      all_services_vrps = []
      while !routes.empty?
        service_vrp = Marshal.load(Marshal.dump(services_vrps[0]))
        service_vrp[:vrp].services = []
        service_vrp[:vrp].vehicles = []
        service_vrp[:vrp].routes = []
        while service_vrp[:vrp].vehicles.size < 3 && !routes.empty?
          service_vrp[:vrp].services += routes.first[:mission_ids].collect{ |mission| services_vrps[0][:vrp].services.find{ |service| service.id == mission }}
          service_vrp[:vrp].vehicles += [routes.first.vehicle.id].collect{ |id| services_vrps[0][:vrp].vehicles.find{ |vehicle| vehicle.id == id }}
          service_vrp[:vrp].routes += [routes.first]
          routes -= [routes.first]
        end
        all_services_vrps += [service_vrp]
      end

      all_services_vrps
    end

    def self.third_stage(services_vrps, results)
      result_inter = []
      unassigned_inter = []
      unassigned = results.collect{ |result| result[:unassigned] }.flatten

      if unassigned.size != 0 && dichotomious_candidate(services_vrps[0])
        build_route(services_vrps[0], results)
        services_vrps[0][:vrp].routes.delete_if{ |route| route[:mission_ids].empty? }
        all_services_vrps = build_services_vrps(services_vrps, services_vrps[0][:vrp].routes)
        all_services_vrps.each{ |service_vrp|
          service_vrp[:vrp].routes.delete_if{ |route| route[:mission_ids].empty? }
          service_vrp[:vrp].vehicles.each{ |vehicle|
            vehicle[:free_approach] = true
          }
          service_vrp[:vrp].services += unassigned.collect{ |una| services_vrps[0][:vrp].services.find{ |service| una[:service_id] == service.id }}
          service_vrp[:vrp].services.uniq
          service_vrp[:vrp].points = service_vrp[:vrp].services.collect{ |service| service.activity.point }
          service_vrp[:vrp].points += service_vrp[:vrp].vehicles.collect{ |vehicle| vehicle.start_point }.compact
          service_vrp[:vrp].points += service_vrp[:vrp].vehicles.collect{ |vehicle| vehicle.end_point }.compact
          service_vrp[:vrp].resolution_duration = 60000
          service_vrp[:vrp].resolution_minimum_duration = 30000
          service_vrp[:vrp].resolution_vehicle_limit = service_vrp[:vrp].vehicles.size
          service_vrp[:vrp].preprocessing_first_solution_strategy = ['local_cheapest_insertion']

          result_inter += [OptimizerWrapper::solve([service_vrp])]
          result_inter = [merge_results(result_inter)]
          unassigned = result_inter.collect{ |result| result[:unassigned] }.flatten if !result_inter.empty?
        }

        result_inter[0]
      else
        results[0]
      end
    end

    def self.build_incompatibility_set(vrp)
      skills = vrp.vehicles.collect{ |vehicle| vehicle[:skills].first }
      skills.each{ |skill_1|
        skills.each{ |skill_2|
          if skill_1 != skill_2 && !(skill_1 & skill_2).empty?
            skill_first = skill_1
            skill_second = skill_2
            next if (skill_first & skill_second).size == skill_first.size
            skills.delete(skill_first)
            skill_first |= skill_second
            skills << skill_first
            skills.delete(skill_second)
          end
        }
      }
      skills
    end

    def self.extract(vehicles, vehicles_skills)
     vehicles_skills.collect{ |skill|
       vehicle_index = vehicles.find_index{ |vehicle| vehicle.skills.first.include?(skill) }
       vehicles.slice!(vehicle_index) if vehicle_index
     }.compact
    end

    def self.split_vehicle(service_vrp)
      vrp = service_vrp[:vrp]
      skills = build_incompatibility_set(vrp)
      # Represent a matrix of vehicle skills
      matrices_cluster = []
      skills.uniq.each{ |skill|
        matrices_skill = []
        vrp.vehicles.each{ |vehicle|
          if vehicle[:skills].include?(skill)
            matrices_skill << skill.first
          end
        }
        matrices_cluster << matrices_skill
      }
      vehicles_skills_1 = []
      vehicles_skills_2 = []

      # Distribute vehicle equally
      matrices_cluster.each_with_index{ |matrice_cluster, index|
        size = matrice_cluster.size
        rounded_mean = vehicles_skills_1.size > vehicles_skills_2.size ? (size/2.0).floor : (size/2.0).ceil
        if size == 1
          vehicles_skills_1 += [matrice_cluster[0]] if rounded_mean == 0
          vehicles_skills_2 += [matrice_cluster[0]] if rounded_mean != 0
        else
          vehicles_skills_1 += matrice_cluster[0..rounded_mean-1]
          vehicles_skills_2 += matrice_cluster[rounded_mean..-1]
        end
      }
      vehicles = Marshal.load(Marshal.dump(vrp.vehicles))
      vehicles_vrp_1 = extract(vehicles, vehicles_skills_1.compact)
      vehicles_vrp_2 = extract(vehicles, vehicles_skills_2.compact)
      [vehicles_vrp_1, vehicles_vrp_2]
    end

    def self.spread_vehicle(vrp, sub_first, sub_second, vehicles_splited)
      sub_first.vehicles = vehicles_splited[0]
      sub_second.vehicles = vehicles_splited[1]
      while sub_first.resolution_vehicle_limit + sub_second.resolution_vehicle_limit != (vrp.resolution_vehicle_limit)
        if sub_first.resolution_vehicle_limit + sub_second.resolution_vehicle_limit < (vrp.resolution_vehicle_limit)
          sub_second.resolution_vehicle_limit += 1
        else
          sub_first.resolution_vehicle_limit -= 1
        end
      end
    end

    def self.split(service_vrp, centroid_indices = nil)
      vrp = service_vrp[:vrp]
      vehicles_splited = split_vehicle(service_vrp)
      vehicles_splited = vehicles_splited.sort_by!{ |vehicles| vehicles.size }
      result_cluster, centroid_indices = kmeans(service_vrp, vehicles_splited, :duration, centroid_indices)
      if result_cluster.compact.size != 1
        # Kmeans return 2 vrps
        vrp.resolution_vehicle_limit = vrp.vehicles.size if !vrp.resolution_vehicle_limit
        sub_service_first = SplitClustering::build_partial_service_vrp(vrp, result_cluster[0])
        sub_first = sub_service_first[:vrp]
        sub_first.points = vrp.points
        sub_first.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (sub_first.services.size.to_f / vrp.services.size.to_f)).to_i
        sub_first.preprocessing_first_solution_strategy = ['self_selection']

        sub_service_second = SplitClustering::build_partial_service_vrp(vrp, result_cluster[1])
        sub_second = sub_service_second[:vrp]
        sub_second.points = vrp.points
        sub_second.resolution_vehicle_limit = ((vrp.resolution_vehicle_limit || vrp.vehicles.size) * (sub_second.services.size.to_f / vrp.services.size.to_f)).to_i
        sub_second.preprocessing_first_solution_strategy = ['self_selection']

        # Spread vehicle and vehicle limit for sub_first and sub_second
        if sub_first.services.size < sub_second.services.size
          spread_vehicle(vrp, sub_first, sub_second, vehicles_splited)
        else
          spread_vehicle(vrp, sub_second, sub_first, vehicles_splited)
        end

        sub_first.vehicles.each{ |vehicle|
          vehicle[:free_approach] = true
          vehicle[:cost_fixed] = vehicle[:cost_fixed] || 100000000
        }
        sub_second.vehicles.each{ |vehicle|
          vehicle[:free_approach] = true
          vehicle[:cost_fixed] = vehicle[:cost_fixed] || 100000000
        }

        sub_service_vrps = [sub_service_first]
        sub_service_vrps << sub_service_second if sub_service_second

      else
        # Kmeans return 1 vrp
        sub_service_first = SplitClustering::build_partial_service_vrp(vrp, result_cluster[0])
        sub_first = sub_service_first[:vrp]
        sub_first.points = vrp.points
        sub_first.vehicles = vehicles_splited[0] + vehicles_splited[1]
        sub_first.vehicles.each{ |vehicle|
          vehicle[:free_approach] = true
          vehicle[:cost_fixed] = 100000
        }
        sub_service_vrps = [sub_service_first]
      end

      [sub_service_vrps, centroid_indices]
    end

    def self.kmeans(services_vrps, vehicles, cut_symbol, old_centroids = nil)
      vrp = services_vrps[:vrp]
      nb_clusters = 2
      cut_symbol = :duration
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] }
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        cumulated_metrics = {}
        unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }
        data_items = []

        # Collect data for kmeans
        vrp.points.each{ |point|
          unit_quantities = {}
          unit_symbols.each{ |unit| unit_quantities[unit] = 0 }
          related_services = vrp.services.select{ |service| service[:activity][:point_id] == point[:id] }
          related_services.each{ |service|
            unit_quantities[:visits] += 1
            cumulated_metrics[:visits] += 1
            unit_quantities[:duration] += service[:activity][:duration]
            cumulated_metrics[:duration] += service[:activity][:duration]
            service.quantities.each{ |quantity|
              unit_quantities[quantity.unit_id.to_sym] += quantity.value
              cumulated_metrics[quantity.unit_id.to_sym] += quantity.value
            }
          }

          next if related_services.empty?
          related_services.each{ |related_service|
            if related_service[:sticky_vehicle_ids] && related_service[:skills] && !related_service[:skills].empty?
              data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, related_service[:sticky_vehicle_ids], related_service[:skills], nil]
            elsif related_service[:sticky_vehicle_ids] && related_service[:skills] && related_service[:skills].empty?
                data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, related_service[:sticky_vehicle_ids], nil, nil]
            elsif related_service[:skills] && !related_service[:skills].empty? && !related_service[:sticky_vehicle_ids]
              data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, related_service[:skills], nil]
            else
              data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, nil, nil]
            end
          }
        }

        start_timer = Time.now
        # Consider only one sticky vehicle
        centroid_indices = []
        skills = []
        vehicles.each_with_index{ |vehicle_c, index|
          skills << vehicles[index].collect{ |vehicle| vehicle[:skills].first }
        }
        skills.flatten
        data_for = Marshal.load(Marshal.dump(data_items))

        # Collect centroids if we have to split again
        if data_items.any?{ |data| data[5] } && !skills.empty?
          skills.each{ |skill|
            data = nil
            if old_centroids
              data = data_for.find{ |data| data[5] && (skill.flatten.uniq & data[5]).size > skill.flatten.uniq.size - 1 && !old_centroids.include?(data_items.index(data)) }
            else
              data = data_for.find{ |data| data[5] && (skill.flatten.uniq & data[5]).size > skill.flatten.uniq.size - 1 }
            end

            centroid_indices << data_items.index(data) if data
            data_for = data_for - [data] if data
            # data_items[centroid_indices.last][5] = skill.flatten.uniq if data
          }
        else
          centroid_indices = (vrp[:preprocessing_kmeans_centroids] && vrp[:preprocessing_kmeans_centroids].size == nb_clusters) ? vrp[:preprocessing_kmeans_centroids] : []
        end
        clusters = SplitClustering::kmeans_process(centroid_indices, 200, 30, nb_clusters, data_items, unit_symbols, cut_symbol, cumulated_metrics[cut_symbol] / nb_clusters, vrp, nil)
        end_timer = Time.now

        result = clusters.collect{ |cluster|
          cluster.data_items.collect{ |data|
            vrp.services.find{ |service| service.activity.point_id == data[2] }.id
          }
        }
        [result, centroid_indices]
      else
        puts "split hierarchical not available when services have activities"
        [vrp]
      end
    end
  end
end
