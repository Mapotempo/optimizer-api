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
require './util/job_manager.rb'
require 'ai4r'

module Interpreters
  class Dichotomious

    def self.dichotomious_candidate?(service_vrp)
      (service_vrp[:level] && service_vrp[:level] > 0) ||
        (service_vrp[:vrp].vehicles.none?{ |vehicle| vehicle.cost_fixed && !vehicle.cost_fixed.zero? } &&
        service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit &&
        !service_vrp[:vrp].scheduling? &&
        # TODO: We should introduce a new parameter to avoid this static definition
        service_vrp[:vrp].services.size - service_vrp[:vrp].routes.map{ |r| r[:mission_ids].size }.sum > 200 &&
        service_vrp[:vrp].shipments.empty? &&
        # (service_vrp[:vrp].vehicles.all?(&:force_start) || service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle[:shift_preference] == 'force_start' }) &&
        service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle.cost_late_multiplier.nil? || vehicle.cost_late_multiplier == 0 } &&
        service_vrp[:vrp].services.all?{ |service| service.activity.late_multiplier.nil? || service.activity.late_multiplier == 0 } &&
        service_vrp[:vrp].services.any?{ |service| service.activity.timewindows && !service.activity.timewindows.empty? } &&
        service_vrp[:vrp].points.all?{ |point| point.location && point.location.lat && point.location.lon }) #TODO - Remove and use matrix/matrix_index in clustering
    end

    def self.feasible_vrp(result, service_vrp)
      (result.nil? || (result[:unassigned].size != service_vrp[:vrp].services.size || result[:unassigned].any?{ |unassigned| !unassigned[:reason] }))
    end

    def self.dichotomious_heuristic(service_vrp, job = nil, &block)
      if dichotomious_candidate?(service_vrp)
        set_config(service_vrp)
        t1 = Time.now
        # Must be called to be sure matrices are complete in vrp and be able to switch vehicles between sub_vrp
        if service_vrp[:level].zero?
          service_vrp[:vrp].compute_matrix
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
        # Do not solve if vrp has too many vehicles or services - init_duration is set in set_config()
        elsif service_vrp[:vrp].resolution_init_duration.nil?
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
          result = OptimizerWrapper.solve([service_vrp], job, block)
        else
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exlusion_cost(service_vrp)
        end

        t2 = Time.now
        if (result.nil? || result[:unassigned].size >= 0.7 * service_vrp[:vrp].services.size) && feasible_vrp(result, service_vrp) &&
           service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit && service_vrp[:vrp].services.size > 100
          sub_service_vrps = []
          loop do
            sub_service_vrps = split(service_vrp, job)
            break if sub_service_vrps.size == 2
          end
          results = sub_service_vrps.map.with_index{ |sub_service_vrp, index|
            sub_service_vrp[:vrp].resolution_split_number = sub_service_vrps[0][:vrp].resolution_split_number + 1 if !index.zero?
            sub_service_vrp[:vrp].resolution_total_split_number = sub_service_vrps[0][:vrp].resolution_total_split_number if !index.zero?
            if sub_service_vrp[:vrp].resolution_duration
              sub_service_vrp[:vrp].resolution_duration *= sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end
            if sub_service_vrp[:vrp].resolution_minimum_duration
              sub_service_vrp[:vrp].resolution_minimum_duration *= sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end
            result = OptimizerWrapper.define_process([sub_service_vrp], job, &block)
            if index.zero? && result
              transfer_unused_vehicles(result, sub_service_vrps)
              matrix_indices = sub_service_vrps[1][:vrp].points.map{ |point|
                service_vrp[:vrp].points.find{ |r_point| point.id == r_point.id }.matrix_index
              }
              SplitClustering.update_matrix_index(sub_service_vrps[1][:vrp])
              SplitClustering.update_matrix(service_vrp[:vrp].matrices, sub_service_vrps[1][:vrp], matrix_indices)
            end
            result
          }
          service_vrp[:vrp].resolution_split_number = sub_service_vrps[1][:vrp].resolution_split_number
          service_vrp[:vrp].resolution_total_split_number = sub_service_vrps[1][:vrp].resolution_total_split_number
          result = Helper.merge_results(results)
          result[:elapsed] += (t2 - t1) * 1000

          remove_bad_skills(service_vrp, result)
          Interpreters::SplitClustering.remove_empty_routes(result)

          result = end_stage_insert_unassigned(service_vrp, result, job)
          Interpreters::SplitClustering.remove_empty_routes(result)

          if service_vrp[:level].zero?
            # Remove vehicles which are half empty
            Interpreters::SplitClustering.remove_empty_routes(result)
            Interpreters::SplitClustering.remove_poorly_populated_routes(service_vrp[:vrp], result, 0.5)
          end

          log "dicho - level(#{service_vrp[:level]}) unassigned rate #{result[:unassigned].size}/#{service_vrp[:vrp].services.size}: #{(result[:unassigned].size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"
        end
      else
        service_vrp[:vrp].resolution_init_duration = nil
      end
      result
    end

    def self.transfer_unused_vehicles(result, sub_service_vrps)
      result[:routes].each{ |r|
        if r[:activities].select{ |a| a[:service_id] }.empty?
          vehicle = sub_service_vrps[0][:vrp].vehicles.find{ |v| v.id == r[:vehicle_id] }
          sub_service_vrps[1][:vrp].vehicles << vehicle
          sub_service_vrps[0][:vrp].vehicles -= [vehicle]
          sub_service_vrps[1][:vrp].points += sub_service_vrps[0][:vrp].points.select{ |p| p.id == vehicle.start_point_id || p.id == vehicle.end_point_id }
          sub_service_vrps[1][:vrp].resolution_vehicle_limit += 1
        end
      }
      sub_service_vrps[0][:vrp].vehicles.each{ |vehicle|
        next if !result[:routes].select{ |r| r[:vehicle_id] == vehicle.id }.empty?
        sub_service_vrps[1][:vrp].vehicles << vehicle
        sub_service_vrps[0][:vrp].vehicles -= [vehicle]
        sub_service_vrps[1][:vrp].points += sub_service_vrps[0][:vrp].points.select{ |p| p.id == vehicle.start_point_id || p.id == vehicle.end_point_id }
        sub_service_vrps[1][:vrp].resolution_vehicle_limit += 1
      }
    end

    def self.dicho_level_coeff(service_vrp)
      balance = 0.66666
      level_approx = Math.log(service_vrp[:vrp].resolution_dicho_division_vec_limit / (service_vrp[:vrp].resolution_vehicle_limit || service_vrp[:vrp].vehicles.size).to_f, balance)
      service_vrp[:vrp].resolution_dicho_level_coeff = 2**(1 / (level_approx - service_vrp[:level]).to_f)
    end

    def self.set_config(service_vrp)
      # service_vrp[:vrp].resolution_batch_heuristic = true
      service_vrp[:vrp].restitution_allow_empty_result = true
      if service_vrp[:level] && service_vrp[:level] > 0
        service_vrp[:vrp].resolution_duration = service_vrp[:vrp].resolution_duration ? (service_vrp[:vrp].resolution_duration / 2.66).to_i : 80000 # TODO: Time calculation is inccorect due to end_stage. We need a better time limit calculation
        service_vrp[:vrp].resolution_minimum_duration = service_vrp[:vrp].resolution_minimum_duration ? (service_vrp[:vrp].resolution_minimum_duration / 2.66).to_i : 70000
      end

      if service_vrp[:level] && service_vrp[:level] == 0
        dicho_level_coeff(service_vrp)
        service_vrp[:vrp].vehicles.each{ |vehicle|
          vehicle[:cost_fixed] = vehicle[:cost_fixed] && vehicle[:cost_fixed] > 0 ? vehicle[:cost_fixed] : 1e6
          vehicle[:cost_distance_multiplier] = 0.05 if vehicle[:cost_distance_multiplier].zero?
        }
      end

      service_vrp[:vrp].resolution_init_duration = 90000 if service_vrp[:vrp].resolution_duration > 90000
      service_vrp[:vrp].resolution_vehicle_limit ||= service_vrp[:vrp][:vehicles].size
      if service_vrp[:vrp].vehicles.size > service_vrp[:vrp].resolution_dicho_division_vec_limit && service_vrp[:vrp].services.size > 100 &&
         service_vrp[:vrp].resolution_vehicle_limit > service_vrp[:vrp].resolution_dicho_division_vec_limit
        service_vrp[:vrp].resolution_init_duration = 1000
      else
        service_vrp[:vrp].resolution_init_duration = nil
      end
      service_vrp[:vrp].preprocessing_first_solution_strategy = ['parallel_cheapest_insertion'] # A bit slower than local_cheapest_insertion; however, returns better results on ortools-v7.

      service_vrp
    end

    def self.update_exlusion_cost(service_vrp)
      if !service_vrp[:level].zero?
        average_exclusion_cost = service_vrp[:vrp].services.collect{ |service| service.exclusion_cost }.sum / service_vrp[:vrp].services.size
        service_vrp[:vrp].services.each{ |service|
          service.exclusion_cost += average_exclusion_cost * (service_vrp[:vrp].resolution_dicho_level_coeff**service_vrp[:level] - 1)
        }
      end
    end

    def self.build_initial_routes(results)
      results.flat_map{ |result|
        next if result.nil?
        result[:routes].map{ |route|
          next if route.nil?
          mission_ids = route[:activities].map{ |activity| activity[:service_id] || activity[:rest_id] }.compact
          next if mission_ids.empty?
          Models::Route.new(
            vehicle: {
              id: route[:vehicle_id]
            },
            mission_ids: mission_ids
          )
        }
      }.compact
    end

    def self.remove_bad_skills(service_vrp, result)
      result[:routes].each{ |r|
        r[:activities].each{ |a|
          if a[:service_id]
            service = service_vrp[:vrp].services.find{ |s| s.id == a[:service_id] }
            vehicle = service_vrp[:vrp].vehicles.find{ |v| v.id == r[:vehicle_id] }
            if service && !service.skills.empty?
              if vehicle.skills.all?{ |xor_skills| (service.skills & xor_skills).size != service.skills.size }
                result[:unassigned] << a
                r[:activities].delete(a)
              end
            end
            # TODO: remove bad sticky?
          end
        }
      }
    end

    def self.end_stage_insert_unassigned(service_vrp, result, job = nil)
      log "---> dicho::end_stage - level(#{service_vrp[:level]})", level: :debug
      if !result[:unassigned].empty?
        log "try to insert #{result[:unassigned].size} unassigned from #{service_vrp[:vrp].services.size} services"
        service_vrp[:vrp].routes = build_initial_routes([result])
        service_vrp[:vrp].resolution_init_duration = nil
        unassigned_services = service_vrp[:vrp].services.select{ |s| result[:unassigned].map{ |a| a[:service_id] }.include?(s.id) }
        unassigned_services_by_skills = unassigned_services.group_by{ |s| s.skills }
        # TODO: sort unassigned_services with no skill / sticky at the end
        unassigned_services_by_skills.each{ |skills, services|
          next if result[:unassigned].empty?
          vehicles_with_skills = skills.empty? ? service_vrp[:vrp].vehicles : service_vrp[:vrp].vehicles.select{ |v|
            v.skills.any?{ |or_skills| (skills & or_skills).size == skills.size }
          }
          sticky_vehicle_ids = unassigned_services.flat_map(&:sticky_vehicles).compact.map(&:id)
          # In case services has incoherent sticky and skills, sticky is the winner
          unless sticky_vehicle_ids.empty?
            vehicles_with_skills = service_vrp[:vrp].vehicles.select{ |v| sticky_vehicle_ids.include?(v.id) }
          end

          # Shuffle so that existing routes will be distributed randomly
          # Otherwise we might have a sub_vrp with 6 existing routes (no empty routes) and
          # hundreds of services which makes it very hard to insert a point
          # With shuffle we distribute the existing routes accross all sub-vrps we create
          vehicles_with_skills.shuffle!

          #TODO: Here we launch the optim of a single skill however, it make sense to include the vehicles without skills
          #(especially the ones with existing routes) in the sub_vrp because that way optim can move poits between vehicles
          #and serve an unserviced point with skills.

          #TODO: We do not consider the geographic closeness/distance of routes and points.
          #This might be the reason why sometimes we have solutions with long detours.
          #However, it is not very easy to find a generic and effective way.

          sub_results = []
          vehicle_count = skills.empty? && !service_vrp[:vrp].routes.empty? ? [service_vrp[:vrp].routes.size, 6].min : 3
          vehicles_with_skills.each_slice(vehicle_count) do |vehicles|
            remaining_service_ids = result[:unassigned].map{ |u| u[:service_id] } & services.map(&:id)
            next if remaining_service_ids.empty?
            assigned_service_ids = result[:routes].select{ |r| vehicles.map(&:id).include?(r[:vehicle_id]) }.flat_map{ |r| r[:activities].map{ |a| a[:service_id] } }.compact

            sub_service_vrp = SplitClustering.build_partial_service_vrp(service_vrp, remaining_service_ids + assigned_service_ids, vehicles.map(&:id))
            sub_service_vrp[:vrp].vehicles.each{ |vehicle|
              vehicle[:cost_fixed] = vehicle[:cost_fixed] && vehicle[:cost_fixed] > 0 ? vehicle[:cost_fixed] : 1e6
              vehicle[:cost_distance_multiplier] = 0.05 if vehicle[:cost_distance_multiplier].zero?
            }
            rate_vehicles = vehicles.size / vehicles_with_skills.size.to_f
            rate_services = services.size / unassigned_services.size.to_f
            if sub_service_vrp[:vrp].resolution_duration
              sub_service_vrp[:vrp].resolution_duration = [(service_vrp[:vrp].resolution_duration / 3.99 * rate_vehicles * rate_services).to_i, 150].max
            end
            if sub_service_vrp[:vrp].resolution_minimum_duration
              sub_service_vrp[:vrp].resolution_minimum_duration = [(service_vrp[:vrp].resolution_minimum_duration / 3.99 * rate_vehicles * rate_services).to_i, 100].max
            end
            # sub_service_vrp[:vrp].resolution_vehicle_limit = sub_service_vrp[:vrp].vehicles.size
            sub_service_vrp[:vrp].restitution_allow_empty_result = true
            result_loop = OptimizerWrapper.solve([sub_service_vrp], job)
            result[:elapsed] += result_loop[:elapsed] if result_loop && result_loop[:elapsed]

            # Initial routes can be refused... check unassigned size before take into account solution
            if result_loop && remaining_service_ids.size >= result_loop[:unassigned].size
              remove_bad_skills(sub_service_vrp, result_loop)
              result[:unassigned].delete_if{ |unassigned_activity|
                result_loop[:routes].any?{ |route|
                  route[:activities].any?{ |activity| activity[:service_id] == unassigned_activity[:service_id] }
                }
              }
              # result[:unassigned] |= result_loop[:unassigned] # Cannot use | operator because :type field not always present...
              result[:unassigned].delete_if{ |activity| result_loop[:unassigned].map{ |a| a[:service_id] }.include?(activity[:service_id]) }
              result[:unassigned] += result_loop[:unassigned]
              result[:routes].delete_if{ |old_route|
                result_loop[:routes].map{ |r| r[:vehicle_id] }.include?(old_route[:vehicle_id])
              }
              result[:routes] += result_loop[:routes]
              # TODO: merge costs, total_infos...
              sub_results << result_loop
            end
          end
          new_routes = build_initial_routes(sub_results)
          vehicle_ids = sub_results.flat_map{ |r| r[:routes].map{ |route| route[:vehicle_id] } }
          service_vrp[:vrp].routes.delete_if{ |r| vehicle_ids.include?(r.vehicle.id) }
          service_vrp[:vrp].routes += new_routes
        }
      end
      log "<--- dicho::end_stage - level(#{service_vrp[:level]})", level: :debug
      result
    end

    def self.split_vehicles(vrp, services_by_cluster)
      log "---> dicho::split_vehicles #{vrp.vehicles.size}", level: :debug
      services_skills_by_clusters = services_by_cluster.map{ |services|
        services.map{ |s| s.skills.empty? ? nil : s.skills.uniq.sort }.compact.uniq
      }
      log "services_skills_by_clusters #{services_skills_by_clusters}", level: :debug
      vehicles_by_clusters = [[], []]
      vrp.vehicles.each{ |v|
        cluster_index = nil
        # Vehicle skills is an array of array of strings
        unless v.skills.empty?
          # If vehicle has skills which match with service skills in only one cluster, prefer this cluster for this vehicle
          preferered_index = []
          services_skills_by_clusters.each_with_index{ |services_skills, index|
            preferered_index << index if services_skills.any?{ |skills| v.skills.any?{ |v_skills| (skills & v_skills).size == skills.size } }
          }
          cluster_index = preferered_index.first if preferered_index.size == 1
        end
        # TODO: prefer cluster with sticky vehicle
        # TODO: avoid to prefer always same cluster
        if cluster_index &&
           ((vehicles_by_clusters[1].size - 1) / services_by_cluster[1].size > (vehicles_by_clusters[0].size + 1) / services_by_cluster[0].size ||
           (vehicles_by_clusters[1].size + 1) / services_by_cluster[1].size < (vehicles_by_clusters[0].size - 1) / services_by_cluster[0].size)
           cluster_index = nil
        end
        if vehicles_by_clusters[0].empty? || vehicles_by_clusters[1].empty?
          cluster_index ||= vehicles_by_clusters[0].size <= vehicles_by_clusters[1].size ? 0 : 1
        else
          cluster_index ||= services_by_cluster[0].size / vehicles_by_clusters[0].size >= services_by_cluster[1].size / vehicles_by_clusters[1].size ? 0 : 1
        end
        vehicles_by_clusters[cluster_index] << v
      }

      if vehicles_by_clusters.any?(&:empty?)
        empty_side = vehicles_by_clusters.select(&:empty?)[0]
        nonempty_side = vehicles_by_clusters.select(&:any?)[0]

        # Move a vehicle from the skill group with most vehicles (from nonempty side to empty side)
        empty_side << nonempty_side.delete(nonempty_side.group_by{ |v| v.skills.uniq.sort }.to_a.max_by{ |vec_group| vec_group[1].size }.last.first)
      end

      log "<--- dicho::split_vehicles #{vehicles_by_clusters.map(&:size)}", level: :debug
      vehicles_by_clusters
    end

    def self.split(service_vrp, job = nil)
      log "---> dicho::split - level(#{service_vrp[:level]})", level: :debug
      vrp = service_vrp[:vrp]
      vrp.resolution_vehicle_limit ||= vrp.vehicles.size
      services_by_cluster = kmeans(vrp, :duration).sort_by{ |ss| Helper.services_duration(ss) }
      split_service_vrps = []
      if services_by_cluster.size == 2
        # Kmeans return 2 vrps
        vehicles_by_cluster = split_vehicles(vrp, services_by_cluster)
        if vehicles_by_cluster[1].size > vehicles_by_cluster[0].size
          services_by_cluster.reverse
          vehicles_by_cluster.reverse
        end
        [0, 1].each{ |i|
          sub_vrp = SplitClustering.build_partial_service_vrp(service_vrp, services_by_cluster[i].map(&:id), vehicles_by_cluster[i].map(&:id))[:vrp]

          # TODO: à cause de la grande disparité du split_vehicles par skills, on peut rapidement tomber à 1...
          sub_vrp.resolution_vehicle_limit = [sub_vrp.vehicles.size, vrp.vehicles.empty? ? 0 : (sub_vrp.vehicles.size / vrp.vehicles.size.to_f * vrp.resolution_vehicle_limit).ceil].min
          sub_vrp.preprocessing_first_solution_strategy = ['self_selection'] # ???
          sub_vrp.resolution_split_number += i
          sub_vrp.resolution_total_split_number += 1

          split_service_vrps << {
            service: service_vrp[:service],
            vrp: sub_vrp,
            level: service_vrp[:level] + 1
          }
        }
      else
        raise 'Incorrect split size with kmeans' if services_by_cluster.size > 2
        # Kmeans return 1 vrp
        sub_vrp = SplitClustering::build_partial_service_vrp(service_vrp, services_by_cluster[0].map(&:id))[:vrp]
        sub_vrp.points = vrp.points
        sub_vrp.vehicles = vrp.vehicles
        sub_vrp.vehicles.each{ |vehicle|
          vehicle[:cost_fixed] = vehicle[:cost_fixed] && vehicle[:cost_fixed] > 0 ? vehicle[:cost_fixed] : 1e6
        }
        split_service_vrps << {
          service: service_vrp[:service],
          vrp: sub_vrp,
          level: service_vrp[:level]
        }
      end
      OutputHelper::Clustering.generate_files(split_service_vrps) if OptimizerWrapper.config[:debug][:output_clusters]

      log "<--- dicho::split - level(#{service_vrp[:level]})", level: :debug
      split_service_vrps
    end

    # TODO: remove this method and use SplitClustering class instead
    def self.kmeans(vrp, cut_symbol)
      nb_clusters = 2
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service[:activity] }
        unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration << :visits
        cumulated_metrics = Hash.new(0)
        data_items = []

        # Collect data for kmeans
        vrp.points.each{ |point|
          unit_quantities = Hash.new(0)
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
            data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, [], [], 0]
          }
        }

        # No expected caracteristics neither strict limitations because we do not
        # know which vehicles will be used in advance
        options = { max_iterations: 100, restarts: 5, cut_symbol: cut_symbol, last_iteration_balance_rate: 0.0 }
        limits = { metric_limit: { limit: cumulated_metrics[cut_symbol] / nb_clusters },
                   strict_limit: {}}

        clusters, _centroid_indices = SplitClustering.kmeans_process([], nb_clusters, data_items, unit_symbols, limits, options)

        services_by_cluster = clusters.collect{ |cluster|
          cluster.data_items.collect{ |data|
            vrp.services.find{ |service| service.activity.point_id == data[2] }
          }
        }
        services_by_cluster
      else
        log 'Split not available when services have no activities', level: :error
        [vrp]
      end
    end
  end
end
