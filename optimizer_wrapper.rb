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
# frozen_string_literal: true

require 'i18n'
require 'resque'
require 'resque-status'
require 'redis'
require 'json'

require './util/error.rb'
require './util/config.rb'
require './util/job_manager.rb'

require './lib/routers/router_wrapper.rb'
require './lib/interpreters/multi_modal.rb'
require './lib/interpreters/periodic_visits.rb'
require './lib/interpreters/split_clustering.rb'
require './lib/interpreters/compute_several_solutions.rb'
require './lib/heuristics/assemble_heuristic.rb'
require './lib/heuristics/dichotomious_approach.rb'
require './lib/filters.rb'
require './lib/cleanse.rb'
require './lib/output_helper.rb'

require 'ai4r'
include Ai4r::Data
require './lib/clusterers/complete_linkage_max_distance.rb'
include Ai4r::Clusterers
require 'sim_annealing'

require 'rgeo/geo_json'

module OptimizerWrapper
  def self.wrapper_vrp(api_key, profile, vrp, checksum, job_id = nil)
    inapplicable_services = []
    apply_zones(vrp)
    adjust_vehicles_duration(vrp)

    Filters.filter(vrp)

    vrp.resolution_repetition ||=
      if !vrp.preprocessing_partitions.empty? && vrp.periodic_heuristic?
        config[:solve][:repetition]
      else
        1
      end

    services_vrps = split_independent_vrp(vrp).map{ |vrp_element|
      {
        service: profile[:services][:vrp].find{ |s|
          inapplicable = config[:services][s].inapplicable_solve?(vrp_element)
          if inapplicable.empty?
            log "Select service #{s}"
            true
          else
            inapplicable_services << inapplicable
            log "Skip inapplicable #{s}: #{inapplicable.join(', ')}"
            false
          end
        },
        vrp: vrp_element,
        dicho_level: 0
      }
    }

    if services_vrps.any?{ |sv| !sv[:service] }
      raise UnsupportedProblemError.new('Cannot apply any of the solver services', inapplicable_services)
    elsif config[:solve][:synchronously] || (
            services_vrps.size == 1 &&
            !vrp.preprocessing_cluster_threshold &&
            config[:services][services_vrps[0][:service]].solve_synchronous?(vrp)
          )
      # The job seems easy enough to perform it with the server
      result = define_main_process(services_vrps, job_id)
      result.size == 1 ? result.first : result
    else
      # Delegate the job to a worker (expire is defined resque config)
      job_id = Job.enqueue_to(profile[:queue], Job, services_vrps: Base64.encode64(Marshal.dump(services_vrps)),
                                                     api_key: api_key,
                                                     checksum: checksum,
                                                     pids: [])
      JobList.add(api_key, job_id)
      job_id
    end
  end

  def self.define_main_process(services_vrps, job = nil, &block)
    log "--> define_main_process #{services_vrps.size} VRPs", level: :info
    log "activities: #{services_vrps.map{ |sv| sv[:vrp].services.size}}", level: :info
    log "vehicles: #{services_vrps.map{ |sv| sv[:vrp].vehicles.size }}", level: :info
    log "resolution_vehicle_limit: #{services_vrps.map{ |sv| sv[:vrp].resolution_vehicle_limit }}", level: :info
    log "min_durations: #{services_vrps.map{ |sv| sv[:vrp].resolution_minimum_duration&.round }}", level: :info
    log "max_durations: #{services_vrps.map{ |sv| sv[:vrp].resolution_duration&.round }}", level: :info
    tic = Time.now

    expected_activity_count = services_vrps.collect{ |sv| sv[:vrp].visits }.sum

    several_service_vrps = Interpreters::SeveralSolutions.expand_similar_resolutions(services_vrps)
    several_solutions = several_service_vrps.collect.with_index{ |current_service_vrps, solution_index|
      callback_main = lambda { |wrapper, avancement, total, message, cost = nil, time = nil, solution = nil|
        msg = "#{"solution: #{solution_index + 1}/#{several_service_vrps.size} - " if several_service_vrps.size > 1}#{message}" unless message.nil?
        block&.call(wrapper, avancement, total, msg, cost, time, solution)
      }

      join_independent_vrps(current_service_vrps, callback_main) { |service_vrp, callback_join|
        repeated_results = []

        service_vrp_repeats = Interpreters::SeveralSolutions.expand_repetitions(service_vrp)

        service_vrp_repeats.each_with_index{ |repeated_service_vrp, repetition_index|
          repeated_results << define_process(repeated_service_vrp, job) { |wrapper, avancement, total, message, cost, time, solution|
            msg = "#{"repetition #{repetition_index + 1}/#{service_vrp_repeats.size} - " if service_vrp_repeats.size > 1}#{message}" unless message.nil?
            callback_join&.call(wrapper, avancement, total, msg, cost, time, solution)
          }
          Models.delete_all # needed to prevent duplicate ids because expand_repeat uses Marshal.load/dump

          break if repeated_results.last[:unassigned].empty? # No need to repeat more, cannot do better than this
        }

        # NOTE: the only criteria is number of unassigneds at the moment so if there is ever a solution with zero
        # unassigned, the loop is cut early. That is, if the criteria below is evolved, the above `break if` condition
        # should be modified in a similar fashion)
        (result, position) = repeated_results.each.with_index(1).min_by { |result, _| result[:unassigned].size } # find the best result and its index
        log "#{job}_repetition - #{repeated_results.collect{ |r| r[:unassigned].size }} : chose to keep the #{position.ordinalize} solution"
        result
      }
    }

    # demo solver returns a fixed solution
    unless services_vrps.collect{ |sv| sv[:service] }.uniq == [:demo]
      check_solutions_consistency(expected_activity_count, several_solutions)
    end

    nb_routes = several_solutions.sum{ |result| result[:routes].count{ |r| r[:activities].any?{ |a| a[:service_id] } } }
    nb_unassigned = several_solutions.sum{ |result| result[:unassigned].size }
    percent_unassigned = (100.0 * nb_unassigned / expected_activity_count).round(1)

    log "result - #{nb_unassigned} of #{expected_activity_count} (#{percent_unassigned}%) unassigned activities"
    log "result - #{nb_routes} of #{services_vrps.sum{ |sv| sv[:vrp].vehicles.size }} vehicles used"

    several_solutions
  ensure
    log "<-- define_main_process elapsed: #{(Time.now - tic).round(2)} sec", level: :info
  end

  # Mutually recursive method
  def self.define_process(service_vrp, job = nil, &block)
    vrp = service_vrp[:vrp]
    dicho_level = service_vrp[:dicho_level].to_i
    split_level = service_vrp[:split_level].to_i
    shipment_size = vrp.relations.count{ |r| r.type == :shipment }
    log "--> define_process VRP (service: #{vrp.services.size} including #{shipment_size} shipment relations, " \
        "vehicle: #{vrp.vehicles.size}, v_limit: #{vrp.resolution_vehicle_limit}) " \
        "with levels (dicho: #{dicho_level}, split: #{split_level})", level: :info
    log "min_duration #{vrp.resolution_minimum_duration&.round} max_duration #{vrp.resolution_duration&.round}",
        level: :info

    tic = Time.now
    expected_activity_count = vrp.visits

    solution ||= Interpreters::SplitClustering.split_clusters(service_vrp, job, &block)        # Calls recursively define_process

    solution ||= Interpreters::Dichotomious.dichotomious_heuristic(service_vrp, job, &block)   # Calls recursively define_process

    solution ||= solve(service_vrp, job, block)

    check_solutions_consistency(expected_activity_count, [solution]) if service_vrp[:service] != :demo # demo solver returns a fixed solution

    log "<-- define_process levels (dicho: #{dicho_level}, split: #{split_level}) elapsed: #{(Time.now - tic).round(2)} sec", level: :info
    solution.use_deprecated_csv_headers = vrp.restitution_use_deprecated_csv_headers
    solution
  end

  def self.solve(service_vrp, job = nil, block = nil)
    vrp = service_vrp[:vrp]
    service = service_vrp[:service]
    dicho_level = service_vrp[:dicho_level]
    shipment_size = vrp.relations.count{ |r| r.type == :shipment }
    log "--> optim_wrap::solve VRP (service: #{vrp.services.size} including #{shipment_size} shipment relations, " \
        "vehicle: #{vrp.vehicles.size} v_limit: #{vrp.resolution_vehicle_limit}) with levels " \
        "(dicho: #{service_vrp[:dicho_level]}, split: #{service_vrp[:split_level].to_i})", level: :debug

    tic = Time.now

    optim_result = nil

    unfeasible_services = {}

    if !vrp.subtours.empty?
      multi_modal = Interpreters::MultiModal.new(vrp, service)
      optim_result = multi_modal.multimodal_routes
    elsif vrp.vehicles.empty? || vrp.services.empty?
      optim_result = vrp.empty_solution(service.to_s, 'No vehicle available for this service', false)
    else
      unfeasible_services = config[:services][service].detect_unfeasible_services(vrp)

      vrp.compute_matrix(&block)

      config[:services][service].check_distances(vrp, unfeasible_services)

      # Remove infeasible services
      services_to_reinject = []
      unfeasible_services.each_key{ |una_service_id|
        index = vrp.services.find_index{ |s| s.id == una_service_id }
        if index
          services_to_reinject << vrp.services.slice!(index)
        end
      }

      # TODO: refactor with dedicated class
      if vrp.schedule?
        periodic = Interpreters::PeriodicVisits.new(vrp)
        vrp = periodic.expand(vrp, job, &block)
        optim_result = parse_result(vrp, vrp.preprocessing_heuristic_result) if vrp.periodic_heuristic?
      end

      if vrp.resolution_solver && !vrp.periodic_heuristic?
        block&.call(nil, nil, nil, "process clique clustering : threshold (#{vrp.preprocessing_cluster_threshold.to_f}) ", nil, nil, nil) if vrp.preprocessing_cluster_threshold.to_f.positive?
        optim_result = clique_cluster(vrp, vrp.preprocessing_cluster_threshold, vrp.preprocessing_force_cluster) { |cliqued_vrp|
          time_start = Time.now

          OptimizerWrapper.config[:services][service].simplify_constraints(cliqued_vrp)

          block&.call(nil, 0, nil, 'run optimization', nil, nil, nil) if dicho_level.nil? || dicho_level.zero?

          # TODO: Move select best heuristic in each solver
          Interpreters::SeveralSolutions.custom_heuristics(service, vrp, block)

          cliqued_solution = OptimizerWrapper.config[:services][service].solve(
            cliqued_vrp,
            job,
            proc{ |pids|
              next unless job

              current_result = Result.get(job) || { pids: nil }
              current_result[:configuration] = {
                csv: cliqued_vrp.restitution_csv,
                geometry: cliqued_vrp.restitution_geometry
              }
              current_result[:pids] = pids

              Result.set(job, current_result)
            }
          ) { |wrapper, avancement, total, _message, cost, _time, solution|
            solution =
              if solution.is_a?(Models::Solution)
                OptimizerWrapper.config[:services][service].patch_simplified_constraints_in_result(solution, cliqued_vrp)
              end
            block&.call(wrapper, avancement, total, 'run optimization, iterations', cost, (Time.now - time_start) * 1000, solution) if dicho_level.nil? || dicho_level.zero?
          }

          OptimizerWrapper.config[:services][service].patch_and_rewind_simplified_constraints(cliqued_vrp, cliqued_solution)

          if cliqued_solution.is_a?(Models::Solution)
            # cliqued_solution[:elapsed] = (Time.now - time_start) * 1000 # Can be overridden in wrappers
            block&.call(nil, nil, nil, "process #{vrp.resolution_split_number}/#{vrp.resolution_total_split_number} - " + 'run optimization' + " - elapsed time #{(Result.time_spent(cliqued_solution.elapsed) / 1000).to_i}/" + "#{vrp.resolution_total_duration / 1000} ", nil, nil, nil) if dicho_level&.positive?
            cliqued_solution.parse_solution(cliqued_vrp)
          elsif cliqued_solution.status == :killed
            next
          elsif cliqued_solution.is_a?(String)
            raise RuntimeError, cliqued_solution
          elsif (vrp.preprocessing_heuristic_result.nil? || vrp.preprocessing_heuristic_result.empty?) && !vrp.restitution_allow_empty_result
            puts cliqued_solution
            raise RuntimeError, 'No solution provided'
          end
        }
      end

      # Reintegrate unfeasible services deleted from vrp.services to help ortools
      vrp.services += services_to_reinject
    end

    if optim_result #Job might have been killed
      Cleanse.cleanse(vrp, optim_result)

      optim_result[:name] = vrp.name
      optim_result[:configuration] = {
        csv: vrp.restitution_csv,
        geometry: vrp.restitution_geometry
      }
      optim_result.unassigned = (optim_result.unassigned || []) + unfeasible_services.values

      if vrp.preprocessing_first_solution_strategy
        optim_result[:heuristic_synthesis] = vrp.preprocessing_heuristic_synthesis
      end
    end

    log "<-- optim_wrap::solve elapsed: #{(Time.now - tic).round(2)}sec", level: :debug

    optim_result
  end

  def self.compute_independent_skills_sets(vrp, mission_skills, vehicle_skills)
    independent_skills = Array.new(mission_skills.size) { |i| [i] }

    correspondance_hash = vrp.vehicles.map{ |vehicle|
      [vehicle.id, vehicle_skills.index{ |skills| skills == vehicle.skills.flatten }]
    }.to_h

    # Build the compatibility table between service and vehicle skills
    # As reminder vehicle skills are defined as an OR condition
    # When the services skills are defined as an AND condition
    compatibility_table = mission_skills.map.with_index{ |_skills, _index| Array.new(vehicle_skills.size) { false } }
    mission_skills.each.with_index{ |m_skills, m_index|
      vehicle_skills.each.with_index{ |v_skills, v_index|
        compatibility_table[m_index][v_index] = true if (v_skills & m_skills) == m_skills
      }
    }

    vrp.relations.select{ |relation|
      Models::Relation::ON_VEHICLES_TYPES.include?(relation.type)
    }.each{ |relation|
      v_skills_indices = relation.linked_vehicle_ids.map{ |v_id| correspondance_hash[v_id] }
      mission_skill_indices = []
      # We check if there is at least one vehicle of the relation compatible with a mission skills set
      v_skills_indices.each{ |v_index|
        mission_skills.each_index.each{ |m_index|
          mission_skill_indices << m_index if compatibility_table[m_index][v_index]
        }
      }
      next if mission_skill_indices.empty?

      mission_skill_indices.uniq!

      # If at last one vehicle of the relation is compatible, then we propagate it,
      # as we want all the relation vehicles to belong to the same problem
      v_skills_indices.each{ |v_index|
        mission_skill_indices.each{ |m_index|
          compatibility_table[m_index][v_index] = true
        }
      }
    }

    mission_skills.size.times.each{ |a_line|
      ((a_line + 1)..mission_skills.size - 1).each{ |b_line|
        next if (compatibility_table[a_line].select.with_index{ |state, index|
          state & compatibility_table[b_line][index]
        }).empty?

        b_set = independent_skills.find{ |set| set.include?(b_line) && set.exclude?(a_line) }
        next if b_set.nil?

        # Skills indices are merged as they have at least a vehicle in common
        independent_skills.delete(b_set)
        set_index = independent_skills.index{ |set| set.include?(a_line) }
        independent_skills[set_index] += b_set
      }
    }
    # Independent skill sets : Original skills are retrieved
    independent_skills.map{ |index_set|
      index_set.collect{ |index| mission_skills[index] }
    }
  end

  def self.build_independent_vrps(vrp, skill_sets, skill_vehicle_ids, skill_service_ids)
    unused_vehicle_indices = (0..vrp.vehicles.size - 1).to_a
    independent_vrps = skill_sets.collect{ |skills_set|
      # Compatible problem ids are retrieved
      vehicle_indices = skills_set.flat_map{ |skills|
        skill_vehicle_ids.select{ |k, _v| (k & skills) == skills }.flat_map{ |_k, v| v }
      }.uniq
      vehicle_indices.each{ |index| unused_vehicle_indices.delete(index) }
      service_ids = skills_set.flat_map{ |skills| skill_service_ids[skills] }

      service_vrp = { service: nil, vrp: vrp }
      Interpreters::SplitClustering.build_partial_service_vrp(service_vrp,
                                                              service_ids,
                                                              vehicle_indices)[:vrp]
    }
    total_size = vrp.services.all?{ |service| service.sticky_vehicles.any? } ? vrp.vehicles.size :
     independent_vrps.collect{ |s_vrp| s_vrp.services.size * [1, s_vrp.vehicles.size].min }.sum
    independent_vrps.each{ |sub_vrp|
      # If one sub vrp has no vehicle or no service, duration can be zero.
      # We only split duration among sub_service_vrps that have at least one vehicle and one service.
      this_sub_size = vrp.services.all?{ |service| service.sticky_vehicles.any? } ? sub_vrp.vehicles.size :
        sub_vrp.services.size * [1, sub_vrp.vehicles.size].min
      adjust_independent_duration(sub_vrp, this_sub_size, total_size)
    }

    return independent_vrps if unused_vehicle_indices.empty?

    sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp({ vrp: vrp }, [], unused_vehicle_indices)
    sub_service_vrp[:vrp].matrices = []
    independent_vrps.push(sub_service_vrp[:vrp])

    independent_vrps
  end

  def self.adjust_independent_duration(vrp, this_sub_size, total_size)
    split_ratio = this_sub_size.to_f / total_size
    vrp.resolution_duration = vrp.resolution_duration&.*(split_ratio)&.ceil
    vrp.resolution_minimum_duration =
      vrp.resolution_minimum_duration&.*(split_ratio)&.ceil
    vrp.resolution_iterations_without_improvment =
      vrp.resolution_iterations_without_improvment&.*(split_ratio)&.ceil
    vrp
  end

  def self.split_independent_vrp(vrp)
    # Don't split vrp if
    # - No vehicle
    # - No service
    # - there is multimodal subtours
    return [vrp] if (vrp.vehicles.size <= 1) || vrp.services.empty? || vrp.subtours&.any? # there might be zero services

    # - there is a service with no skills (or sticky vehicle see: expand_data.rb:sticky_as_skills)
    mission_skills = vrp.services.map(&:skills).uniq
    return [vrp] if mission_skills.include?([])

    # Generate Services data
    grouped_services = vrp.services.group_by(&:skills)
    skill_service_ids = Hash.new{ [] }
    grouped_services.each{ |skills, missions| skill_service_ids[skills] += missions.map(&:id) }

    # Generate Vehicles data
    ### Be careful in case the alternative skills are supported again !
    grouped_vehicles = vrp.vehicles.group_by{ |vehicle| vehicle.skills.flatten }
    vehicle_skills = grouped_vehicles.keys.uniq
    skill_vehicle_ids = Hash.new{ [] }
    grouped_vehicles.each{ |skills, vehicles|
      skill_vehicle_ids[skills] += vehicles.map{ |vehicle| vrp.vehicles.find_index(vehicle) }
    }

    independant_skill_sets = compute_independent_skills_sets(vrp, mission_skills, vehicle_skills)

    build_independent_vrps(vrp, independant_skill_sets, skill_vehicle_ids, skill_service_ids)
  end

  def self.join_independent_vrps(services_vrps, callback)
    solutions = services_vrps.each_with_index.map{ |service_vrp, i|
      block = if services_vrps.size > 1 && !callback.nil?
                proc { |wrapper, avancement, total, message, cost = nil, time = nil, solution = nil|
                  msg = "split independent process #{i + 1}/#{services_vrps.size} - #{message}" unless message.nil?
                  callback&.call(wrapper, avancement, total, msg, cost, time, solution)
                }
              else
                callback
              end
      yield(service_vrp, block)
    }

    solutions.reduce(&:+)
    # Helper.merge_results(solutions, true)
  end

  def self.job_list(api_key)
    (JobList.get(api_key) || []).collect{ |e|
      if job = Resque::Plugins::Status::Hash.get(e) # rubocop: disable Lint/AssignmentInCondition
        {
          time: job.time,
          uuid: job.uuid,
          status: job.status,
          avancement: job.message,
          checksum: job.options && job.options['checksum']
        }
      else
        Result.remove(api_key, e)
      end
    }.compact
  end

  def self.job_kill(_api_key, id)
    res = Result.get(id)
    Resque::Plugins::Status::Hash.kill(id) # Worker will be killed at the next call of at() method

    # Only kill the solver process if a pid has been set
    if res && res[:pids] && !res[:pids].empty?
      res[:pids].each{ |pid|
        begin
          Process.kill('KILL', pid)
        rescue Errno::ESRCH
          nil
        end
      }
    end

    @killed = true
  end

  def self.job_remove(api_key, id)
    Result.remove(api_key, id)
    # remove only queued jobs
    if Resque::Plugins::Status::Hash.get(id)
      Job.dequeue(Job, id)
      Resque::Plugins::Status::Hash.remove(id)
    end
  end

  private

  def self.check_solutions_consistency(expected_value, solutions)
    solutions.each{ |solution|
      if solution.routes.any?{ |route| route.activities.any?{ |a| a.timings.waiting_time < 0 } }
        log 'Computed waiting times are invalid', level: :warn
        raise RuntimeError, 'Computed waiting times are invalid' if ENV['APP_ENV'] != 'production'
      end

      waiting_times = solution.routes.map{ |route| route.detail.total_waiting_time }.compact
      durations = solution.routes.map{ |route|
        route.activities.map{ |act|
          act.timings.departure_time && (act.timings.departure_time - act.timings.begin_time)
        }.compact
      }
      setup_durations = solution.routes.map{ |route|
        route.activities.map{ |act|
          next if act.type == 'rest'

          (act.timings.travel_time.nil? || act.timings.travel_time&.positive?) && act.detail.setup_duration || 0
        }.compact
      }
      total_time = solution.details.total_time || 0
      total_travel_time = solution.details.total_travel_time || 0
      if !@zip_condition && total_time != (total_travel_time || 0) +
                                           waiting_times.sum +
                                           (setup_durations.flatten.reduce(&:+) || 0) +
                                           (durations.flatten.reduce(&:+) || 0)

        log_string = 'Computed times are invalid'
        tags = {
          total_time: total_time,
          total_travel_time: total_travel_time,
          waiting_time: waiting_times.sum,
          setup_durations: setup_durations.flatten.reduce(&:+),
          durations: durations.flatten.reduce(&:+)
        }
        log log_string, tags.merge(level: :warn)
        raise RuntimeError, 'Computed times are invalid' if ENV['APP_ENV'] != 'production'
      end

      nb_assigned = solution.routes.sum{ |route| route.activities.count(&:service_id) }
      nb_unassigned = solution.unassigned.count(&:service_id)

      if expected_value != nb_assigned + nb_unassigned # rubocop:disable Style/Next for error handling
        tags = { expected: expected_value, assigned: nb_assigned, unassigned: nb_unassigned }
        log 'Wrong number of visits returned in result', tags.merge(level: :warn)
        # FIXME: Validate time computation for zip clusters
        raise RuntimeError, 'Wrong number of visits returned in result' if ENV['APP_ENV'] != 'production'
      end
    }
  end

  def self.adjust_vehicles_duration(vrp)
      vrp.vehicles.select{ |v| v.duration? && !v.rests.empty? }.each{ |v|
        v.rests.each{ |r|
          v.duration += r.duration
        }
      }
  end

  def self.formatted_duration(duration)
    if duration
      h = (duration / 3600).to_i
      m = (duration / 60).to_i % 60
      s = duration.to_i % 60
      [h, m, s].map { |t| t.to_s.rjust(2, '0') }.join(':')
    end
  end

  def self.compute_route_waiting_times(route)
    previous_end = route[:activities].first[:begin_time]
    loc_index = nil
    consumed_travel_time = 0
    consumed_setup_time = 0
    route[:activities].each.with_index{ |act, index|
      used_travel_time = 0
      if act[:type] == 'rest'
        if loc_index.nil?
          next_index = route[:activities][index..-1].index{ |a| a[:type] != 'rest' }
          loc_index = index + next_index if next_index
          consumed_travel_time = 0
        end
        shared_travel_time = loc_index && route[:activities][loc_index][:travel_time] || 0
        potential_setup = shared_travel_time > 0 && route[:activities][loc_index][:detail][:setup_duration] || 0
        left_travel_time = shared_travel_time - consumed_travel_time
        used_travel_time = [act[:begin_time] - previous_end, left_travel_time].min
        consumed_travel_time += used_travel_time
        # As setup is considered as a transit value, it may be performed before a rest
        consumed_setup_time  += [act[:begin_time] - previous_end - used_travel_time, potential_setup].min
      else
        used_travel_time = (act[:travel_time] || 0) - consumed_travel_time - consumed_setup_time
        consumed_travel_time = 0
        consumed_setup_time = 0
        loc_index = nil
      end
      considered_setup = act[:travel_time]&.positive? && (act[:detail][:setup_duration].to_i - consumed_setup_time) || 0
      arrival_time = previous_end + used_travel_time + considered_setup + consumed_setup_time
      act[:waiting_time] = act[:begin_time] - arrival_time
      previous_end = act[:end_time] || act[:begin_time]
    }
  end

  def self.provide_day(vrp, route)
    return unless vrp.schedule?

    route_index = route[:vehicle_id].split('_').last.to_i

    if vrp.schedule_start_date
      days_from_start = route_index - vrp.schedule_range_indices[:start]
      route[:day] = vrp.schedule_start_date.to_date + days_from_start
    else
      route_index
    end
  end

  def self.provide_visits_index(vrp, set)
    return unless vrp.schedule?

    set.each{ |activity|
      id = activity[:service_id] || activity[:rest_id] ||
           activity[:pickup_shipment_id] || activity[:delivery_shipment_id]

      next unless id

      activity[:visit_index] = id.split('_')[-2].to_i
    }
  end

  def self.apply_zones(vrp)
    vrp.zones.each{ |zone|
      next if zone.allocations.empty?

      zone.vehicles = if zone.allocations.size == 1
                        zone.allocations[0].collect{ |vehicle_id| vrp.vehicles.find{ |vehicle| vehicle.id == vehicle_id } }.compact
                      else
                        zone.allocations.collect{ |allocation| vrp.vehicles.find{ |vehicle| vehicle.id == allocation.first } }.compact
                      end

      next if zone.vehicles.compact.empty?

      zone.vehicles.each{ |vehicle|
        vehicle.skills.each{ |skillset| skillset << zone[:id] }
      }
    }

    return unless vrp.points.all?(&:location)

    vrp.zones.each{ |zone|
      related_ids = vrp.services.collect{ |service|
        activity_loc = service.activity.point.location

        next unless zone.inside(activity_loc.lat, activity_loc.lon)

        service.skills += [zone[:id]]
        service.id
      }.compact

      # Remove zone allocation verification if we need to assign zone without vehicle affectation together
      next unless zone.allocations.size > 1 && related_ids.size > 1

      vrp.relations += [{
        type: :same_route,
        linked_ids: related_ids.flatten,
      }]
    }
  end

  def self.clique_cluster(vrp, cluster_threshold, force_cluster)
    @zip_condition = vrp.matrices.any? && (cluster_threshold.to_f.positive? || force_cluster) && !vrp.schedule?

    if @zip_condition
      if vrp.services.any?{ |s| s.activities.any? }
        raise UnsupportedProblemError('Threshold is not supported yet if one service has serveral activies.')
      end

      original_services = Array.new(vrp.services.size){ |i| vrp.services[i].clone }
      zip_key = zip_cluster(vrp, cluster_threshold, force_cluster)
    end
    result = yield(vrp)
    if @zip_condition
      vrp.services = original_services
      unzip_cluster(result, zip_key, vrp)
    else
      result
    end
  end

  def self.zip_cluster(vrp, cluster_threshold, force_cluster)
    return nil if vrp.services.empty?

    data_set = DataSet.new(data_items: (0..(vrp.services.length - 1)).collect{ |i| [i] })
    c = CompleteLinkageMaxDistance.new
    matrix = vrp.matrices[0][vrp.vehicles[0].router_dimension.to_sym]
    cost_late_multiplier = vrp.vehicles.all?{ |v| v.cost_late_multiplier && v.cost_late_multiplier != 0 }
    no_capacities = vrp.vehicles.all?{ |v| v.capacities&.empty? }
    c.distance_function = if force_cluster
      lambda do |a, b|
        aa = vrp.services[a[0]]
        bb = vrp.services[b[0]]
        aa.activity.timewindows.empty? && bb.activity.timewindows.empty? ||
          aa.activity.timewindows.any?{ |twa|
            bb.activity.timewindows.any?{ |twb| twa.start <= twb.end && twb.start <= twa.end }
          } ?
          matrix[aa.activity.point.matrix_index][bb.activity.point.matrix_index] :
          Float::INFINITY
      end
    else
      lambda do |a, b|
        aa = vrp.services[a[0]]
        bb = vrp.services[b[0]]
        aa.activity.timewindows.collect{ |t| [t.start, t.end] } == bb.activity.timewindows.collect{ |t| [t.start, t.end] } &&
          ((cost_late_multiplier && aa.activity.late_multiplier.to_f.positive? && bb.activity.late_multiplier.to_f.positive?) || (aa.activity.duration&.zero? && bb.activity.duration&.zero?)) &&
          (no_capacities || (aa.quantities&.empty? && bb.quantities&.empty?)) &&
          aa.skills == bb.skills ?
          matrix[aa.activity.point.matrix_index][bb.activity.point.matrix_index] :
          Float::INFINITY
      end
                          end
    clusterer = c.build(data_set, cluster_threshold)

    new_size = clusterer.clusters.size

    # Build replacement list
    new_services = Array.new(new_size)
    clusterer.clusters.each_with_index do |cluster, i|
      new_services[i] = vrp.services[cluster.data_items[0][0]]
      new_services[i].activity.duration = cluster.data_items.map{ |di| vrp.services[di[0]].activity.duration }.reduce(&:+)
      next unless force_cluster

      new_quantities = []
      type = []
      services_quantities = cluster.data_items.map{ |di|
        di.collect{ |index|
          type << vrp.services[index].type
          vrp.services[index].quantities
        }.flatten
      }
      services_quantities.each_with_index{ |service_quantity, index|
        if new_quantities.empty?
          new_quantities = service_quantity
        else
          service_quantity.each{ |sub_quantity|
            (new_quantities.one?{ |new_quantity| new_quantity[:unit_id] == sub_quantity[:unit_id] }) ? new_quantities.find{ |new_quantity| new_quantity[:unit_id] == sub_quantity[:unit_id] }[:value] += (type[index] == 'delivery') ? -sub_quantity[:value] : sub_quantity[:value] : new_quantities << sub_quantity
          }
        end
      }
      new_services[i].quantities = new_quantities
      new_services[i].priority = cluster.data_items.map{ |di| vrp.services[di[0]].priority }.min

      new_tws = []
      to_remove_tws = []
      service_tws = cluster.data_items.map{ |di|
        di.collect{ |index|
          vrp.services[index].activity.timewindows
        }.flatten
      }
      service_tws.each{ |service_tw|
        if new_tws.empty?
          new_tws = service_tw
        else
          new_tws.each{ |new_tw|
            # find intersection with tw of service_tw
            compatible_tws = service_tw.select{ |tw|
              tw.day_index.nil? || new_tw.day_index.nil? || tw.day_index == new_tw.day_index &&
                (new_tw.end.nil? || tw.start <= new_tw.end) &&
                (tw.end.nil? || tw.end >= new_tw.start)
            }
            if compatible_tws.empty?
              to_remove_tws << new_tws
            else
              compatible_start = compatible_tws.collect(&:start).max
              compatible_end = compatible_tws.collect(&:end).compact.min
              new_tw.start = [new_tw.start, compatible_start].max
              new_tw.end = [new_tw.end, compatible_end].min if compatible_end
            end
          }
        end
      }
      if !new_tws.empty? && (new_tws - to_remove_tws).empty?
        raise OptimizerWrapper::DiscordantProblemError.new('Zip cluster: no intersecting tw could be found')
      end

      new_services[i].activity.timewindows = (new_tws - to_remove_tws).compact
    end

    # Fill new vrp
    vrp.services = new_services

    clusterer.clusters
  end

  def self.unzip_cluster(result, zip_key, original_vrp)
    return result unless zip_key

    activities = []

    if result[:unassigned] && !result[:unassigned].empty?
      result[:routes] << {
        vehicle_id: 'unassigned',
        activities: result[:unassigned]
      }
    end

    routes = result[:routes].collect{ |route|
      vehicle = (original_vrp.vehicles.find{ |v| v[:id] == route[:vehicle_id] }) || original_vrp.vehicles[0]
      new_activities = []
      activities = route[:activities].collect.with_index{ |activity, idx_a|
        idx_s = original_vrp.services.index{ |s| s.id == activity[:service_id] }
        idx_z = zip_key.index{ |z| z.data_items.flatten.include? idx_s }
        if idx_z && idx_z < zip_key.length && zip_key[idx_z].data_items.length > 1
          sub = zip_key[idx_z].data_items.collect{ |i| i[0] }
          matrix = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[original_vrp.vehicles[0].router_dimension.to_sym]

          # Cluster start: Last non rest-without-location stop before current cluster
          start = new_activities.reverse.find{ |r| r[:service_id] }
          start_index = start ? original_vrp.services.index{ |s| s.id == start[:service_id] } : 0

          j = 0
          j += 1 while route[:activities][idx_a + j] && !route[:activities][idx_a + j][:service_id]

          stop_index = if route[:activities][idx_a + j] && route[:activities][idx_a + j][:service_id]
            original_vrp.services.index{ |s| s.id == route[:activities][idx_a + j][:service_id] }
          else
            original_vrp.services.length - 1
          end

          sub_size = sub.length
          min_order = if sub_size <= 5
            # Test all permutations inside cluster
            sub.permutation.collect{ |p|
              last = start_index
              sum = p.sum { |s|
                a, last = last, s
                matrix[original_vrp.services[a].activity.point.matrix_index][original_vrp.services[s].activity.point.matrix_index]
              } + matrix[original_vrp.services[p[-1]].activity.point.matrix_index][original_vrp.services[stop_index].activity.point.matrix_index]
              [sum, p]
            }.min_by{ |a| a[0] }[1]
          else
            # Run local optimization inside cluster
            sim_annealing = SimAnnealing::SimAnnealingVrp.new
            sim_annealing.start = start_index
            sim_annealing.stop = stop_index
            sim_annealing.matrix = matrix
            sim_annealing.vrp = original_vrp
            fact = (1..[sub_size, 8].min).reduce(1, :*) # Yes, compute factorial
            initial_order = [start_index] + sub + [stop_index]
            sub_size += 2
            r = sim_annealing.search(initial_order, fact, 100000.0, 0.999)[:vector]
            r = r.collect{ |i| initial_order[i] }
            index = r.index(start_index)
            if r[(index + 1) % sub_size] != stop_index && r[(index - 1) % sub_size] != stop_index
              # Not stop and start following
              sub
            else
              if r[(index + 1) % sub_size] == stop_index
                r.reverse!
                index = sub_size - 1 - index
              end
              r = (index == 0) ? r : r[index..-1] + r[0..index - 1] # shift to replace start at beginning
              r[1..-2] # remove start and stop from cluster
            end
          end
          last_index = start_index
          new_activities += min_order.collect{ |index|
            original_service = original_vrp.services[index]
            fake_wrapper = Wrappers::Wrapper.new
            a = {
              point_id: (original_service.activity.point_id if original_service.id),
              travel_time: (t = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:time]) ?
                t[original_vrp.services[last_index].activity.point.matrix_index][original_service.activity.point.matrix_index] : 0,
              travel_value: (v = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:value]) ?
                v[original_vrp.services[last_index].activity.point.matrix_index][original_service.activity.point.matrix_index] : 0,
              travel_distance: (d = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:distance]) ?
                d[original_vrp.services[last_index].activity.point.matrix_index][original_service.activity.point.matrix_index] : 0, # TODO: from matrix_distance
              # travel_start_time: 0, # TODO: from matrix_time
              # arrival_time: 0, # TODO: from matrix_time
              # departure_time: 0, # TODO: from matrix_time
              service_id: original_service.id,
              type: :service,
              detail: fake_wrapper.build_detail(original_service,
                                                     original_service.activity,
                                                     original_service.activity.point,
                                                     vehicle.global_day_index ? vehicle.global_day_index % 7 : nil,
                                                     nil, vehicle)
            }.delete_if { |_k, v| !v }
            last_index = index
            a
          }
        else
          new_activities << activity
        end
      }.flatten.uniq
      {
        vehicle_id: route[:vehicle_id],
        activities: activities,
        total_distance: route[:total_distance] || 0,
        total_time: route[:total_time] || 0,
        total_travel_time: route[:total_travel_time] || 0,
        total_travel_value: route[:total_travel_value] || 0,
        geometry: route[:geometry]
      }.delete_if{ |_k, v| v.nil? }
    }
    result[:unassigned] = (routes.find{ |route| route[:vehicle_id] == 'unassigned' }) ? routes.find{ |route| route[:vehicle_id] == 'unassigned' }[:activities] : []
    result[:routes] = routes.reject{ |route| route[:vehicle_id] == 'unassigned' }
    result
  end
end

module SimAnnealing
  class SimAnnealingVrp < SimAnnealing
    attr_accessor :start, :stop, :matrix, :vrp

    def euc_2d(c1, c2)
      if [start, stop].include?(c1) && [start, stop].include?(c2)
        0
      else
        matrix[vrp.services[c1].activity.point.matrix_index][vrp.services[c2].activity.point.matrix_index]
      end
    end
  end
end
