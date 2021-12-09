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

require_all 'lib'
require_all 'util'

module OptimizerWrapper
  def self.wrapper_vrp(api_key, profile, vrp, checksum, job_id = nil)
    inapplicable_services = []
    apply_zones(vrp)
    adjust_vehicles_duration(vrp)

    Filters.filter(vrp)

    vrp.configuration.resolution.repetition ||=
      if !vrp.configuration.preprocessing.partitions.empty? && vrp.periodic_heuristic?
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
            !vrp.configuration.preprocessing.cluster_threshold &&
            config[:services][services_vrps[0][:service]].solve_synchronous?(vrp)
          )
      # The job seems easy enough to perform it with the server
      define_main_process(services_vrps, job_id)
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
    log "configuration.resolution.vehicle_limit: #{services_vrps.map{ |sv| sv[:vrp].configuration.resolution.vehicle_limit }}", level: :info
    log "min_durations: #{services_vrps.map{ |sv| sv[:vrp].configuration.resolution.minimum_duration&.round }}", level: :info
    log "max_durations: #{services_vrps.map{ |sv| sv[:vrp].configuration.resolution.duration&.round }}", level: :info
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
        (result, position) = repeated_results.each.with_index(1).min_by { |rresult, _| rresult.unassigned.size } # find the best result and its index
        log "#{job}_repetition - #{repeated_results.collect{ |r| r.unassigned.size }} : chose to keep the #{position.ordinalize} solution"
        result
      }
    }

    # demo solver returns a fixed solution
    unless services_vrps.collect{ |sv| sv[:service] }.uniq == [:demo]
      check_solutions_consistency(expected_activity_count, several_solutions)
    end

    nb_routes = several_solutions.sum(&:count_assigned_services)
    nb_unassigned = several_solutions.sum(&:count_unassigned_services)
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
        "vehicle: #{vrp.vehicles.size}, v_limit: #{vrp.configuration.resolution.vehicle_limit}) " \
        "with levels (dicho: #{dicho_level}, split: #{split_level})", level: :info
    log "min_duration #{vrp.configuration.resolution.minimum_duration&.round} max_duration #{vrp.configuration.resolution.duration&.round}",
        level: :info

    tic = Time.now
    expected_activity_count = vrp.visits

    solution ||= Interpreters::SplitClustering.split_clusters(service_vrp, job, &block)        # Calls recursively define_process

    solution ||= Interpreters::Dichotomious.dichotomious_heuristic(service_vrp, job, &block)   # Calls recursively define_process

    solution ||= solve(service_vrp, job, block)

    check_solutions_consistency(expected_activity_count, [solution]) if service_vrp[:service] != :demo # demo solver returns a fixed solution
    log "<-- define_process levels (dicho: #{dicho_level}, split: #{split_level}) elapsed: #{(Time.now - tic).round(2)} sec", level: :info
    solution.configuration.deprecated_headers = vrp.configuration.restitution.use_deprecated_csv_headers
    solution
  end

  def self.solve(service_vrp, job = nil, block = nil)
    vrp = service_vrp[:vrp]
    service = service_vrp[:service]
    dicho_level = service_vrp[:dicho_level]
    shipment_size = vrp.relations.count{ |r| r.type == :shipment }
    log "--> optim_wrap::solve VRP (service: #{vrp.services.size} including #{shipment_size} shipment relations, " \
        "vehicle: #{vrp.vehicles.size} v_limit: #{vrp.configuration.resolution.vehicle_limit}) with levels " \
        "(dicho: #{service_vrp[:dicho_level]}, split: #{service_vrp[:split_level].to_i})", level: :debug

    tic = Time.now

    optim_solution = nil

    unfeasible_services = {}

    if !vrp.subtours.empty?
      multi_modal = Interpreters::MultiModal.new(vrp, service)
      optim_solution = multi_modal.multimodal_routes
    elsif vrp.vehicles.empty? || vrp.services.empty?
      unassigned_with_reason = vrp.services.map{ |s|
        Models::Solution::Stop.new(s, reason: 'No vehicle available for this service')
      }
      optim_solution = vrp.empty_solution(service.to_s, unassigned_with_reason, false)
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
        optim_solution = vrp.configuration.preprocessing.heuristic_result if vrp.periodic_heuristic?
      end

      if vrp.configuration.resolution.solver && !vrp.periodic_heuristic?
        block&.call(nil, nil, nil, "process clique clustering : threshold (#{vrp.configuration.preprocessing.cluster_threshold.to_f}) ", nil, nil, nil) if vrp.configuration.preprocessing.cluster_threshold.to_f.positive?
        optim_solution = clique_cluster(vrp, vrp.configuration.preprocessing.cluster_threshold, vrp.configuration.preprocessing.force_cluster) { |cliqued_vrp|
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

              result_object = Result.get(job) || { pids: [] }
              result_object[:pids] = pids
              Result.set(job, result_object)
            }
          ) { |wrapper, avancement, total, _message, cost, _time, solution|
            solution =
              if solution.is_a?(Models::Solution)
                OptimizerWrapper.config[:services][service].patch_simplified_constraints_in_solution(solution, cliqued_vrp)
              end
            block&.call(wrapper, avancement, total, 'run optimization, iterations', cost, (Time.now - time_start) * 1000, solution) if dicho_level.nil? || dicho_level.zero?
            solution
          }
          OptimizerWrapper.config[:services][service].patch_and_rewind_simplified_constraints(cliqued_vrp, cliqued_solution)

          if cliqued_solution.is_a?(Models::Solution)
            # cliqued_solution[:elapsed] = (Time.now - time_start) * 1000 # Can be overridden in wrappers
            block&.call(nil, nil, nil, "process #{vrp.configuration.resolution.split_number}/#{vrp.configuration.resolution.total_split_number} - " + 'run optimization' + " - elapsed time #{(Result.time_spent(cliqued_solution.elapsed) / 1000).to_i}/" + "#{vrp.configuration.resolution.total_duration / 1000} ", nil, nil, nil) if dicho_level&.positive?
            cliqued_solution
          elsif cliqued_solution.status == :killed
            next
          elsif cliqued_solution.is_a?(String)
            raise RuntimeError, cliqued_solution
          elsif (vrp.configuration.preprocessing.heuristic_result.nil? || vrp.configuration.preprocessing.heuristic_result.empty?) && !vrp.configuration.restitution.allow_empty_result
            puts cliqued_solution
            raise RuntimeError, 'No solution provided'
          end
        }
      end

      # Reintegrate unfeasible services deleted from vrp.services to help ortools
      vrp.services += services_to_reinject
    end

    if optim_solution # Job might have been killed
      Cleanse.cleanse(vrp, optim_solution)
      optim_solution.name = vrp.name
      optim_solution.configuration.csv = vrp.configuration.restitution.csv
      optim_solution.configuration.geometry = vrp.configuration.restitution.geometry
      optim_solution.unassigned += unfeasible_services.values.flatten
      optim_solution.parse(vrp)

      if vrp.configuration.preprocessing.first_solution_strategy
        optim_solution.heuristic_synthesis = vrp.configuration.preprocessing.heuristic_synthesis
      end
    else
      optim_solution = vrp.empty_solution(service, unfeasible_services.values)
    end

    log "<-- optim_wrap::solve elapsed: #{(Time.now - tic).round(2)}sec", level: :debug
    optim_solution
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
        compatibility_table[m_index][v_index] = true if (m_skills - v_skills).empty?
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

  def self.build_independent_vrps(vrp, skill_sets, vehicle_indices_by_skills, skill_service_ids)
    unused_vehicle_indices = (0..vrp.vehicles.size - 1).to_a
    independent_vrps = skill_sets.collect{ |skills_set|
      # Compatible problem ids are retrieved
      vehicle_indices = skills_set.flat_map{ |skills|
        vehicle_indices_by_skills.select{ |k, _v| (skills - k).empty? }.flat_map{ |_k, v| v }
      }.uniq
      vehicle_indices.each{ |index| unused_vehicle_indices.delete(index) }
      service_ids = skills_set.flat_map{ |skills| skill_service_ids[skills] }

      service_vrp = { service: nil, vrp: vrp }
      Interpreters::SplitClustering.build_partial_service_vrp(service_vrp,
                                                              service_ids,
                                                              vehicle_indices)[:vrp]
    }
    total_size = vrp.services.all?{ |service| service.sticky_vehicle_ids.any? } ? vrp.vehicles.size :
     independent_vrps.collect{ |s_vrp| s_vrp.services.size * [1, s_vrp.vehicles.size].min }.sum
    independent_vrps.each{ |sub_vrp|
      # If one sub vrp has no vehicle or no service, duration can be zero.
      # We only split duration among sub_service_vrps that have at least one vehicle and one service.
      this_sub_size = vrp.services.all?{ |service| service.sticky_vehicle_ids.any? } ? sub_vrp.vehicles.size :
        sub_vrp.services.size * [1, sub_vrp.vehicles.size].min
      adjust_independent_duration(sub_vrp, this_sub_size, total_size)
    }

    return independent_vrps if unused_vehicle_indices.empty?

    sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp({ vrp: vrp }, [], unused_vehicle_indices)
    independent_vrps.push(sub_service_vrp[:vrp])

    independent_vrps
  end

  def self.adjust_independent_duration(vrp, this_sub_size, total_size)
    split_ratio = this_sub_size.to_f / total_size
    vrp.configuration.resolution.duration = vrp.configuration.resolution.duration&.*(split_ratio)&.ceil
    vrp.configuration.resolution.minimum_duration =
      vrp.configuration.resolution.minimum_duration&.*(split_ratio)&.ceil
    vrp.configuration.resolution.iterations_without_improvment =
      vrp.configuration.resolution.iterations_without_improvment&.*(split_ratio)&.ceil
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
    if vrp.vehicles.any?{ |v| v.skills.size > 1 } # alternative skills
      log 'split_independent_vrp does not support alternative set of vehicle skills', level: :warn
      # Be careful in case the alternative skills are supported again !
      # The vehicle.skills.flatten down below won't work
      return [vrp]
    end
    grouped_vehicles = vrp.vehicles.group_by{ |vehicle| vehicle.skills.flatten }
    vehicle_skills = grouped_vehicles.keys.uniq
    vehicle_indices_by_skills = Hash.new{ [] }
    grouped_vehicles.each{ |skills, vehicles|
      vehicle_indices_by_skills[skills] += vehicles.map{ |vehicle| vrp.vehicles.find_index(vehicle) }
    }

    independent_skill_sets = compute_independent_skills_sets(vrp, mission_skills, vehicle_skills)

    build_independent_vrps(vrp, independent_skill_sets, vehicle_indices_by_skills, skill_service_ids)
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
      if solution.routes.any?{ |route| route.stops.any?{ |a| a.info.waiting_time < 0 } }
        log 'Computed waiting times are invalid', level: :warn
        raise RuntimeError, 'Computed waiting times are invalid' if ENV['APP_ENV'] != 'production'
      end

      waiting_times = solution.routes.map{ |route| route.info.total_waiting_time }.compact
      durations = solution.routes.map{ |route|
        route.stops.map{ |stop|
          stop.info.departure_time && (stop.info.departure_time - stop.info.begin_time)
        }.compact
      }
      setup_durations = solution.routes.map{ |route|
        route.stops.map{ |stop|
          next if stop.type == :rest

          (stop.info.travel_time.nil? || stop.info.travel_time&.positive?) && stop.activity.setup_duration || 0
        }.compact
      }
      total_time = solution.info.total_time || 0
      total_travel_time = solution.info.total_travel_time || 0
      if total_time != (total_travel_time || 0) +
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

      nb_assigned = solution.count_assigned_services
      nb_unassigned = solution.count_unassigned_services

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
      clusters = zip_cluster(vrp, cluster_threshold, force_cluster)
    end
    solution = yield(vrp)

    if @zip_condition
      vrp.services = original_services
      unzip_cluster(solution, clusters, vrp)
    else
      solution
    end
  end

  def self.zip_cluster(vrp, cluster_threshold, force_cluster)
    return nil if vrp.services.empty?

    c = Ai4r::Clusterers::CompleteLinkageMaxDistance.new

    matrix = vrp.matrices[0][vrp.vehicles[0].router_dimension.to_sym]

    c.distance_function =
      if force_cluster
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
        cost_late_multiplier = vrp.vehicles.all?{ |v| v.cost_late_multiplier && v.cost_late_multiplier != 0 }
        no_capacities = vrp.vehicles.all?{ |v| v.capacities&.empty? }

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

    data_set = Ai4r::Data::DataSet.new(data_items: (0..(vrp.services.length - 1)).collect{ |i| [i] })

    clusterer = c.build(data_set, cluster_threshold)

    new_size = clusterer.clusters.size

    # Build replacement list
    new_services = Array.new(new_size)
    clusterer.clusters.each_with_index do |cluster, i|
      new_services[i] = vrp.services[cluster.data_items[0][0]]
      new_services[i].activity.duration =
        cluster.data_items.map{ |di| vrp.services[di[0]].activity.duration }.reduce(&:+)
      next unless force_cluster

      new_quantities = []
      services_quantities = cluster.data_items.map{ |di|
        di.collect{ |index|
          vrp.services[index].quantities
        }.flatten
      }

      services_quantities.each{ |service_quantity|
        if new_quantities.empty?
          new_quantities = service_quantity
        else
          service_quantity.each{ |sub_quantity|
            if new_quantities.one?{ |new_quantity| new_quantity.unit.id == sub_quantity.unit.id }
              new_quantities.find{ |new_quantity|
                new_quantity.unit.id == sub_quantity.unit.id
              }.value += sub_quantity.value
            else
              new_quantities << sub_quantity
            end
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

  def self.unzip_cluster(solution, clusters, original_vrp)
    return solution unless clusters

    new_routes = solution.routes.map{ |route|
      last_point = nil
      new_stops = route.stops.flat_map.with_index{ |activity, act_index|
        if activity.service_id
          service_index = original_vrp.services.index{ |s| s.id == activity.service_id }
          cluster_index = clusters.index{ |z| z.data_items.flatten.include? service_index }
          if cluster_index && clusters[cluster_index].data_items.size > 1
            cluster_data_indices = clusters[cluster_index].data_items.collect{ |i| i[0] }
            cluster_services = cluster_data_indices.map{ |index| original_vrp.services[index] }
            next_point = route.stops[act_index + 1..route.stops.size].find{ |act|
              act.activity.point
            }&.activity&.point
            tsp = TSPHelper.create_tsp(original_vrp,
                                       vehicle: route.vehicle,
                                       services: cluster_services,
                                       start_point: last_point,
                                       end_point: next_point)
            solution = TSPHelper.solve(tsp)
            last_point = solution.routes[0].stops.reverse.find(&:service_id).activity.point
            service_ids = solution.routes[0].stops.select{ |a| a.type == :service }.map(&:id).compact
            service_ids.map{ |service_id|
              Models::Solution::Stop.new(original_vrp.services.find{ |service| service.id == service_id })
            }
          else
            activity
          end
        else
          last_point = activity.activity.point || last_point
          activity
        end
      }
      Models::Solution::Route.new(stops: new_stops, vehicle: route.vehicle)
    }
    new_unassigned = solution.unassigned.flat_map{ |un|
      if un.service_id
        service_index = original_vrp.services.index{ |s| s.id == un.service_id }
        cluster_index = clusters.index{ |z| z.data_items.flatten.include? service_index }
        if cluster_index && clusters[cluster_index].data_items.size > 1
          cluster_data_indices = clusters[cluster_index].data_items.collect{ |i| i[0] }
          cluster_data_indices.map{ |index|
            Models::Solution::Stop.new(original_vrp.services[index])
          }
        else
          un
        end
      else
        un
      end
    }
    solution = Models::Solution.new(routes: new_routes, unassigned: new_unassigned)
    solution.parse(original_vrp, compute_dimensions: true)
  end
end
