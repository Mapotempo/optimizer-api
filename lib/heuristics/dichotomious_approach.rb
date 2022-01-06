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
require './lib/tsp_helper.rb'
require './lib/helper.rb'
require './util/job_manager.rb'

module Interpreters
  class Dichotomious
    def self.dichotomious_candidate?(service_vrp)
      service_vrp[:dicho_level]&.positive? ||
        (
          # TODO: remove cost_fixed condition after exclusion cost calculation is corrected.
          service_vrp[:vrp].vehicles.none?{ |vehicle| vehicle.cost_fixed && !vehicle.cost_fixed.zero? } &&
          service_vrp[:vrp].vehicles.size > service_vrp[:vrp].configuration.resolution.dicho_algorithm_vehicle_limit &&
          (service_vrp[:vrp].configuration.resolution.vehicle_limit.nil? ||
            service_vrp[:vrp].configuration.resolution.vehicle_limit > service_vrp[:vrp].configuration.resolution.dicho_algorithm_vehicle_limit) &&
          service_vrp[:vrp].services.size - service_vrp[:vrp].routes.map{ |r| r.mission_ids.size }.sum >
            service_vrp[:vrp].configuration.resolution.dicho_algorithm_service_limit &&
          !service_vrp[:vrp].schedule? &&
          service_vrp[:vrp].points.all?{ |point| point&.location&.lat && point&.location&.lon } &&
          service_vrp[:vrp].relations.empty?
        )
    end

    def self.feasible_vrp(solution, service_vrp)
      solution.nil? || solution.count_unassigned_services != service_vrp[:vrp].services.size ||
        solution.unassigned.reject(&:reason).any?
    end

    def self.dichotomious_heuristic(service_vrp, job = nil, &block)
      if dichotomious_candidate?(service_vrp)
        vrp = service_vrp[:vrp]
        message = "dicho - level(#{service_vrp[:dicho_level]}) "\
                  "activities: #{vrp.services.size} "\
                  "vehicles (limit): #{vrp.vehicles.size}(#{vrp.configuration.resolution.vehicle_limit})"\
                  "duration [min, max]: [#{vrp.configuration.resolution.minimum_duration&.round},#{vrp.configuration.resolution.duration&.round}]"
        log message, level: :info

        set_config(service_vrp)

        # Must be called to be sure matrices are complete in vrp and be able to switch vehicles between sub_vrp
        if service_vrp[:dicho_level].zero?
          service_vrp[:vrp].compute_matrix
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exclusion_cost(service_vrp)
        # Do not solve if vrp has too many vehicles or services - init_duration is set in set_config()
        elsif service_vrp[:vrp].configuration.resolution.init_duration.nil?
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exclusion_cost(service_vrp)
          solution = OptimizerWrapper.solve(service_vrp, job, block)
        else
          service_vrp[:vrp].calculate_service_exclusion_costs(:time, true)
          update_exclusion_cost(service_vrp)
        end

        if (solution.nil? || solution.unassigned.size >= 0.7 * service_vrp[:vrp].services.size) &&
           feasible_vrp(solution, service_vrp) &&
           service_vrp[:vrp].vehicles.size > service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit &&
           service_vrp[:vrp].services.size > service_vrp[:vrp].configuration.resolution.dicho_division_service_limit
          sub_service_vrps = []

          3.times do # TODO: move this logic inside the split function
            sub_service_vrps = split(service_vrp, job)
            break if sub_service_vrps.size == 2
          end

          # TODO: instead of an error, we can just continue the optimisation in the child process
          # by modifying the configuration.resolution.dicho_division_X_limit's here so that the child runs the
          # optimisation instead of trying to split again
          raise 'dichotomious_heuristic cannot split the problem into two clusters' if sub_service_vrps.size != 2

          solutions = sub_service_vrps.map.with_index{ |sub_service_vrp, index|
            unless index.zero?
              sub_service_vrp[:vrp].configuration.resolution.split_number = sub_service_vrps[0][:vrp].configuration.resolution.split_number + 1
              sub_service_vrp[:vrp].configuration.resolution.total_split_number =
                sub_service_vrps[0][:vrp].configuration.resolution.total_split_number
            end
            if sub_service_vrp[:vrp].configuration.resolution.duration
              sub_service_vrp[:vrp].configuration.resolution.duration *=
                sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end
            if sub_service_vrp[:vrp].configuration.resolution.minimum_duration
              sub_service_vrp[:vrp].configuration.resolution.minimum_duration *=
                sub_service_vrp[:vrp].services.size / service_vrp[:vrp].services.size.to_f * 2
            end

            solution = OptimizerWrapper.define_process(sub_service_vrp, job, &block)

            transfer_unused_vehicles(service_vrp, solution, sub_service_vrps) if index.zero? && solution

            solution
          }
          service_vrp[:vrp].configuration.resolution.split_number = sub_service_vrps[1][:vrp].configuration.resolution.split_number
          service_vrp[:vrp].configuration.resolution.total_split_number = sub_service_vrps[1][:vrp].configuration.resolution.total_split_number
          solution = solutions.reduce(&:+)
          log "dicho - level(#{service_vrp[:dicho_level]}) before remove_bad_skills unassigned rate " \
              "#{solution.unassigned.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%", level: :debug

          remove_bad_skills(service_vrp, solution)
          Interpreters::SplitClustering.remove_empty_routes(solution)
          solution.parse(vrp)
          log "dicho - level(#{service_vrp[:dicho_level]}) before end_stage_insert  unassigned rate " \
              "#{solution.unassigned.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%", level: :debug

          solution = end_stage_insert_unassigned(service_vrp, solution, job)
          Interpreters::SplitClustering.remove_empty_routes(solution)

          if service_vrp[:dicho_level].zero?
            # Remove vehicles which are half empty
            log "dicho - before remove_poorly_populated_routes: #{solution.routes.size}", level: :debug
            Interpreters::SplitClustering.remove_poorly_populated_routes(service_vrp[:vrp], solution, 0.5)
            log "dicho - after remove_poorly_populated_routes: #{solution.routes.size}", level: :debug
          end
          solution.parse(vrp)


          log "dicho - level(#{service_vrp[:dicho_level]}) unassigned rate " \
              "#{solution.unassigned.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"
        end
      else
        service_vrp[:vrp].configuration.resolution.init_duration = nil
      end
      solution
    end

    def self.transfer_unused_vehicles(service_vrp, solution, sub_service_vrps)
      original_vrp = service_vrp[:vrp]
      sv_zero = sub_service_vrps[0][:vrp]
      sv_one = sub_service_vrps[1][:vrp]
      original_matrix_indices = nil

      # Transfer the vehicles which do not appear in the routes or the empty vehicles that appear in the routes
      sv_zero.vehicles.each{ |vehicle|
        route = solution.routes.find{ |r| r.vehicle.id == vehicle.id }

        next if route&.stops&.any?(&:service_id)

        sv_one.vehicles << vehicle
        sv_zero.vehicles -= [vehicle]
        vehicle_points = [vehicle.start_point, vehicle.end_point].compact.uniq

        update_sv_one_matrix(sv_one, original_vrp, original_matrix_indices, vehicle, vehicle_points)
      }

      # Transfer unsued vehicle limit to the other side as well
      sv_zero_unused_vehicle_limit = sv_zero.configuration.resolution.vehicle_limit - solution.count_used_routes
      sv_one.configuration.resolution.vehicle_limit += sv_zero_unused_vehicle_limit
    end

    def self.update_sv_one_matrix(sv_one, original_vrp, original_matrix_indices, vehicle, vehicle_points)
      vehicle_points.each{ |new_point|
        point_exists = sv_one.points.find{ |p| p.id == new_point.id }

        if point_exists
          vehicle.start_point = point_exists if vehicle.start_point_id == new_point.id
          vehicle.end_point = point_exists if vehicle.end_point_id == new_point.id
          next
        end

        new_point.matrix_index = sv_one.points.size

        original_matrix_indices ||= sv_one.points.map{ |p| original_vrp.points.find{ |pi| pi.id == p.id }.matrix_index }
        new_point_original_matrix_index = original_vrp.points.find{ |pi| pi.id == new_point.id }.matrix_index

        # Update the matrix
        sv_one.matrices.each_with_index{ |sv_one_matrix, m_index|
          %i[time distance value].each{ |dimension|
            d_matrix = sv_one_matrix.send(dimension)
            next unless d_matrix

            original_matrix = original_vrp.matrices[m_index].send(dimension)

            # existing points to new_point
            d_matrix.each_with_index{ |row, r_index|
              row << original_matrix[original_matrix_indices[r_index]][new_point_original_matrix_index]
            }
            # new_point to existing points
            d_matrix << original_matrix[new_point_original_matrix_index].values_at(*original_matrix_indices)
            # new_point to new_point
            d_matrix.last << 0
          }
        }

        original_matrix_indices << new_point_original_matrix_index
        sv_one.points << new_point
      }
    end

    def self.dicho_level_coeff(service_vrp)
      balance = 0.66666
      level_approx = Math.log(service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit /
                    (service_vrp[:vrp].configuration.resolution.vehicle_limit || service_vrp[:vrp].vehicles.size).to_f, balance)
      service_vrp[:vrp].configuration.resolution.dicho_level_coeff = 2**(1 / (level_approx - service_vrp[:dicho_level]).to_f)
    end

    def self.set_config(service_vrp)
      # service_vrp[:vrp].configuration.resolution.batch_heuristic = true
      service_vrp[:vrp].configuration.restitution.allow_empty_result = true
      if service_vrp[:dicho_level]&.positive?
        # TODO: Time calculation is inccorect due to end_stage. We need a better time limit calculation
        service_vrp[:vrp].configuration.resolution.duration =
          service_vrp[:vrp].configuration.resolution.duration ? (service_vrp[:vrp].configuration.resolution.duration / 2.66).to_i : 80000
        service_vrp[:vrp].configuration.resolution.minimum_duration =
          service_vrp[:vrp].configuration.resolution.minimum_duration ?
            (service_vrp[:vrp].configuration.resolution.minimum_duration / 2.66).to_i : 70000
      end

      if service_vrp[:dicho_level]&.zero?
        dicho_level_coeff(service_vrp)
        service_vrp[:vrp].vehicles.each{ |vehicle|
          vehicle[:cost_fixed] = vehicle[:cost_fixed]&.positive? ? vehicle[:cost_fixed] : 1e6
          vehicle[:cost_distance_multiplier] = 0.05 if vehicle[:cost_distance_multiplier].zero?
        }
      end

      service_vrp[:vrp].configuration.resolution.init_duration = 90000 if service_vrp[:vrp].configuration.resolution.duration > 90000
      service_vrp[:vrp].configuration.resolution.vehicle_limit ||= service_vrp[:vrp][:vehicles].size
      service_vrp[:vrp].configuration.resolution.init_duration =
        if service_vrp[:vrp].vehicles.size > service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit &&
           service_vrp[:vrp].services.size > service_vrp[:vrp].configuration.resolution.dicho_division_service_limit &&
           service_vrp[:vrp].configuration.resolution.vehicle_limit > service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit
          1000
        end
      # A bit slower than local_cheapest_insertion; however, returns better results on ortools-v7.
      service_vrp[:vrp].configuration.preprocessing.first_solution_strategy = ['parallel_cheapest_insertion']

      service_vrp
    end

    def self.update_exclusion_cost(service_vrp)
      return if service_vrp[:dicho_level].zero?

      average_exclusion_cost = service_vrp[:vrp].services.sum(&:exclusion_cost) / service_vrp[:vrp].services.size
      service_vrp[:vrp].services.each{ |service|
        service.exclusion_cost += average_exclusion_cost * (service_vrp[:vrp].configuration.resolution.dicho_level_coeff**service_vrp[:dicho_level] - 1)
      }
    end

    def self.build_initial_routes(solutions)
      solutions.flat_map{ |solution|
        next if solution.nil?

        solution.routes.map{ |route|
          mission_ids = route.stops.map(&:service_id).compact
          next if mission_ids.empty?

          Models::Route.create(
            vehicle: route.vehicle,
            mission_ids: mission_ids
          )
        }
      }.compact
    end

    def self.remove_bad_skills(service_vrp, solution)
      log '---> remove_bad_skills', level: :debug
      solution.routes.each{ |r|
        r.stops.each{ |a|
          next unless a.service_id

          service = service_vrp[:vrp].services.find{ |s| s.id == a.service_id }
          next unless service && !service.skills.empty?

          next unless r.vehicle.skills.all?{ |xor_skills| (service.skills & xor_skills).size != service.skills.size }

          log "dicho - removed service #{a.service_id} from vehicle #{r.vehicle.id}"
          solution.unassigned << a
          r.stops.delete(a)
          # TODO: remove bad sticky?
        }
      }
      log '<--- remove_bad_skills', level: :debug
    end

    def self.insert_unassigned_by_skills(service_vrp, unassigned_services, unassigned_with_skills,
                                         skills, solution, transfer_unused_time_limit)
      vrp = service_vrp[:vrp]
      log "try to insert #{unassigned_with_skills.size} unassigned from #{vrp.services.size} services"
      vrp.routes = build_initial_routes([solution])
      vrp.configuration.resolution.init_duration = nil

      vehicles_with_skills = vrp.vehicles.map.with_index{ |vehicle, v_index|
        r_index = solution.routes.index{ |route| route.vehicle.id == vehicle.id }
        compatible = if skills.any?
                       vehicle.skills.any?{ |or_skills| (skills & or_skills).size == skills.size }
                     else
                       true
                     end
        [vehicle.id, r_index, v_index] if compatible
      }.compact

      # Shuffle so that existing routes will be distributed randomly
      # Otherwise we might have a sub_vrp with 6 existing routes (no empty routes) and
      # hundreds of services which makes it very hard to insert a point
      # With shuffle we distribute the existing routes accross all sub-vrps we create
      vehicles_with_skills.shuffle!

      # TODO: Here we launch the optim of a single skill however, it make sense to include the vehicles
      # without skills (especially the ones with existing routes) in the sub_vrp because that way optim
      # can move points between vehicles and serve an unserviced point with skills.

      # TODO: We do not consider the geographic closeness/distance of routes and points.
      # This might be the reason why sometimes we have solutions with long detours.
      # However, it is not very easy to find a generic and effective way.

      sub_solutions = []
      vehicle_count = (skills.empty? && !vrp.routes.empty?) ? [vrp.routes.size, 6].min : 3
      impacted_routes = []
      vehicles_with_skills.each_slice(vehicle_count) do |vehicles_indices|
        remaining_service_ids = solution.unassigned.map(&:service_id) & unassigned_with_skills.map(&:id)
        next if remaining_service_ids.empty?

        rate_vehicles = vehicles_indices.size / vehicles_with_skills.size.to_f
        rate_services = unassigned_services.empty? ? 1 : unassigned_with_skills.size / unassigned_services.size.to_f

        sub_vrp_configuration_resolution_duration =
          [(vrp.configuration.resolution.duration.to_f / 3.99 * rate_vehicles * rate_services + transfer_unused_time_limit).to_i, 150].max
        sub_vrp_configuration_resolution_minimum_duration =
          [(vrp.configuration.resolution.minimum_duration.to_f / 3.99 * rate_vehicles * rate_services).to_i, 100].max

        used_vehicle_count = vehicles_indices.size

        if vrp.configuration.resolution.vehicle_limit
          sub_vrp_vehicle_limit = @leftover_vehicle_limit + used_vehicle_count
          if sub_vrp_vehicle_limit&.zero? # The vehicle limit is hit cannot use more new vehicles...
            transfer_unused_time_limit = sub_vrp_configuration_resolution_duration
            next
          end
        end

        assigned_service_ids = vehicles_indices.map{ |_v, r_i, _v_i| r_i }.compact.flat_map{ |r_i|
          solution.routes[r_i].stops.map(&:service_id)
        }.compact

        sub_service_vrp = SplitClustering.build_partial_service_vrp(service_vrp,
                                                                    remaining_service_ids + assigned_service_ids,
                                                                    vehicles_indices.map{ |_v, _r_i, v_i| v_i })
        sub_vrp = sub_service_vrp[:vrp]
        sub_vrp.vehicles.each{ |vehicle|
          impacted_routes << vehicle.id
          vehicle.cost_fixed = vehicle.cost_fixed&.positive? ? vehicle.cost_fixed : 1e6
          vehicle.cost_distance_multiplier = 0.05 if vehicle.cost_distance_multiplier.zero?
        }

        sub_vrp.configuration.resolution.minimum_duration = sub_vrp_configuration_resolution_minimum_duration if sub_vrp.configuration.resolution.minimum_duration
        sub_vrp.configuration.resolution.duration = sub_vrp_configuration_resolution_duration if sub_vrp.configuration.resolution.duration
        sub_vrp.configuration.resolution.vehicle_limit = sub_vrp_vehicle_limit  if vrp.configuration.resolution.vehicle_limit

        sub_vrp.configuration.restitution.allow_empty_result = true
        solution_loop = OptimizerWrapper.solve(sub_service_vrp)

        next unless solution_loop

        solution.elapsed += solution_loop.elapsed.to_f
        transfer_unused_time_limit = sub_vrp.configuration.resolution.duration - solution_loop.elapsed.to_f

        # TODO: Remove unnecessary if conditions and .nil? checks
        # Initial routes can be refused... check unassigned size before take into account solution
        next if remaining_service_ids.size < solution_loop.unassigned.size

        if vrp.configuration.resolution.vehicle_limit # correct the lefover vehicle limit count
          @leftover_vehicle_limit -=
            solution_loop.count_used_routes - used_vehicle_count
        end

        remove_bad_skills(sub_service_vrp, solution_loop)

        Helper.replace_routes_in_result(solution, solution_loop)
        solution.parse(vrp)
        sub_solutions << solution_loop
      end
      new_routes = build_initial_routes(sub_solutions)
      vrp.routes.delete_if{ |r| impacted_routes.include?(r.vehicle_id) }
      vrp.routes += new_routes
    end

    def self.end_stage_insert_unassigned(service_vrp, solution, job = nil)
      log "---> dicho::end_stage - level(#{service_vrp[:dicho_level]})", level: :debug
      return solution if solution.unassigned.empty?

      vrp = service_vrp[:vrp]
      log "try to insert #{solution.unassigned.size} unassigned from #{vrp.services.size} services"
      transfer_unused_time_limit = 0
      vrp.routes = build_initial_routes([solution])
      vrp.configuration.resolution.init_duration = nil
      unassigned_service_ids = solution.unassigned.map(&:service_id).compact
      unassigned_services = vrp.services.select{ |s| unassigned_service_ids.include?(s.id) }
      unassigned_services_by_skills = unassigned_services.group_by(&:skills)

      @leftover_vehicle_limit = vrp.configuration.resolution.vehicle_limit - solution.routes.size

      # TODO: sort unassigned_services with no skill / sticky at the end
      unassigned_services_by_skills[[]] = [] if unassigned_services_by_skills.empty?

      unassigned_services_by_skills.each{ |skills, un_w_services|
        next if solution.unassigned.empty?

        insert_unassigned_by_skills(service_vrp, unassigned_services, un_w_services,
                                    skills, solution, transfer_unused_time_limit)
      }
      solution
    ensure
      log "<--- dicho::end_stage - level(#{service_vrp[:dicho_level]})", level: :debug
    end

    def self.split_vehicles(vrp, services_by_cluster)
      log "---> dicho::split_vehicles #{vrp.vehicles.size}", level: :debug
      services_skills_by_clusters = services_by_cluster.map{ |services|
        services.map{ |s| s.skills.empty? ? nil : s.skills.uniq.sort }.compact.uniq
      }
      log "services_skills_by_clusters #{services_skills_by_clusters}", level: :debug
      vehicles_by_clusters = [[], []]
      vrp.vehicles.each_with_index{ |v, v_i|
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
           ((vehicles_by_clusters[1].size - 1) / services_by_cluster[1].size >
           (vehicles_by_clusters[0].size + 1) / services_by_cluster[0].size ||
           (vehicles_by_clusters[1].size + 1) / services_by_cluster[1].size <
           (vehicles_by_clusters[0].size - 1) / services_by_cluster[0].size)
          cluster_index = nil
        end
        cluster_index ||= if vehicles_by_clusters[0].empty? || vehicles_by_clusters[1].empty?
                            vehicles_by_clusters[0].size <= vehicles_by_clusters[1].size ? 0 : 1
                          else
                            (services_by_cluster[0].size / vehicles_by_clusters[0].size) >=
                              (services_by_cluster[1].size / vehicles_by_clusters[1].size) ? 0 : 1
                          end
        vehicles_by_clusters[cluster_index] << v_i
      }

      if vehicles_by_clusters.any?(&:empty?)
        empty_side = vehicles_by_clusters.find(&:empty?)
        nonempty_side = vehicles_by_clusters.find(&:any?)

        # Move a vehicle from the skill group with most vehicles (from nonempty side to empty side)
        empty_side << nonempty_side.delete(
          nonempty_side.group_by{ |v|
            vrp.vehicles[v].skills.uniq.sort
          }.to_a.max_by{ |vec_group|
            vec_group[1].size
          }.last.first
        )
      end

      if vehicles_by_clusters[1].size > vehicles_by_clusters[0].size
        services_by_cluster.reverse!
        vehicles_by_clusters.reverse!
      end

      log "<--- dicho::split_vehicles #{vehicles_by_clusters.map(&:size)}", level: :debug
      vehicles_by_clusters
    end

    def self.split_vehicle_limits(vrp, vehicles_by_cluster)
      vehicle_shares = vehicles_by_cluster.collect(&:size)

      smaller_side = [1, (vehicle_shares.min.to_f / vehicle_shares.sum * vrp.configuration.resolution.vehicle_limit).round].max
      bigger_side  = vrp.configuration.resolution.vehicle_limit - smaller_side

      (vehicle_shares[0] < vehicle_shares[1]) ? [smaller_side, bigger_side] : [bigger_side, smaller_side]
    end

    def self.split(service_vrp, _job = nil)
      log "---> dicho::split - level(#{service_vrp[:dicho_level]})", level: :debug
      vrp = service_vrp[:vrp]
      vrp.configuration.resolution.vehicle_limit ||= vrp.vehicles.size
      services_by_cluster = kmeans(vrp, :duration).sort_by{ |ss| Helper.services_duration(ss) }
      split_service_vrps = []
      if services_by_cluster.size == 2
        # Kmeans return 2 vrps
        vehicles_by_cluster = split_vehicles(vrp, services_by_cluster)
        vehicle_limits_by_cluster = split_vehicle_limits(vrp, vehicles_by_cluster)

        [0, 1].each{ |i|
          sub_vrp = SplitClustering.build_partial_service_vrp(service_vrp,
                                                              services_by_cluster[i].map(&:id),
                                                              vehicles_by_cluster[i])[:vrp]

          # TODO: à cause de la grande disparité du split_vehicles par skills, on peut rapidement tomber à 1...
          sub_vrp.configuration.resolution.vehicle_limit = vehicle_limits_by_cluster[i]
          sub_vrp.configuration.resolution.split_number += i
          sub_vrp.configuration.resolution.total_split_number += 1

          split_service_vrps << {
            service: service_vrp[:service],
            vrp: sub_vrp,
            dicho_level: service_vrp[:dicho_level] + 1
          }
        }
      else
        # Kmeans return 1 vrp
        sub_vrp = SplitClustering.build_partial_service_vrp(service_vrp, services_by_cluster[0].map(&:id))[:vrp]
        sub_vrp.points = vrp.points
        sub_vrp.vehicles = vrp.vehicles
        sub_vrp.vehicles.each{ |vehicle|
          vehicle.cost_fixed = vehicle.cost_fixed&.positive? ? vehicle.cost_fixed : 1e6
        }
        split_service_vrps << {
          service: service_vrp[:service],
          vrp: sub_vrp,
          dicho_level: service_vrp[:dicho_level]
        }
      end
      OutputHelper::Clustering.generate_files(split_service_vrps) if OptimizerWrapper.config[:debug][:output_clusters]

      log "<--- dicho::split - level(#{service_vrp[:dicho_level]})", level: :debug
      split_service_vrps
    end

    # TODO: remove this method and use SplitClustering class instead
    def self.kmeans(vrp, cut_symbol)
      nb_clusters = 2
      # Split using balanced kmeans
      if vrp.services.all?(&:activity)
        cumulated_metrics = Hash.new(0)
        data_items = []

        # Collect data for kmeans
        vrp.points.each{ |point|
          unit_quantities = Hash.new(0)
          related_services = vrp.services.select{ |service| service.activity.point.id == point.id }
          related_services.each{ |service|
            unit_quantities[:visits] += 1
            cumulated_metrics[:visits] += 1
            unit_quantities[:duration] += service.activity.duration
            cumulated_metrics[:duration] += service.activity.duration
            service.quantities.each{ |quantity|
              unit_quantities[quantity.unit_id.to_sym] += quantity.value
              cumulated_metrics[quantity.unit_id.to_sym] += quantity.value
            }
          }

          next if related_services.empty?

          characteristics = { duration_from_and_to_depot: [0, 0] }
          characteristics[:matrix_index] = point[:matrix_index] unless vrp.matrices.empty?
          data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, characteristics, [], 0]
        }

        # No expected characteristics neither strict limitations because we do not
        # know which vehicles will be used in advance
        options = { max_iterations: 100, restarts: 5, cut_symbol: cut_symbol, last_iteration_balance_rate: 0.0 }
        limits = { metric_limit: { limit: cumulated_metrics[cut_symbol] / nb_clusters }, strict_limit: {}}

        options[:distance_matrix] = vrp.matrices[0].time if !vrp.matrices.empty?

        options[:clusters_infos] = SplitClustering.collect_cluster_data(vrp, nb_clusters)

        clusters = SplitClustering.kmeans_process(nb_clusters, data_items, {}, limits, options)

        services_by_cluster = clusters.collect{ |cluster|
          cluster.data_items.flat_map{ |data|
            vrp.services.select{ |service| service.activity.point_id == data[2] }
          }
        }

        log "Dicho K-Means: split #{vrp.services.size} into #{services_by_cluster.map.with_index{ |subset, s_i| "#{subset.size}(#{clusters[s_i].data_items.map{ |i| i[3][options[:cut_symbol]] || 0 }.inject(0, :+)})" }.join(' & ')} (cut symbol: #{options[:cut_symbol]})"

        services_by_cluster
      else
        log 'Split not available when services have no activities', level: :error
        [vrp]
      end
    end
  end
end
