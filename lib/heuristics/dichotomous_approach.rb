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
  class Dichotomous
    def self.dichotomous_candidate?(service_vrp)
      config = service_vrp[:vrp].configuration
      service_vrp[:dicho_level]&.positive? ||
        (
          # TODO: remove cost_fixed and duration conditions after exclusion cost calculation is corrected.
          service_vrp[:vrp].vehicles.none?{ |vehicle| vehicle.cost_fixed && !vehicle.cost_fixed.zero? } &&
          service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle.duration || vehicle.timewindow } &&
          service_vrp[:vrp].vehicles.size > config.resolution.dicho_algorithm_vehicle_limit &&
          (config.resolution.vehicle_limit.nil? ||
            config.resolution.vehicle_limit > config.resolution.dicho_algorithm_vehicle_limit) &&
          config.resolution.dicho_algorithm_service_limit.to_i.positive? &&
          service_vrp[:vrp].services.size - service_vrp[:vrp].routes.map{ |r| r.mission_ids.size }.sum >
            config.resolution.dicho_algorithm_service_limit &&
          !service_vrp[:vrp].schedule? &&
          service_vrp[:vrp].points.all?{ |point| point&.location&.lat && point&.location&.lon } &&
          service_vrp[:vrp].relations.empty? &&
          # TODO: max_split transfer_unused_resources can handle empties_or_fills use that logic in dicho
          service_vrp[:vrp].services.none?{ |s| s.quantities.any?(&:fill) || s.quantities.any?(&:empty) }
        )
    end

    def self.feasible_vrp(solution, service_vrp)
      solution.nil? || solution.count_unassigned_services != service_vrp[:vrp].services.size ||
        solution.unassigned_stops.reject(&:reason).any?
    end

    def self.dichotomous_heuristic(service_vrp, job = nil, &block)
      if dichotomous_candidate?(service_vrp)
        vrp = service_vrp[:vrp]
        log_message = "dicho - level(#{service_vrp[:dicho_level]}) "\
                  "activities: #{vrp.services.size} "\
                  "vehicles (limit): #{vrp.vehicles.size}(#{vrp.configuration.resolution.vehicle_limit})"\
                  "duration [min, max]: [#{vrp.configuration.resolution.minimum_duration&.round},"\
                  "#{vrp.configuration.resolution.duration&.round}]"
        log log_message, level: :info

        set_config(service_vrp)

        # Must be called to be sure matrices are complete in vrp and be able to switch vehicles between sub_vrp
        if service_vrp[:dicho_level].zero?
          service_vrp[:vrp].compute_matrix(job)
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

        if (solution.nil? || solution.unassigned_stops.size >= 0.7 * service_vrp[:vrp].services.size) &&
           feasible_vrp(solution, service_vrp) &&
           service_vrp[:vrp].vehicles.size > service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit &&
           service_vrp[:vrp].services.size > service_vrp[:vrp].configuration.resolution.dicho_division_service_limit
          sub_service_vrps = []

          3.times do # TODO: move this logic inside the split function
            sub_service_vrps = split(service_vrp, job)

            break if sub_service_vrps.size == 2 && sub_service_vrps.none?{ |s_vrp| s_vrp[:vrp].services.empty? }
          end

          if sub_service_vrps.size != 2 || sub_service_vrps.any?{ |s_vrp| s_vrp[:vrp].services.empty? }
            sub_service_vrps.each{ |s_vrp| s_vrp[:dicho_data][:cannot_split_further] = true }
            log 'dichotomous_heuristic cannot split the problem into two clusters', level: :warn
          end

          solutions =
            sub_service_vrps.map.with_index{ |sub_service_vrp, index|
              solution =
                OptimizerWrapper.define_process(sub_service_vrp,
                                                job) { |wrapper, avancement, total, message, cost, time, sol|
                  avc = service_vrp[:dicho_denominators].map.with_index{ |lvl, idx|
                    Rational(service_vrp[:dicho_sides][idx], lvl)
                  }.sum

                  msg =
                    if message.include?('dichotomous process')
                      message
                    else
                      add = "dichotomous process #{(service_vrp[:dicho_denominators].last * avc).to_i}"\
                            "/#{service_vrp[:dicho_denominators].last}"
                      OptimizerWrapper.concat_avancement(add, message)
                    end
                  block&.call(wrapper, avancement, total, msg, cost, time, sol)
                }

              transfer_unused_vehicles(solution, sub_service_vrps) if index.zero? && solution

              solution
            }
          solution = solutions.reduce(&:+)
          log "dicho - level(#{service_vrp[:dicho_level]}) before remove_bad_skills unassigned rate " \
              "#{solution.unassigned_stops.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned_stops.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"

          remove_bad_skills(service_vrp, solution)
          Interpreters::SplitClustering.remove_empty_routes(solution)
          solution.parse(vrp)
          log "dicho - level(#{service_vrp[:dicho_level]}) before end_stage_insert  unassigned rate " \
              "#{solution.unassigned_stops.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned_stops.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"

          solution = end_stage_insert_unassigned(service_vrp, solution, job)
          Interpreters::SplitClustering.remove_empty_routes(solution)

          if service_vrp[:dicho_level].zero?
            # Remove vehicles which are half empty
            log "dicho - before remove_poorly_populated_routes: #{solution.routes.size}"
            Interpreters::SplitClustering.remove_poorly_populated_routes(service_vrp[:vrp], solution, 0.5)
            log "dicho - after remove_poorly_populated_routes: #{solution.routes.size}"
          end
          solution.parse(vrp)

          log "dicho - level(#{service_vrp[:dicho_level]}) unassigned rate " \
              "#{solution.unassigned_stops.size}/#{service_vrp[:vrp].services.size}: " \
              "#{(solution.unassigned_stops.size.to_f / service_vrp[:vrp].services.size * 100).round(1)}%"
        end
      else
        service_vrp[:vrp].configuration.resolution.init_duration = nil
      end
      solution
    end

    def self.transfer_unused_vehicles(solution, sub_service_vrps)
      return if sub_service_vrps.size != 2

      sv_zero = sub_service_vrps[0][:vrp]
      sv_one = sub_service_vrps[1][:vrp]

      # Transfer the vehicles which do not appear in the routes or the empty vehicles that appear in the routes
      sv_zero.vehicles.each{ |vehicle|
        route = solution.routes.find{ |r| r.vehicle.id == vehicle.id }

        next if route&.stops&.any?(&:service_id)

        sv_one.vehicles << vehicle
        sv_zero.vehicles -= [vehicle]
        vehicle_points = [vehicle.start_point, vehicle.end_point].compact.uniq
        vehicle_points.each{ |new_point|
          existing_point = sv_one.points.find{ |p| p.id == new_point.id }

          if existing_point
            vehicle.start_point = existing_point if vehicle.start_point_id == new_point.id
            vehicle.end_point = existing_point if vehicle.end_point_id == new_point.id
          else
            sv_one.points << new_point
          end
        }
      }

      # Transfer unsued vehicle limit to the other side as well
      sv_zero_unused_vehicle_limit = sv_zero.configuration.resolution.vehicle_limit - solution.count_used_routes
      sv_one.configuration.resolution.vehicle_limit += sv_zero_unused_vehicle_limit
    end

    def self.dicho_level_coeff(service_vrp)
      balance = 0.66666
      divisor = (service_vrp[:vrp].configuration.resolution.vehicle_limit || service_vrp[:vrp].vehicles.size).to_f
      level_approx = Math.log(service_vrp[:vrp].configuration.resolution.dicho_division_vehicle_limit / divisor,
                              balance)
      power = 1 / (level_approx - service_vrp[:dicho_level]).to_f
      service_vrp[:vrp].configuration.resolution.dicho_level_coeff = 2**power
    end

    def self.set_config(service_vrp) # rubocop: disable Naming/AccessorMethodName, Style/CommentedKeyword
      # service_vrp[:vrp].configuration.resolution.batch_heuristic = true
      config = service_vrp[:vrp].configuration
      config.restitution.allow_empty_result = true

      if service_vrp[:dicho_level]&.zero?
        dicho_level_coeff(service_vrp)
        service_vrp[:vrp].vehicles.each{ |vehicle|
          vehicle[:cost_fixed] = vehicle[:cost_fixed]&.positive? ? vehicle[:cost_fixed] : 1e6
          vehicle[:cost_distance_multiplier] = 0.05 if vehicle[:cost_distance_multiplier].zero?
        }
      end

      config.resolution.init_duration = 90000 if config.resolution.duration > 90000
      config.resolution.vehicle_limit ||= service_vrp[:vrp][:vehicles].size
      config.resolution.init_duration =
        if (service_vrp[:dicho_data].nil? || !service_vrp[:dicho_data][:cannot_split_further]) &&
           service_vrp[:vrp].vehicles.size > config.resolution.dicho_division_vehicle_limit &&
           service_vrp[:vrp].services.size > config.resolution.dicho_division_service_limit &&
           config.resolution.vehicle_limit > config.resolution.dicho_division_vehicle_limit
          1000
        end

      service_vrp
    end

    def self.update_exclusion_cost(service_vrp)
      return if service_vrp[:dicho_level].zero?

      average_exclusion_cost = service_vrp[:vrp].services.sum(&:exclusion_cost) / service_vrp[:vrp].services.size
      service_vrp[:vrp].services.each{ |service|
        multiplier = (service_vrp[:vrp].configuration.resolution.dicho_level_coeff**service_vrp[:dicho_level] - 1)
        service.exclusion_cost += average_exclusion_cost * multiplier
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
          solution.unassigned_stops << a
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
        compatible =
          if skills.any?
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
        remaining_service_ids = solution.unassigned_stops.map(&:service_id) & unassigned_with_skills.map(&:id)
        next if remaining_service_ids.empty?

        rate_vehicles = vehicles_indices.size / vehicles_with_skills.size.to_f
        rate_services = unassigned_services.empty? ? 1 : unassigned_with_skills.size / unassigned_services.size.to_f

        sub_vrp_configuration_resolution_duration = [
          150,
          vrp.configuration.resolution.duration.to_f / 3.99 * rate_vehicles * rate_services + transfer_unused_time_limit
        ].max.to_i
        sub_vrp_configuration_resolution_minimum_duration =
          [(vrp.configuration.resolution.minimum_duration.to_f / 3.99 * rate_vehicles * rate_services).to_i, 100].max

        used_vehicle_count = vehicles_indices.count{ |_v_id, r_index, _v_index| r_index }

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

        resolution = sub_vrp.configuration.resolution
        resolution.minimum_duration = sub_vrp_configuration_resolution_minimum_duration if resolution.minimum_duration
        resolution.duration = sub_vrp_configuration_resolution_duration if resolution.duration
        resolution.vehicle_limit = sub_vrp_vehicle_limit if vrp.configuration.resolution.vehicle_limit

        sub_vrp.configuration.restitution.allow_empty_result = true
        solution_loop = OptimizerWrapper.solve(sub_service_vrp)

        next unless solution_loop

        solution.elapsed += solution_loop.elapsed.to_f
        transfer_unused_time_limit = resolution.duration - solution_loop.elapsed.to_f

        # TODO: Remove unnecessary if conditions and .nil? checks
        # Initial routes can be refused... check unassigned size before take into account solution
        next if remaining_service_ids.size < solution_loop.unassigned_stops.size

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

    def self.end_stage_insert_unassigned(service_vrp, solution, _job = nil)
      log "---> dicho::end_stage - level(#{service_vrp[:dicho_level]})"
      return solution if solution.unassigned_stops.empty?

      vrp = service_vrp[:vrp]
      log "try to insert #{solution.unassigned_stops.size} unassigned from #{vrp.services.size} services"
      transfer_unused_time_limit = 0
      vrp.routes = build_initial_routes([solution])
      vrp.configuration.resolution.init_duration = nil
      unassigned_service_ids = solution.unassigned_stops.map(&:service_id).compact
      unassigned_services = vrp.services.select{ |s| unassigned_service_ids.include?(s.id) }
      unassigned_services_by_skills = unassigned_services.group_by(&:skills)

      @leftover_vehicle_limit = vrp.configuration.resolution.vehicle_limit - solution.routes.size

      # TODO: sort unassigned_services with no skill / sticky at the end
      unassigned_services_by_skills[[]] = [] if unassigned_services_by_skills.empty?

      unassigned_services_by_skills.each{ |skills, un_w_services|
        next if solution.unassigned_stops.empty?

        insert_unassigned_by_skills(service_vrp, unassigned_services, un_w_services,
                                    skills, solution, transfer_unused_time_limit)
      }
      solution
    ensure
      log "<--- dicho::end_stage - level(#{service_vrp[:dicho_level]})"
    end

    def self.split(service_vrp, job = nil)
      log "---> dicho::split - level(#{service_vrp[:dicho_level]})"

      unless service_vrp[:dicho_data]
        service_vrp[:dicho_data], _empties_or_fills = SplitClustering.initialize_split_data(service_vrp, job)
      end
      dicho_data = service_vrp[:dicho_data]

      enum_current_vehicles = dicho_data[:current_vehicles].select

      sides =
        SplitClustering.split_balanced_kmeans(
          { vrp: SplitClustering.create_representative_sub_vrp(dicho_data) }, 2,
          cut_symbol: :duration, restarts: 1, build_sub_vrps: false, basic_split: true, group_points: false
        ).sort_by!{ |side|
          [side.size, side.sum(&:visits_number)] # [number_of_vehicles, number_of_visits]
        }.reverse!.collect!{ |side|
          enum_current_vehicles.select{ |v| side.any?{ |s| s.id == "0_representative_vrp_s_#{v.id}" } }
        }

      split_service_vrps = []
      sides.select(&:any?).collect.with_index{ |side, i|
        local_dicho_data = dicho_data.dup
        local_dicho_data[:current_vehicles] = side

        split_service_vrps << {
          service: service_vrp[:service],
          vrp: SplitClustering.create_sub_vrp(local_dicho_data),
          dicho_data: local_dicho_data,
          dicho_level: service_vrp[:dicho_level] + 1,
          # dicho_denominators and dicho_sides logic comes from
          # https://github.com/braktar/optimizer-api/commit/1abb786365b4582c7279540c46e541a80f76a489
          dicho_denominators: service_vrp[:dicho_denominators] + [2**(service_vrp[:dicho_level] + 1)],
          dicho_sides: service_vrp[:dicho_sides] + [i],
        }
      }

      log "<--- dicho::split - level(#{service_vrp[:dicho_level]})"
      split_service_vrps
    end
  end
end
