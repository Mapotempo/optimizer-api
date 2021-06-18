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
require 'i18n'
require 'resque'
require 'resque-status'
require 'redis'
require 'json'
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

require 'ai4r'
include Ai4r::Data
require './lib/clusterers/complete_linkage_max_distance.rb'
include Ai4r::Clusterers
require 'sim_annealing'

require 'rgeo/geo_json'

module OptimizerWrapper
  REDIS = Resque.redis

  def self.config
    @@c
  end

  def self.access(force_load = false)
    load config[:access_by_api_key][:file] || './config/access.rb' if force_load
    @access_by_api_key
  end

  def self.dump_vrp_dir
    @@dump_vrp_dir
  end

  def self.dump_vrp_dir=(dir)
    @@dump_vrp_dir = dir
  end

  def self.router
    @router ||= Routers::RouterWrapper.new(ActiveSupport::Cache::NullStore.new, ActiveSupport::Cache::NullStore.new, config[:router][:api_key])
  end

  def self.wrapper_vrp(api_key, services, vrp, checksum, job_id = nil)
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
        service: services[:services][:vrp].find{ |s|
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
      # Delegate the job to a worker
      job_id = Job.enqueue_to(services[:queue], Job, services_vrps: Base64.encode64(Marshal.dump(services_vrps)),
                                                     api_key: api_key,
                                                     checksum: checksum,
                                                     pids: [])
      JobList.add(api_key, job_id)
      job_id
    end
  end

  def self.define_main_process(services_vrps, job = nil, &block)
    log "--> define_main_process #{services_vrps.size} VRPs", level: :info
    log "activities: #{services_vrps.map{ |sv| sv[:vrp].services.size + sv[:vrp].shipments.size * 2 }}", level: :info
    log "vehicles: #{services_vrps.map{ |sv| sv[:vrp].vehicles.size }}", level: :info
    log "resolution_vehicle_limit: #{services_vrps.map{ |sv| sv[:vrp].resolution_vehicle_limit }}", level: :info
    log "min_durations: #{services_vrps.map{ |sv| sv[:vrp].resolution_minimum_duration&.round }}", level: :info
    log "max_durations: #{services_vrps.map{ |sv| sv[:vrp].resolution_duration&.round }}", level: :info
    tic = Time.now

    expected_activity_count = services_vrps.collect{ |sv| sv[:vrp].visits }.sum

    several_service_vrps = Interpreters::SeveralSolutions.expand_several_solutions(services_vrps)

    several_results = several_service_vrps.collect.with_index{ |current_service_vrps, solution_index|
      callback_main = lambda { |wrapper, avancement, total, message, cost = nil, time = nil, solution = nil|
        msg = "#{"solution: #{solution_index + 1}/#{several_service_vrps.size} - " if several_service_vrps.size > 1}#{message}" unless message.nil?
        block&.call(wrapper, avancement, total, msg, cost, time, solution)
      }

      join_independent_vrps(current_service_vrps, callback_main) { |service_vrp, callback_join|
        repeated_results = []

        service_vrp_repeats = Interpreters::SeveralSolutions.expand_repeat(service_vrp)

        service_vrp_repeats.each_with_index{ |repeated_service_vrp, repetition_index|
          repeated_results << define_process(repeated_service_vrp, job) { |wrapper, avancement, total, message, cost, time, solution|
            msg = "#{"repetition #{repetition_index + 1}/#{service_vrp_repeats.size} - " if service_vrp_repeats.size > 1}#{message}" unless message.nil?
            callback_join&.call(wrapper, avancement, total, msg, cost, time, solution)
          }
        }

        (result, position) = repeated_results.each.with_index(1).min_by { |result, _| result[:unassigned].size } # find the best result and its index
        log "#{job}_repetition - #{repeated_results.collect{ |r| r[:unassigned].size }} : chose to keep the #{position.ordinalize} solution"
        result
      }
    }

    check_result_consistency(expected_activity_count, several_results) if services_vrps.collect{ |sv| sv[:service] } != [:demo] # demo solver returns a fixed solution

    nb_routes = several_results.sum{ |result| result[:routes].count{ |r| r[:activities].any?{ |a| a[:service_id] || a[:original_shipment_id] } } }
    nb_unassigned = several_results.sum{ |result| result[:unassigned].size }
    percent_unassigned = (100.0 * nb_unassigned / expected_activity_count).round(1)

    log "result - #{nb_unassigned} of #{expected_activity_count} (#{percent_unassigned}%) unassigned activities"
    log "result - #{nb_routes} of #{services_vrps.sum{ |sv| sv[:vrp].vehicles.size }} vehicles used"

    several_results
  ensure
    log "<-- define_main_process elapsed: #{(Time.now - tic).round(2)} sec", level: :info
  end

  # Mutually recursive method
  def self.define_process(service_vrp, job = nil, &block)
    vrp = service_vrp[:vrp]
    dicho_level = service_vrp[:dicho_level].to_i
    split_level = service_vrp[:split_level].to_i
    log "--> define_process VRP (service: #{vrp.services.size}, shipment: #{vrp.shipments.size}, vehicle: #{vrp.vehicles.size}, v_limit: #{vrp.resolution_vehicle_limit}) with levels (dicho: #{dicho_level}, split: #{split_level})", level: :info
    log "min_duration #{vrp.resolution_minimum_duration&.round} max_duration #{vrp.resolution_duration&.round}", level: :info

    tic = Time.now
    expected_activity_count = vrp.visits

    result ||= Interpreters::SplitClustering.split_clusters(service_vrp, job, &block)        # Calls recursively define_process

    result ||= Interpreters::Dichotomious.dichotomious_heuristic(service_vrp, job, &block)   # Calls recursively define_process

    result ||= solve(service_vrp, job, block)

    check_result_consistency(expected_activity_count, result) if service_vrp[:service] != :demo # demo solver returns a fixed solution

    log "<-- define_process levels (dicho: #{dicho_level}, split: #{split_level}) elapsed: #{(Time.now - tic).round(2)} sec", level: :info
    result
  end

  def self.solve(service_vrp, job = nil, block = nil)
    vrp = service_vrp[:vrp]
    service = service_vrp[:service]
    dicho_level = service_vrp[:dicho_level]
    log "--> optim_wrap::solve VRP (service: #{vrp.services.size}, shipment: #{vrp.shipments.size} vehicle: #{vrp.vehicles.size} v_limit: #{vrp.resolution_vehicle_limit}) with levels (dicho: #{service_vrp[:dicho_level]}, split: #{service_vrp[:split_level].to_i})", level: :debug

    tic = Time.now

    optim_result = nil

    unfeasible_services = []

    if !vrp.subtours.empty?
      multi_modal = Interpreters::MultiModal.new(vrp, service)
      optim_result = multi_modal.multimodal_routes
    elsif vrp.vehicles.empty? || (vrp.services.empty? && vrp.shipments.empty?)
      optim_result = config[:services][service].empty_result(
        service.to_s, vrp, 'No vehicle available for this service', false)
    else
      services_to_reinject = []
      sub_unfeasible_services = config[:services][service].detect_unfeasible_services(vrp)

      vrp.compute_matrix(&block)

      sub_unfeasible_services = config[:services][service].check_distances(vrp, sub_unfeasible_services)
      vrp.clean_according_to(sub_unfeasible_services)

      # Remove infeasible services
      sub_unfeasible_services.each{ |una_service|
        index = vrp.services.find_index{ |s| una_service[:original_service_id] == s.id }
        if index
          services_to_reinject << vrp.services.slice!(index)
        end
      }

      # TODO: refactor with dedicated class
      if vrp.scheduling?
        periodic = Interpreters::PeriodicVisits.new(vrp)
        vrp = periodic.expand(vrp, job, &block)
        optim_result = parse_result(vrp, vrp.preprocessing_heuristic_result) if vrp.periodic_heuristic?
      end

      unfeasible_services += sub_unfeasible_services
      if vrp.resolution_solver && !vrp.periodic_heuristic?
        block&.call(nil, nil, nil, "process clique clustering : threshold (#{vrp.preprocessing_cluster_threshold.to_f}) ", nil, nil, nil) if vrp.preprocessing_cluster_threshold.to_f.positive?
        optim_result = clique_cluster(vrp, vrp.preprocessing_cluster_threshold, vrp.preprocessing_force_cluster) { |cliqued_vrp|
          time_start = Time.now

          OptimizerWrapper.config[:services][service].simplify_constraints(cliqued_vrp)

          block&.call(nil, 0, nil, 'run optimization', nil, nil, nil) if dicho_level.nil? || dicho_level.zero?

          # TODO: Move select best heuristic in each solver
          Interpreters::SeveralSolutions.custom_heuristics(service, vrp, block)

          cliqued_result = OptimizerWrapper.config[:services][service].solve(
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
              if solution.is_a?(Hash)
                OptimizerWrapper.config[:services][service].patch_simplified_constraints_in_result(solution, cliqued_vrp)
              end
            block&.call(wrapper, avancement, total, 'run optimization, iterations', cost, (Time.now - time_start) * 1000, solution) if dicho_level.nil? || dicho_level.zero?
          }

          OptimizerWrapper.config[:services][service].patch_and_rewind_simplified_constraints(cliqued_vrp, cliqued_result)

          if cliqued_result.is_a?(Hash)
            # cliqued_result[:elapsed] = (Time.now - time_start) * 1000 # Can be overridden in wrappers
            block&.call(nil, nil, nil, "process #{vrp.resolution_split_number}/#{vrp.resolution_total_split_number} - " + 'run optimization' + " - elapsed time #{(Result.time_spent(cliqued_result[:elapsed]) / 1000).to_i}/" + "#{vrp.resolution_total_duration / 1000} ", nil, nil, nil) if dicho_level&.positive?
            parse_result(cliqued_vrp, cliqued_result)
          elsif cliqued_result == 'Job killed'
            next
          elsif cliqued_result.is_a?(String)
            raise RuntimeError, cliqued_result
          elsif (vrp.preprocessing_heuristic_result.nil? || vrp.preprocessing_heuristic_result.empty?) && !vrp.restitution_allow_empty_result
            puts cliqued_result
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
      optim_result[:unassigned] = (optim_result[:unassigned] || []) + unfeasible_services

      if vrp.preprocessing_first_solution_strategy
        optim_result[:heuristic_synthesis] = vrp.preprocessing_heuristic_synthesis
      end
    end

    log "<-- optim_wrap::solve elapsed: #{(Time.now - tic).round(2)}sec", level: :debug

    optim_result
  end

  def self.split_independent_vrp_by_skills(vrp)
    mission_skills = (vrp.services.map(&:skills) + vrp.shipments.map(&:skills)).uniq
    return [vrp] if mission_skills.include?([])

    # Generate Services data
    grouped_services = vrp.services.group_by(&:skills)
    skill_service_ids = Hash.new{ [] }
    grouped_services.each{ |skills, missions| skill_service_ids[skills] += missions.map(&:id) }

    # Generate Shipments data
    grouped_shipments = vrp.shipments.group_by(&:skills)
    skill_shipment_ids = Hash.new{ [] }
    grouped_shipments.each{ |skills, missions| skill_shipment_ids[skills] += missions.map(&:id) }

    # Generate Vehicles data
    ### Be careful in case the alternative skills are supported again !
    grouped_vehicles = vrp.vehicles.group_by{ |vehicle| vehicle.skills.flatten }
    vehicle_skills = grouped_vehicles.keys.uniq
    skill_vehicle_ids = Hash.new{ [] }
    grouped_vehicles.each{ |skills, vehicles| skill_vehicle_ids[skills] += vehicles.map{ |vehicle| vrp.vehicles.find_index(vehicle) } }

    independent_skills = Array.new(mission_skills.size) { |i| [i] }

    # Build the compatibility table between service and vehicle skills
    # As reminder vehicle skills are defined as an OR condition
    # When the services skills are defined as an AND condition
    compatibility_table = mission_skills.map.with_index{ |_skills, _index| Array.new(vehicle_skills.size) { false } }
    mission_skills.each.with_index{ |m_skills, m_index|
      vehicle_skills.each.with_index{ |v_skills, v_index|
        compatibility_table[m_index][v_index] = true if (v_skills & m_skills) == m_skills
      }
    }

    mission_skills.size.times.each{ |a_line|
      ((a_line + 1)..mission_skills.size - 1).each{ |b_line|
        next if (compatibility_table[a_line].select.with_index{ |state, index| state & compatibility_table[b_line][index] }).empty?

        b_set = independent_skills.find{ |set| set.include?(b_line) && set.exclude?(a_line) }
        next if b_set.nil?

        # Skills indices are merged as they have at least a vehicle in common
        independent_skills.delete(b_set)
        set_index = independent_skills.index{ |set| set.include?(a_line) }
        independent_skills[set_index] += b_set
      }
    }

    # Original skills are retrieved
    independant_skill_sets = independent_skills.map{ |index_set|
      index_set.collect{ |index| mission_skills[index] }
    }

    unused_vehicles_indices = (0..vrp.vehicles.size - 1).to_a
    independent_vrps = independant_skill_sets.collect{ |skills_set|
      # Compatible problem ids are retrieved
      vehicles_indices = skills_set.flat_map{ |skills| skill_vehicle_ids.select{ |k, _v| (k & skills) == skills }.flat_map{ |_k, v| v } }.uniq
      vehicles_indices.each{ |index| unused_vehicles_indices.delete(index) }
      service_ids = skills_set.flat_map{ |skills| skill_service_ids[skills] }
      shipment_ids = skills_set.flat_map{ |skills| skill_shipment_ids[skills] }
      service_vrp = {
        service: nil,
        vrp: vrp,
      }

      sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp(service_vrp, service_ids + shipment_ids, vehicles_indices)
      sub_service_vrp[:vrp]
    }

    total_size = independent_vrps.collect{ |s_s_v| (s_s_v.services.size + s_s_v.shipments.size) * [1, s_s_v.vehicles.size].min }.sum
    independent_vrps.each{ |sub_service_vrp|
      # If one sub_service_vrp has no vehicle or no service, duration can be zero.
      # We only split duration among sub_service_vrps that have at least one vehicle and one service.
      this_sub_vrp_size = (sub_service_vrp.services.size + sub_service_vrp.shipments.size) * [1, sub_service_vrp.vehicles.size].min

      split_ratio = this_sub_vrp_size / total_size.to_f
      sub_service_vrp.resolution_duration = vrp.resolution_duration&.*(split_ratio)&.ceil
      sub_service_vrp.resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out)&.*(split_ratio)&.ceil
      sub_service_vrp.resolution_iterations_without_improvment = vrp.resolution_iterations_without_improvment&.*(split_ratio)&.ceil
    }

    return independent_vrps if unused_vehicles_indices.empty?

    sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp({ vrp: vrp }, [], unused_vehicles_indices)
    sub_service_vrp[:vrp].matrices = []
    independent_vrps.push(sub_service_vrp[:vrp])

    independent_vrps
  end

  def self.split_independent_vrp_by_sticky_vehicle(vrp)
    vrp.vehicles.map.with_index{ |vehicle, v_i|
      vehicle_id = vehicle.id
      service_ids = vrp.services.select{ |s| s.sticky_vehicles.map(&:id) == [vehicle_id] }.map(&:id)
      shipment_ids = vrp.shipments.select{ |s| s.sticky_vehicles.map(&:id) == [vehicle_id] }.map(&:id)

      service_vrp = {
        service: nil,
        vrp: vrp,
      }
      sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp(service_vrp, service_ids + shipment_ids, [v_i])
      split_ratio = 1.0 / vrp.vehicles.size
      sub_service_vrp[:vrp].resolution_duration = vrp.resolution_duration&.*(split_ratio)&.ceil
      sub_service_vrp[:vrp].resolution_minimum_duration = (vrp.resolution_minimum_duration || vrp.resolution_initial_time_out)&.*(split_ratio)&.ceil
      sub_service_vrp[:vrp].resolution_iterations_without_improvment = vrp.resolution_iterations_without_improvment&.*(split_ratio)&.ceil
      sub_service_vrp[:vrp]
    }
  end

  def self.split_independent_vrp(vrp)
    # Don't split vrp if
    return [vrp] if (vrp.vehicles.size <= 1) ||
                    (vrp.services.empty? && vrp.shipments.empty?) # there might be zero services or shipments (check together)

    if vrp.services.all?{ |s| s.sticky_vehicles.size == 1 } && vrp.shipments.all?{ |s| s.sticky_vehicles.size == 1 }
      return split_independent_vrp_by_sticky_vehicle(vrp)
    end

    if !vrp.subtours&.any? && # Cannot split if there is multimodal subtours
       vrp.services.all?{ |s| s.sticky_vehicles.empty? } &&
       vrp.shipments.all?{ |s| s.sticky_vehicles.empty? }
      return split_independent_vrp_by_skills(vrp)
    end

    [vrp]
  end

  def self.join_independent_vrps(services_vrps, callback)
    results = services_vrps.each_with_index.map{ |service_vrp, i|
      block = if services_vrps.size > 1 && !callback.nil?
                proc { |wrapper, avancement, total, message, cost = nil, time = nil, solution = nil|
                  msg = "process #{i + 1}/#{services_vrps.size} - #{message}" unless message.nil?
                  callback&.call(wrapper, avancement, total, msg, cost, time, solution)
                }
              else
                callback
              end
      yield(service_vrp, block)
    }

    Helper.merge_results(results, true)
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

  def self.find_type(activity)
    if activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id] || activity[:shipment_id]
      'visit'
    elsif activity[:rest_id]
      'rest'
    elsif activity[:point_id]
      'store'
    end
  end

  def self.build_csv(solutions)
    header = ['vehicle_id', 'id', 'point_id', 'lat', 'lon', 'type', 'waiting_time', 'begin_time', 'end_time', 'setup_duration', 'duration', 'additional_value', 'skills', 'tags', 'total_travel_time', 'total_travel_distance', 'total_waiting_time']
    quantities_header = []
    unit_ids = []
    optim_planning_output = nil
    max_timewindows_size = 0
    reasons = nil
    solutions&.collect{ |solution|
      solution[:routes].each{ |route|
        route[:activities].each{ |activity|
          next if activity[:detail].nil? || !activity[:detail][:quantities]

          activity[:detail][:quantities].each{ |quantity|
            unit_ids << quantity[:unit]
            quantities_header << "quantity_#{quantity['label'] || quantity[:unit]}"
          }
        }
      }
      quantities_header.uniq!
      unit_ids.uniq!

      max_timewindows_size = ([max_timewindows_size] + solution[:routes].collect{ |route|
        route[:activities].collect{ |activity|
          next if activity[:detail].nil? || !activity[:detail][:timewindows]

          activity[:detail][:timewindows].collect{ |tw| [tw[:start], tw[:end]] }.uniq.size
        }.compact
      }.flatten +
      solution[:unassigned].collect{ |activity|
        next if activity[:detail].nil? || !activity[:detail][:timewindows]

        activity[:detail][:timewindows].collect{ |tw| [tw[:start], tw[:end]] }.uniq.size
      }.compact).max
      timewindows_header = (0..max_timewindows_size.to_i - 1).collect{ |index|
        ["timewindow_start_#{index}", "timewindow_end_#{index}"]
      }.flatten
      header += quantities_header + timewindows_header
      reasons = true if solution[:unassigned].size.positive?

      optim_planning_output = solution[:routes].any?{ |route| route[:activities].any?{ |stop| stop[:day_week] } }
    }
    CSV.generate{ |out_csv|
      if optim_planning_output
        header = ['day_week_num', 'day_week'] + header
      end
      if reasons
        header << 'unassigned_reason'
      end
      out_csv << header
      (solutions.is_a?(Array) ? solutions : [solutions]).collect{ |solution|
        solution[:routes].each{ |route|
          route[:activities].each{ |activity|
            days_info = optim_planning_output ? [activity[:day_week_num], activity[:day_week]] : []
            common = build_csv_activity(solution[:name], route, activity)
            timewindows = build_csv_timewindows(activity, max_timewindows_size)
            quantities = unit_ids.collect{ |unit_id|
              activity[:detail][:quantities]&.find{ |quantity| quantity[:unit] == unit_id } && activity[:detail][:quantities]&.find{ |quantity| quantity[:unit] == unit_id }[:value]
            }
            out_csv << (days_info + common + quantities + timewindows + [nil])
          }
        }
        solution[:unassigned].each{ |activity|
          days_info = optim_planning_output ? [activity[:day_week_num], activity[:day_week]] : []
          common = build_csv_activity(solution[:name], nil, activity)
          timewindows = build_csv_timewindows(activity, max_timewindows_size)
          quantities = unit_ids.collect{ |unit_id|
            activity[:detail][:quantities]&.find{ |quantity| quantity[:unit] == unit_id } && activity[:detail][:quantities]&.find{ |quantity| quantity[:unit] == unit_id }[:value]
          }
          out_csv << (days_info + common + quantities + timewindows + [activity[:reason]])
        }
      }
    }
  end

  private

  def self.check_result_consistency(expected_value, results)
    [results].flatten(1).each{ |result|
      nb_assigned = result[:routes].sum{ |route| route[:activities].count{ |a| a[:service_id] || a[:pickup_shipment_id] || a[:delivery_shipment_id] } }
      nb_unassigned = result[:unassigned].count{ |unassigned| unassigned[:service_id] || unassigned[:pickup_shipment_id] || unassigned[:delivery_shipment_id] }

      if expected_value != nb_assigned + nb_unassigned # rubocop:disable Style/Next for error handling
        log "Expected: #{expected_value} Have: #{nb_assigned + nb_unassigned} activities"
        log 'Wrong number of visits returned in result', level: :warn
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

  def self.round_route_stats(route)
    [:end_time, :start_time].each{ |key|
      next unless route[key]

      route[key] = route[key].round
    }

    route[:activities].each{ |activity|
      [:begin_time, :current_distance, :departure_time, :end_time,
       :travel_distance, :travel_time, :travel_value, :waiting_time].each{ |key|
        next unless activity[key]

        activity[key] = activity[key].round
      }
    }
  end

  def self.compute_route_total_dimensions(vrp, route, matrix)
    previous = nil
    dimensions = []
    dimensions << :time if matrix&.time
    dimensions << :distance if matrix&.distance
    dimensions << :value if matrix&.value

    total = dimensions.collect.with_object({}) { |dimension, hash| hash[dimension] = 0 }
    route[:activities].each{ |activity|
      point = vrp.points.find{ |p| p.id == activity[:point_id] }&.matrix_index
      if previous && point
        dimensions.each{ |dimension|
          activity["travel_#{dimension}".to_sym] = matrix&.send(dimension)[previous][point]
          total[dimension] += activity["travel_#{dimension}".to_sym].round
          activity[:current_distance] ||= total[dimension].round if dimension == :distance
        }
      end

      previous = point
    }

    if route[:end_time] && route[:start_time]
      route[:total_time] = route[:end_time] - route[:start_time]
    end
    route[:total_travel_time] = total[:time].round if dimensions.include?(:time)
    route[:total_distance] = total[:distance].round if dimensions.include?(:distance)
    route[:total_travel_value] = total[:value].round if dimensions.include?(:value)

    return unless route[:activities].all?{ |a| a[:waiting_time] }

    route[:total_waiting_time] = route[:activities].collect{ |a| a[:waiting_time] }.sum.round
  end

  def self.compute_result_total_dimensions_and_round_route_stats(result)
    [:total_time, :total_travel_time, :total_travel_value, :total_distance, :total_waiting_time].each{ |stat_symbol|
      next unless result[:routes].all?{ |r| r[stat_symbol] }

      result[stat_symbol] = result[:routes].collect{ |r|
        r[stat_symbol]
      }.reduce(:+)
    }

    result[:routes].each{ |r|
      round_route_stats(r)
    }
  end

  def self.compute_route_waiting_times(route)
    seen = 1
    previous_end =
      if route[:activities].first[:type] == 'depot'
        route[:activities].first[:begin_time]
      else
        route[:activities].first[:end_time]
      end
    route[:activities].first[:waiting_time] = 0

    first_service_seen = true
    while seen < route[:activities].size
      considered_setup =
        if route[:activities][seen][:type] == 'rest'
          0
        elsif first_service_seen || route[:activities][seen][:travel_time].positive?
          route[:activities][seen][:detail][:setup_duration] || 0
        else
          0
        end
      first_service_seen = false if %w[service pickup delivery].include?(route[:activities][seen][:type])
      arrival_time = previous_end + (route[:activities][seen][:travel_time] || 0) + considered_setup
      route[:activities][seen][:waiting_time] = route[:activities][seen][:begin_time] - arrival_time
      previous_end = route[:activities][seen][:end_time]
      seen += 1
    end
  end

  def self.build_csv_activity(name, route, activity)
    type = find_type(activity)
    [
      route && route[:vehicle_id],
      build_complete_id(activity),
      activity[:point_id],
      activity[:detail][:lat],
      activity[:detail][:lon],
      type,
      formatted_duration(activity[:waiting_time]),
      formatted_duration(activity[:begin_time]),
      formatted_duration(activity[:end_time]),
      formatted_duration(activity[:detail][:setup_duration] || 0),
      formatted_duration(activity[:detail][:duration] || 0),
      activity[:detail][:additional_value] || 0,
      activity[:detail][:skills].to_a.empty? ? nil : activity[:detail][:skills].to_a.flatten.join(','),
      name,
      route && formatted_duration(route[:total_travel_time]),
      route && route[:total_distance],
      route && formatted_duration(route[:total_waiting_time]),
    ].flatten
  end

  def self.build_complete_id(activity)
    return activity[:service_id] if activity[:service_id]

    return "#{activity[:pickup_shipment_id]}_pickup" if activity[:pickup_shipment_id]

    return "#{activity[:delivery_shipment_id]}_delivery" if activity[:delivery_shipment_id]

    return "#{activity[:shipment_id]}_#{activity['type']}" if activity[:shipment_id]

    activity[:rest_id] || activity[:point_id]
  end

  def self.build_csv_timewindows(activity, max_timewindows_size)
    (0..max_timewindows_size - 1).collect{ |index|
      if activity[:detail][:timewindows] && index < activity[:detail][:timewindows].collect{ |tw| [tw[:start], tw[:end]] }.uniq.size
        timewindow = activity[:detail][:timewindows].select{ |tw| [tw[:start], tw[:end]] }.uniq.sort_by{ |t| t[:start] }[index]
        [timewindow[:start] && formatted_duration(timewindow[:start]), timewindow[:end] && formatted_duration(timewindow[:end])]
      else
        [nil, nil]
      end
    }.flatten
  end

  def self.route_details(vrp, route, vehicle)
    previous = nil
    details = nil
    segments = route[:activities].reverse.collect{ |activity|
      current =
        if activity[:rest_id]
          previous
        else
          vrp.points.find{ |point| point.id == activity[:point_id] }
        end
      segment =
        if previous && current
          [current[:location][:lat], current[:location][:lon], previous[:location][:lat], previous[:location][:lon]]
        end
      previous = current
      segment
    }.reverse.compact

    unless segments.empty?
      details = OptimizerWrapper.router.compute_batch(OptimizerWrapper.config[:router][:url],
                                                      vehicle.router_mode.to_sym, vehicle.router_dimension,
                                                      segments, vrp.restitution_geometry.include?(:encoded_polyline),
                                                      vehicle.router_options)
      raise RouterError.new('Route details cannot be received') unless details
    end

    details&.each{ |d| d[0] = (d[0] / 1000.0).round(4) if d[0] }
    details
  end

  def self.compute_route_travel_distances(vrp, matrix, route, vehicle)
    return nil unless matrix&.distance.nil? && route[:activities].size > 1 && vrp.points.all?(&:location)

    details = route_details(vrp, route, vehicle)

    return nil unless details && !details.empty?

    route[:activities][1..-1].each_with_index{ |activity, index|
      activity[:travel_distance] = details[index]&.first
    }

    details
  end

  def self.fill_missing_route_data(vrp, route, matrix, vehicle, solvers)
    route[:original_vehicle_id] = vrp.vehicles.find{ |v| v.id == route[:vehicle_id] }.original_id
    route[:day] = route[:vehicle_id].split('_').last.to_i unless route[:original_vehicle_id] == route[:vehicle_id]
    details = compute_route_travel_distances(vrp, matrix, route, vehicle)
    compute_route_waiting_times(route) unless route[:activities].empty? || solvers.include?('vroom')

    if route[:end_time] && route[:start_time]
      route[:total_time] = route[:end_time] - route[:start_time]
    end

    compute_route_total_dimensions(vrp, route, matrix)

    return unless ([:polylines, :encoded_polylines] & vrp.restitution_geometry).any? && route[:activities].size > 1 &&
                  route[:activities].count{ |i| ['service', 'pickup', 'delivery'].include?(i[:type]) } > 0

    details ||= route_details(vrp, route, vehicle)
    route[:geometry] = details&.map(&:last)
  end

  def self.empty_route(vrp, vehicle)
    route_start_time = [[vehicle.timewindow], vehicle.sequence_timewindows].compact.flatten[0]&.start.to_i
    route_end_time = route_start_time
    {
      vehicle_id: vehicle.id,
      original_vehicle_id: vehicle.original_id,
      cost_details: Models::CostDetails.new({}),
      activities: [], # TODO: check if depot activities are needed
                      # or-tools returns depot_start -> depot_end for empty vehicles
                      # in that case route_end_time needs to be corrected
      start_time: route_start_time,
      end_time: route_end_time,
      initial_loads: vrp.units.collect{ |unit| { unit: unit.id, label: unit.label, value: 0 } }
    }
  end

  def self.parse_result(vrp, result)
    tic_parse_result = Time.now
    vrp.vehicles.each{ |vehicle|
      route = result[:routes].find{ |r| r[:vehicle_id] == vehicle.id }
      unless route
        # there should be one route per vehicle in result :
        route = empty_route(vrp, vehicle)
        result[:routes] << route
      end
      matrix = vrp.matrices.find{ |mat| mat.id == vehicle.matrix_id }
      fill_missing_route_data(vrp, route, matrix, vehicle, result[:solvers])
    }
    compute_result_total_dimensions_and_round_route_stats(result)

    log "result - unassigned rate: #{result[:unassigned].size} of (ser: #{vrp.visits}, ship: #{vrp.shipments.size}) (#{(result[:unassigned].size.to_f / (vrp.visits + 2 * vrp.shipments.size) * 100).round(1)}%)"
    used_vehicle_count = result[:routes].count{ |r| r[:activities].any?{ |a| a[:service_id] || a[:pickup_shipment_id] } }
    log "result - #{used_vehicle_count}/#{vrp.vehicles.size}(limit: #{vrp.resolution_vehicle_limit}) vehicles used: #{used_vehicle_count}"
    log "<---- parse_result elapsed: #{Time.now - tic_parse_result}sec", level: :debug

    result
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

      related_ids += vrp.shipments.collect{ |shipment|
        shipments_ids = []
        pickup_loc = shipment.pickup.point.location
        delivery_loc = shipment.delivery.point.location

        if zone.inside(pickup_loc[:lat], pickup_loc[:lon])
          shipment.skills += [zone[:id]]
          shipments_ids << shipment.id + 'pickup'
        end
        if zone.inside(delivery_loc[:lat], delivery_loc[:lon])
          shipment.skills += [zone[:id]]
          shipments_ids << shipment.id + 'delivery'
        end
        shipments_ids.uniq
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
    if vrp.matrices.size.positive? && vrp.shipments.size.zero? && (cluster_threshold.to_f.positive? || force_cluster) && !vrp.scheduling?
      raise UnsupportedProblemError('Threshold is not supported yet if one service has serveral activies.') if vrp.services.any?{ |s| s.activities.size.positive? }

      original_services = Array.new(vrp.services.size){ |i| vrp.services[i].clone }
      zip_key = zip_cluster(vrp, cluster_threshold, force_cluster)
    end
    result = yield(vrp)
    if !vrp.matrices.empty? && vrp.shipments.empty? && (cluster_threshold.to_f.positive? || force_cluster) && !vrp.scheduling?
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
            a = {
              point_id: (original_vrp.services[index].activity.point_id if original_vrp.services[index].id),
              travel_time: (t = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:time]) ?
                t[original_vrp.services[last_index].activity.point.matrix_index][original_vrp.services[index].activity.point.matrix_index] : 0,
              travel_value: (v = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:value]) ?
                v[original_vrp.services[last_index].activity.point.matrix_index][original_vrp.services[index].activity.point.matrix_index] : 0,
              travel_distance: (d = original_vrp.matrices.find{ |m| m.id == vehicle.matrix_id }[:distance]) ?
                d[original_vrp.services[last_index].activity.point.matrix_index][original_vrp.services[index].activity.point.matrix_index] : 0, # TODO: from matrix_distance
              # travel_start_time: 0, # TODO: from matrix_time
              # arrival_time: 0, # TODO: from matrix_time
              # departure_time: 0, # TODO: from matrix_time
              service_id: original_vrp.services[index].id
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
