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
require 'thread'

require './util/job_manager.rb'

require './lib/routers/router_wrapper.rb'
require './lib/interpreters/multi_modal.rb'
require './lib/interpreters/multi_trips.rb'
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
    load './config/access.rb' if force_load
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
    # Get complete matrix in case of problem to dump
    if ENV['DUMP_VRP'] && vrp.name
      vrp.compute_matrix
      File.write('test/fixtures/' + vrp.name + '.dump', Base64.encode64(Marshal::dump(vrp)))
    end

    inapplicable_services = []
    apply_zones(vrp)
    adjust_vehicles_duration(vrp)

    services_vrps = split_independent_vrp(vrp).map.with_index{ |vrp_element, i|
      {
        service: services[:services][:vrp].find{ |s|
          inapplicable = config[:services][s].inapplicable_solve?(vrp_element)
          if inapplicable.empty?
            puts "Select service #{s}"
            true
          else
            inapplicable_services << inapplicable
            puts "Skip inapplicable #{s}: #{inapplicable.join(', ')}"
            false
          end
        },
        vrp: vrp_element,
        level: 0
      }
    }

    services_vrps = Filters::filter(services_vrps)

    # to make clustering more regular :
    services_vrps.each{ |service|
      next if service[:vrp].preprocessing_partitions.empty? ||
              !service[:vrp].preprocessing_first_solution_strategy.to_a.include?('periodic')

      service[:vrp].resolution_repetition = 3
    }

    if services_vrps.any?{ |sv| !sv[:service] }
      raise UnsupportedProblemError.new(inapplicable_services)
    elsif vrp.restitution_geometry && !vrp.points.all?{ |point| point[:location] }
      raise DiscordantProblemError.new("Geometry is not available if locations are not defined")
    else
      if config[:solve_synchronously] || (services_vrps.size == 1 && !vrp.preprocessing_cluster_threshold && config[:services][services_vrps[0][:service]].solve_synchronous?(vrp))
        # The job seems easy enough to perform it with the server
        define_process(services_vrps, job_id)
      else
        # Delegate the job to a worker
        job_id = Job.enqueue_to(services[:queue], Job, services_vrps: Base64.encode64(Marshal::dump(services_vrps)),
          api_key: api_key, checksum: checksum, pids: [])
        JobList.add(api_key, job_id)
        Result.get(job_id) || job_id
      end
    end
  end

  # Recursive method
  def self.define_process(services_vrps, job = nil, &block)
    filtered_services = services_vrps.delete_if{ |service_vrp| # TODO remove ?
      service_vrp[:vrp].services.empty? && service_vrp[:vrp].shipments.empty?
    }
    unduplicated_services, duplicated_services = Interpreters::SeveralSolutions.expand(filtered_services)
    duplicated_results = duplicated_services.compact.collect.with_index{ |service_vrp, repetition|
      define_process([service_vrp], job) { |wrapper, avancement, total, message, cost, time, solution|
        block&.call(wrapper, avancement, total, "repetition #{repetition + 1}/#{duplicated_services.size} - " + message, cost, time, solution)
      }
    }
    split_results = []
    definitive_service_vrps = unduplicated_services.collect{ |service_vrp|
      # Split/Clusterize the problem if too large
      unsplit_vrps, split_results = Interpreters::SplitClustering.split_clusters([service_vrp], job, &block) # Call recursively define_process
      unsplit_vrps
    }.flatten.compact
    dicho_results = []
    definitive_service_vrps.delete_if{ |service_vrp|
      dicho_result = Interpreters::Dichotomious.dichotomious_heuristic(service_vrp, job, &block) # Call recursively define_process
      dicho_results << dicho_result
      dicho_result
    }
    definitive_service_vrps.each{ |service_vrp| # TODO avant dicho ou dans solve ?
      multi = Interpreters::MultiTrips.new
      multi.expand(service_vrp[:vrp])
    }
    result = solve(definitive_service_vrps, job, block) if !definitive_service_vrps.empty? && dicho_results.compact.empty?
    if duplicated_results.size == services_vrps.first[:vrp][:resolution_repetition]
      result = duplicated_results.min_by{ |r| r[:unassigned].size }
      puts "#{job}_repetition - #{duplicated_results.collect{ |r| r[:unassigned].size }} : chose to keep #{duplicated_results.find_index(result)}"
      duplicated_results = [] # keep those results?
    end
    result_global = {
      result: ([result] + duplicated_results + split_results + dicho_results).compact
    }
    result_global[:result].size > 1 ? result_global[:result] : result_global[:result].first
  end

  def self.solve(services_vrps, job = nil, block = nil)
    unfeasible_services = []

    cluster_reference = 0
    real_result = join_independent_vrps(services_vrps, block) { |service, vrp, block|
      cluster_result = nil

      config[:services][service].clean_data(vrp)

      if !vrp.subtours.empty?
        multi_modal = Interpreters::MultiModal.new(vrp, service)
        cluster_result = multi_modal.multimodal_routes()
      else
        if vrp.vehicles.empty? # TODO remove ?
          cluster_result = {
            cost: nil,
            solvers: [service.to_s],
            iterations: nil,
            routes: [],
            unassigned: vrp.services.collect{ |service_|
              {
                service_id: service_[:id],
                point_id: service_[:activity] ? service_[:activity][:point_id] : nil,
                detail: {
                  lat: service_[:activity] ? service_[:activity][:point][:lat] : nil,
                  lon: service_[:activity] ? service_[:activity][:point][:lon] : nil,
                  setup_duration: service_[:activity] ? service_[:activity][:setup_duration] : nil,
                  duration: service_[:activity] ? service_[:activity][:duration] : nil,
                  timewindows: service_[:activity][:timewindows] && !service_[:activity][:timewindows].empty? ? [{
                    start: service_[:activity][:timewindows][0][:start],
                    end: service_[:activity][:timewindows][0][:start],
                  }] : [],
                  quantities: service_[:activity] ? service_[:quantities] : nil ,
                },
                reason: "No vehicle available for this service (split)"
              }
            },
            elapsed: nil,
            total_distance: nil
          }
        else
          services_to_reinject = []
          puts "Solving #{cluster_reference + 1}/#{services_vrps.size}" unless services_vrps.size == 1
          sub_unfeasible_services = config[:services][service].detect_unfeasible_services(vrp)

          vrp.compute_matrix(&block)

          sub_unfeasible_services = config[:services][service].check_distances(vrp, sub_unfeasible_services)
          unfeasible_services += sub_unfeasible_services

          vrp = config[:services][service].simplify_constraints(vrp)

          if !vrp.services.empty? || !vrp.shipments.empty? || !vrp.rests.empty?
            unfeasible_services.each{ |una_service|
              index = vrp.services.find_index{ |s| una_service[:original_service_id] == s.id }
              if index
                services_to_reinject << vrp.services.slice!(index)
              end

              next if una_service[:detail][:skills] && una_service[:detail][:skills].any?{ |skill| skill.include?('cluster') }
              una_service[:detail][:skills] = una_service[:detail][:skills].to_a + ["cluster #{cluster_reference}"]
            } if vrp.resolution_solver_parameter == -1 || !vrp.resolution_solver || vrp.scheduling?
            periodic = Interpreters::PeriodicVisits.new(vrp)
            vrp = periodic.expand(vrp, job) {
              block&.call(nil, nil, nil, 'solving scheduling heuristic', nil, nil, nil)
            }
            if vrp.preprocessing_partitions.any?{ |partition| partition[:entity] == 'work_day' }
              add_day_skill(vrp.vehicles.first, vrp.preprocessing_heuristic_result, unfeasible_services)
            end
            if vrp.resolution_solver_parameter != -1 && vrp.resolution_solver && !vrp.preprocessing_first_solution_strategy.to_a.include?('periodic')
              block.call(nil, nil, nil, 'process heuristic choice', nil, nil, nil) if block && vrp.preprocessing_first_solution_strategy
              # Select best heuristic
              Interpreters::SeveralSolutions.custom_heuristics(service, vrp, block)
              unfeasible_services.each{ |una_service|
                index = vrp.services.find_index{ |s| una_service[:original_service_id] == s.id }
                if index
                  services_to_reinject << vrp.services.slice!(index)
                end

                next if una_service[:detail][:skills] && una_service[:detail][:skills].any?{ |skill| skill.include?('cluster') }
                una_service[:detail][:skills] = una_service[:detail][:skills].to_a + ["cluster #{cluster_reference}"]
              }
              block.call(nil, nil, nil, 'process clustering', nil, nil, nil) if block && vrp.preprocessing_cluster_threshold
              cluster_result = cluster(vrp, vrp.preprocessing_cluster_threshold, vrp.preprocessing_force_cluster) do |cluster_vrp|
                block.call(nil, 0, nil, 'run optimization', nil, nil, nil) if block && !vrp.dichotomious_process?
                time_start = Time.now
                result = OptimizerWrapper.config[:services][service].solve(cluster_vrp, job, Proc.new{ |pids|
                    if job
                      actual_result = Result.get(job) || { 'pids' => nil }
                      if cluster_vrp[:restitution_csv]
                        actual_result[:csv] = true
                      end
                      actual_result['pids'] = pids
                      Result.set(job, actual_result)
                    end
                  }) { |wrapper, avancement, total, message, cost, time, solution|
                  block.call(wrapper, avancement, total, 'run optimization, iterations', cost, (Time.now - time_start) * 1000, solution.class.name == 'Hash' && solution) if block && !vrp.dichotomious_process?
                }
                if result.class.name == 'Hash' # result.is_a?(Hash) not working
                  result[:elapsed] = (Time.now - time_start) * 1000 # Can be overridden in wrappers
                  block.call(nil, nil, nil, "process #{vrp.resolution_split_number}/#{vrp.resolution_total_split_number} - " + 'run optimization' + " - elapsed time #{(Result.time_spent(result[:elapsed]) / 1000).to_i}/" + "#{vrp.resolution_total_duration / 1000} ", nil, nil, nil) if block && vrp.dichotomious_process?
                  parse_result(cluster_vrp, result)
                elsif result.class.name == 'String' # result.is_a?(String) not working
                  raise RuntimeError.new(result) unless result == "Job killed"
                elsif !vrp.preprocessing_heuristic_result || vrp.preprocessing_heuristic_result.empty?
                  raise RuntimeError.new('No solution provided') unless vrp.restitution_allow_empty_result
                end
              end
            end
          else # TODO remove ?
            cluster_result = {
              cost: nil,
              solvers: [service.to_s],
              iterations: nil,
              routes: [],
              unassigned: [],
              elapsed: nil,
              total_distance: nil
            }
          end

          # Reintegrate unfeasible services deleted from vrp.services to help ortools
          vrp.services += services_to_reinject
        end
      end

      if vrp.preprocessing_partition_method || !vrp.preprocessing_partitions.empty?
        # add associated cluster as skill
        [cluster_result, vrp.preprocessing_heuristic_result].each{ |solution|
          next if solution.nil? || solution.empty?

          solution[:routes].each{ |route|
            route[:activities].each do |stop|
              next if stop[:service_id].nil?

              stop[:detail][:skills] = stop[:detail][:skills].to_a + ["cluster #{cluster_reference}"]
            end
          }
          solution[:unassigned].each do |stop|
            next if stop[:service_id].nil?

            stop[:detail][:skills] = stop[:detail][:skills].to_a + ["cluster #{cluster_reference}"]
          end
        }
      end
      cluster_reference += 1
      if vrp.preprocessing_heuristic_result && !vrp.preprocessing_heuristic_result.empty?
        if [cluster_result, vrp.preprocessing_heuristic_result].all?{ |result| result.nil? || result[:routes].empty? }
          cluster_result || parse_result(vrp, vrp[:preprocessing_heuristic_result])
        else
          [cluster_result || parse_result(vrp, vrp[:preprocessing_heuristic_result]), parse_result(vrp, vrp[:preprocessing_heuristic_result])].select{ |result| !result[:routes].empty? }.sort_by{ |sol| sol[:cost] }.first
        end
      else
        Cleanse::cleanse(vrp, cluster_result)
        cluster_result
      end
    }

    real_result[:unassigned] = (real_result[:unassigned] || []) + unfeasible_services if real_result
    real_result[:name] = services_vrps[0][:vrp][:name] if real_result
    if real_result && services_vrps.any?{ |service| service[:vrp][:preprocessing_first_solution_strategy] }
      real_result[:heuristic_synthesis] = services_vrps.collect{ |service| service[:vrp][:preprocessing_heuristic_synthesis] }
      real_result[:heuristic_synthesis].flatten! if services_vrps.size == 1
    end

    if real_result && services_vrps.any?{ |service_vrp| service_vrp[:vrp][:restitution_csv] }
      real_result[:csv] = true
    end

    real_result
  rescue Resque::Plugins::Status::Killed
    puts 'Job Killed'
  rescue => e
    puts e
    puts e.backtrace
    raise
  end

  def self.split_independent_vrp_by_skills(vrp)
    # TODO : remove this flatten to take into account alternative skills on vehicle
    vehicle_ids_by_skills = vrp.vehicles.group_by{ |vehicle| vehicle.skills.flatten }.map{ |skills, vehicles| vehicles.map{ |v| v.id }.flatten }

    sub_vrps = vehicle_ids_by_skills.each_with_object([]) { |vehicle_ids, sub_vrps|
      service_ids = vrp.services.select{ |s| (s.skills & vrp.vehicles.find{ |v| vehicle_ids.include?(v.id) }.skills.flatten) == s.skills }.map(&:id)
      shipment_ids = vrp.shipments.select{ |s| (s.skills & vrp.vehicles.find{ |v| vehicle_ids.include?(v.id) }.skills.flatten) == s.skills }.map(&:id)

      next if service_ids.empty? && shipment_ids.empty? # No need to create this sub_problem if there is no shipment nor service in it

      service_vrp = {
        service: nil,
        vrp: vrp,
      }
      sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp(service_vrp, service_ids + shipment_ids, vehicle_ids)
      split_ratio = (sub_service_vrp[:vrp].services.size + sub_service_vrp[:vrp].shipments.size) / (vrp.services.size + vrp.shipments.size).to_f
      sub_service_vrp[:vrp].resolution_duration = (vrp.resolution_duration &.* split_ratio).to_i
      sub_service_vrp[:vrp].resolution_minimum_duration = (vrp.resolution_minimum_duration &.* split_ratio).to_i
      sub_service_vrp[:vrp].resolution_iterations_without_improvment = (vrp.resolution_iterations_without_improvment  &.* split_ratio).to_i
      sub_vrps.push(sub_service_vrp[:vrp])
    }
    sub_vrps
  end

  def self.split_independent_vrp_by_sticky_vehicle(vrp)
    # Intead of map{}.compact() or collect{}.compact() reduce([]){} or each_with_object([]){} is more efficient
    # when there are items to skip in the loop because it makes one pass of the array instead of two
    sub_vrps = vrp.vehicles.map(&:id).each_with_object([]) { |vehicle_id, sub_vrps|
      service_ids = vrp.services.select{ |s| s.sticky_vehicles.map(&:id) == [vehicle_id] }.map(&:id)
      shipment_ids = vrp.shipments.select{ |s| s.sticky_vehicles.map(&:id) == [vehicle_id] }.map(&:id)

      next if service_ids.empty? && shipment_ids.empty? # No need to create this sub_problem if there is no shipment nor service in it

      service_vrp = {
        service: nil,
        vrp: vrp,
      }
      sub_service_vrp = Interpreters::SplitClustering.build_partial_service_vrp(service_vrp, service_ids + shipment_ids, [vehicle_id])
      sub_service_vrp[:vrp].resolution_duration = vrp.resolution_duration && vrp.resolution_duration / vrp.vehicles.size
      sub_service_vrp[:vrp].resolution_minimum_duration = (vrp.resolution_minimum_duration && vrp.resolution_minimum_duration / vrp.vehicles.size) || (vrp.resolution_initial_time_out && vrp.resolution_initial_time_out / vrp.vehicles.size)
      sub_vrps.push(sub_service_vrp[:vrp])
    }
    sub_vrps
  end

  def self.split_independent_vrp(vrp)
    # Don't split vrp if
    return [vrp] if (vrp.vehicles.size <= 1) ||
                    (vrp.services.empty? && vrp.shipments.empty?) # there might be zero services or shipments (check together)

    if vrp.services.all?{ |s| s.sticky_vehicles.size == 1 } && vrp.shipments.all?{ |s| s.sticky_vehicles.size == 1 }
      return split_independent_vrp_by_sticky_vehicle(vrp)
    end

    all_skills = vrp.vehicles.map{ |v| v.skills.flatten }.uniq
    if !vrp.subtours&.any? && # Cannot split if there is multimodal subtours
       vrp.services.all?{ |s|
         !s.skills.empty? &&
         s.sticky_vehicles.empty? &&
         all_skills.one?{ |skills| (s.skills & skills).size == s.skills.size }
       }
      return split_independent_vrp_by_skills(vrp)
    end

    [vrp]
  end

  def self.join_independent_vrps(services_vrps, callback)
    results = services_vrps.each_with_index.map{ |sv, i|
      yield(sv[:service], sv[:vrp], services_vrps.size == 1 ? callback : callback ? lambda { |wrapper, avancement, total, message, cost = nil, time = nil, solution = nil|
        callback.call(wrapper, avancement, total, "process #{i+1}/#{services_vrps.size} - " + message, cost, time, solution)
      } : nil)
    }

    services_vrps.size == 1 ? results[0] : {
      solvers: results.flat_map{ |r| r && r[:solvers] }.compact,
      cost: results.map{ |r| r && r[:cost] }.compact.reduce(&:+),
      routes: results.flat_map{ |r| r && r[:routes] }.compact,
      unassigned: results.flat_map{ |r| r && r[:unassigned] }.compact,
      elapsed: results.map{ |r| r && r[:elapsed] || 0 }.reduce(&:+),
      total_time: results.map{ |r| r && r[:total_travel_time] }.compact.reduce(&:+),
      total_value: results.map{ |r| r && r[:total_travel_value] }.compact.reduce(&:+),
      total_distance: results.map{ |r| r && r[:total_distance] }.compact.reduce(&:+)
    }
  end

  def self.job_list(api_key)
    (JobList.get(api_key) || []).collect{ |e|
      if job = Resque::Plugins::Status::Hash.get(e)
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

  def self.job_kill(api_key, id)
    res = Result.get(id)
    Resque::Plugins::Status::Hash.kill(id) # Worker will be killed at the next call of at() method

    # Only kill the solver process if a pid has been set
    if res && res['pids'] && !res['pids'].empty?
      res['pids'].each{ |pid|
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
    if activity['service_id'] || activity['delivery_shipment_id'] || activity['delivery_shipment_id']
      'visit'
    elsif activity['rest_id']
      'rest'
    elsif activity['point_id']
      'store'
    else
      nil
    end
  end

  def self.build_csv(solutions)
    header = ['vehicle_id', 'id', 'point_id', 'lat', 'lon', 'type', 'setup_duration', 'duration', 'additional_value', 'skills', 'tags', 'total_travel_time', 'total_travel_distance']
    quantities_header = []
    unit_ids = []
    optim_planning_output = nil
    max_timewindows_size = 0
    reasons = nil
    if solutions
      (solutions.is_a?(Array) ? solutions : [solutions]).collect{ |solution|
        solution['routes'].each{ |route|
          route['activities'].each{ |activity|
            next if activity['detail'].nil? || !activity['detail']['quantities']

            activity['detail']['quantities'].each{ |quantity|
              unit_ids << quantity['unit']
              quantities_header << "quantity_#{quantity['label'] || quantity['unit']}"
            }
          }
        }
        quantities_header.uniq!
        unit_ids.uniq!

        max_timewindows_size = ([max_timewindows_size] + solution['routes'].collect{ |route|
          route['activities'].collect{ |activity|
            next if activity['detail'].nil? || !activity['detail']['timewindows']

            activity['detail']['timewindows'].collect{ |tw| [tw['start'], tw['end']] }.uniq.size
          }.compact
        }.flatten +
        solution['unassigned'].collect{ |activity|
          next if activity['detail'].nil? || !activity['detail']['timewindows']

          activity['detail']['timewindows'].collect{ |tw| [tw['start'], tw['end']] }.uniq.size
        }.compact).max
        timewindows_header = (0..max_timewindows_size.to_i - 1).collect{ |index|
          ["timewindow_start_#{index}", "timewindow_end_#{index}"]
        }.flatten
        header += quantities_header + timewindows_header
        reasons = true if solution['unassigned'].size.positive?

        optim_planning_output = solution['routes'].any?{ |route| route['activities'].any?{ |stop| stop['day_week'] } }
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
          solution['routes'].each{ |route|
            route['activities'].each{ |activity|
              days_info = optim_planning_output ? [activity['day_week_num'], activity['day_week']] : []
              common = build_csv_activity(solution['name'], route, activity)
              timewindows = build_csv_timewindows(activity, max_timewindows_size)
              quantities = unit_ids.collect{ |unit_id|
                activity['detail']['quantities'].find{ |quantity| quantity['unit'] == unit_id } && activity['detail']['quantities'].find{ |quantity| quantity['unit'] == unit_id }['value']
              }
              out_csv << (days_info + common + quantities + timewindows + [nil] )
            }
          }
          solution['unassigned'].each{ |activity|
            days_info = optim_planning_output ? [activity['day_week_num'], activity['day_week']] : []
            common = build_csv_activity(solution['name'], nil, activity)
            timewindows = build_csv_timewindows(activity, max_timewindows_size)
            quantities = unit_ids.collect{ |unit_id|
              activity['detail']['quantities'].find{ |quantity| quantity['unit'] == unit_id } && activity['detail']['quantities'].find{ |quantity| quantity['unit'] == unit_id }['value']
            }
            out_csv << (days_info + common + quantities + timewindows + [activity['reason']])
          }
        }
      }
    end
  end

  private

  def self.adjust_vehicles_duration(vrp)
      vrp.vehicles.select{ |v| v.duration? && v.rests.size > 0 }.each{ |v|
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

  def self.route_total_dimension(vrp, route, vehicle, dimension)
    previous = nil
    route[:activities].sum{ |a|
      #TODO: This next operation is expensive for big instances. Is there a better way?
      point_id = a[:point_id] ? a[:point_id] : a[:service_id] ? vrp.services.find{ |s|
        s.id == a[:service_id]
      }.activity.point_id : a[:pickup_shipment_id] ? vrp.shipments.find{ |s|
        s.id == a[:pickup_shipment_id]
      }.pickup.point_id : a[:delivery_shipment_id] ? vrp.shipments.find{ |s|
        s.id == a[:delivery_shipment_id]
      }.delivery.point_id : nil
      if point_id
        point = vrp.points.find{ |p| p.id == point_id }.matrix_index
        if previous && point
          a[('travel_' + dimension.to_s).to_sym] = vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.send(dimension)[previous][point]
        end
      end
      previous = point
      a[('travel_' + dimension.to_s).to_sym] || 0
    }
  end

  def self.build_csv_activity(name, route, activity)
    type = find_type(activity)
    [
      route && route['vehicle_id'],
      activity['service_id'] || activity['pickup_shipment_id'] || activity['delivery_shipment_id'] || activity['rest_id'] || activity['point_id'],
      activity['point_id'],
      activity['detail']['lat'],
      activity['detail']['lon'],
      type,
      formatted_duration(activity['detail']['setup_duration'] || 0),
      formatted_duration(activity['detail']['duration'] || 0),
      activity['detail']['additional_value'] || 0,
      activity['detail']['skills'].to_a.empty? ? nil : activity['detail']['skills'].to_a.flatten.join(','),
      name,
      route && formatted_duration(route['total_travel_time']),
      route && route['total_distance']
    ]
  end

  def self.build_csv_timewindows(activity, max_timewindows_size)
    (0..max_timewindows_size - 1).collect{ |index|
      if activity['detail']['timewindows'] && index < activity['detail']['timewindows'].collect{ |tw| [tw['start'], tw['end']] }.uniq.size
        timewindow = activity['detail']['timewindows'].select{ |tw| [tw['start'], tw['end']] }.uniq.sort_by{ |t| t['start'] }[index]
        [timewindow['start'] && formatted_duration(timewindow['start']), timewindow['end'] && formatted_duration(timewindow['end'])]
      else
        [nil, nil]
      end
    }.flatten
  end

  def self.route_details(vrp, route, vehicle)
    previous = nil
    details = nil
    segments = route[:activities].reverse.collect{ |activity|
      current = nil
      if activity[:point_id]
        current = vrp.points.find{ |point| point[:id] == activity[:point_id] }
      elsif activity[:service_id]
        current = vrp.points.find{ |point| point[:id] ==  vrp.services.find{ |service| service[:id] == activity[:service_id] }[:activity][:point_id] }
      elsif activity[:pickup_shipment_id]
        current = vrp.points.find{ |point| point[:id] ==  vrp.shipments.find{ |shipment| shipment[:id] == activity[:pickup_shipment_id] }[:pickup][:point_id] }
      elsif activity[:delivery_shipment_id]
        current = vrp.points.find{ |point| point[:id] ==  vrp.shipments.find{ |shipment| shipment[:id] == activity[:delivery_shipment_id] }[:delivery][:point_id] }
      elsif activity[:rest_id]
        current = previous
      end
      segment = if previous && current
        [current[:location][:lat], current[:location][:lon], previous[:location][:lat], previous[:location][:lon]]
      end
      previous = current
      segment
    }.reverse.compact
    unless segments.empty?
      details = OptimizerWrapper.router.compute_batch(OptimizerWrapper.config[:router][:url],
        vehicle[:router_mode].to_sym, vehicle[:router_dimension], segments, vrp.restitution_geometry_polyline, vehicle.router_options)
      raise RouterError.new('Route details cannot be received') unless details
    end
    details.each{ |d| d[0] = (d[0] / 1000.0).round(4) if d[0] } if details
    details
  end

  def self.parse_result(vrp, result)
    result[:routes].each{ |r|
      details = nil
      v = vrp.vehicles.find{ |v| v.id == r[:vehicle_id] }
      if r[:end_time] && r[:start_time]
        r[:total_time] = r[:end_time] - r[:start_time]
      end

      matrix = vrp.matrices.find{ |mat| mat.id == v.matrix_id }
      if matrix.time
        r[:total_travel_time] = route_total_dimension(vrp, r, v, :time)
      end
      if matrix.value
        r[:total_travel_value] = route_total_dimension(vrp, r, v, :value)
      end
      if matrix.distance
        r[:total_distance] = route_total_dimension(vrp, r, v, :distance)
      elsif matrix[:distance].nil? && r[:activities].size > 1 && vrp.points.all?(&:location)
        details = route_details(vrp, r, v)
        if details && !details.empty?
          r[:total_distance] = details.map(&:first).compact.reduce(:+)
          index = 0
          r[:activities][1..-1].each{ |activity|
            activity[:travel_distance] = details[index].first if details[index]
            index += 1
          }
        end
      end
      if vrp.restitution_geometry && r[:activities].size > 1
        details = route_details(vrp, r, v) if details.nil?
        r[:geometry] = details.map(&:last) if details
      end
    }
    if result[:routes].all?{ |r| r[:total_time] }
      result[:total_time] = result[:routes].collect{ |r|
        r[:total_time]
      }.reduce(:+)
    end

    if result[:routes].all?{ |r| r[:total_distance] }
      result[:total_distance] = result[:routes].collect{ |r|
        r[:total_distance]
      }.reduce(:+)
    end

    result
  end

  def self.apply_zones(vrp)
    vrp.zones.each{ |zone|
      if !zone.allocations.empty?
        zone.vehicles = if zone.allocations.size == 1
          zone.allocations[0].collect{ |vehicle_id| vrp.vehicles.find{ |vehicle| vehicle.id == vehicle_id } }.compact
        else
          zone.allocations.collect{ |allocation| vrp.vehicles.find{ |vehicle| vehicle.id == allocation.first } }.compact
        end
        if !zone.vehicles.compact.empty?
          zone.vehicles.each{ |vehicle|
            if vehicle.skills.empty?
              vehicle.skills = [[zone[:id]]]
            else
              vehicle.skills.each{ |alternative| alternative << zone[:id] }
            end
          }
        end
      end
    }
    if vrp.points.all?{ |point| point.location }
      vrp.zones.each{ |zone|
        related_ids = vrp.services.collect{ |service|
          activity_point = vrp.points.find{ |point| point.id == service.activity.point_id }
          if zone.inside(activity_point.location.lat, activity_point.location.lon)
            service.sticky_vehicles += zone.vehicles
            service.sticky_vehicles.uniq!
            service.skills += [zone[:id]]
            service.id
          end
        }.compact + vrp.shipments.collect{ |shipment|
          shipments_ids = []
          pickup_point = vrp.points.find{ |point| point[:id] == shipment[:pickup][:point_id] }
          delivery_point = vrp.points.find{ |point| point[:id] == shipment[:delivery][:point_id] }
          if zone.inside(pickup_point[:location][:lat], pickup_point[:location][:lon]) && zone.inside(delivery_point[:location][:lat], delivery_point[:location][:lon])
            shipment.sticky_vehicles += zone.vehicles
            shipment.sticky_vehicles.uniq!
          end
          if zone.inside(pickup_point[:location][:lat], pickup_point[:location][:lon])
            shipment.skills += [zone[:id]]
            shipments_ids << shipment.id + 'pickup'
          end
          if zone.inside(delivery_point[:location][:lat], delivery_point[:location][:lon])
            shipment.skills += [zone[:id]]
            shipments_ids << shipment.id + 'delivery'
          end
          shipments_ids.uniq
        }.compact
        # Remove zone allocation verification if we need to assign zone without vehicle affectation together
        if !zone.allocations.empty? && zone.allocations.size > 1 && !related_ids.empty? && related_ids.size > 1
          vrp.relations += [{
            type: :same_route,
            linked_ids: related_ids.flatten,
          }]
        end
      }
    end
  end

  def self.cluster(vrp, cluster_threshold, force_cluster)
    if vrp.matrices.size > 0 && vrp.shipments.size == 0 && (cluster_threshold.to_f > 0 || force_cluster) && !vrp.scheduling?
      original_services = Array.new(vrp.services.size){ |i| vrp.services[i].clone }
      zip_key = zip_cluster(vrp, cluster_threshold, force_cluster)
    end
    result = yield(vrp)
    if vrp.matrices.size > 0 && vrp.shipments.size == 0 && (cluster_threshold.to_f > 0 || force_cluster) && !vrp.scheduling?
      vrp.services = original_services
      unzip_cluster(result, zip_key, vrp)
    else
      result
    end
  end

  def self.zip_cluster(vrp, cluster_threshold, force_cluster)
    return nil unless vrp.services.length > 0

    data_set = DataSet.new(data_items: (0..(vrp.services.length - 1)).collect{ |i| [i] })
    c = CompleteLinkageMaxDistance.new
    matrix = vrp.matrices[0][vrp.vehicles[0].router_dimension.to_sym]
    cost_late_multiplier = vrp.vehicles.all?{ |v| v.cost_late_multiplier && v.cost_late_multiplier != 0 }
    no_capacities = vrp.vehicles.all?{ |v| v.capacities.size == 0 }
    if force_cluster
      c.distance_function = lambda do |a, b|
        aa = vrp.services[a[0]]
        bb = vrp.services[b[0]]
        aa.activity.timewindows.empty? && bb.activity.timewindows.empty? || aa.activity.timewindows.any?{ |twa| bb.activity.timewindows.any?{ |twb| twa[:start] <= twb[:end] && twb[:start] <= twa[:end] }} ?
          matrix[aa.activity.point.matrix_index][bb.activity.point.matrix_index] :
          Float::INFINITY
      end
    else
      c.distance_function = lambda do |a, b|
        aa = vrp.services[a[0]]
        bb = vrp.services[b[0]]
        (aa.activity.timewindows.collect{ |t| [t[:start], t[:end]]} == bb.activity.timewindows.collect{ |t| [t[:start], t[:end]]} &&
          ((cost_late_multiplier && aa.activity.late_multiplier.to_f > 0 && bb.activity.late_multiplier.to_f > 0) || (aa.activity.duration == 0 && bb.activity.duration == 0)) &&
          (no_capacities || (aa.quantities.size == 0 && bb.quantities.size == 0)) &&
          aa.skills == bb.skills) ?
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
      if force_cluster
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
              new_quantities.one?{ |new_quantity| new_quantity[:unit_id] == sub_quantity[:unit_id] } ? new_quantities.find{ |new_quantity| new_quantity[:unit_id] == sub_quantity[:unit_id] }[:value] += type[index] == "delivery" ? -sub_quantity[:value] : sub_quantity[:value] : new_quantities << sub_quantity
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
                tw[:day_index].nil? || new_tw[:day_index].nil? || tw[:day_index] == new_tw[:day_index] &&
                  (tw[:start].nil? || new_tw[:end].nil? || tw[:start] <= new_tw[:end]) &&
                  (tw[:end].nil? || new_tw[:start].nil? || tw[:end] >= new_tw[:start])
              }
              if compatible_tws.empty?
                to_remove_tws << new_tws
              else
                compatible_start = compatible_tws.collect{ |tw| tw[:start] }.compact.max
                compatible_end = compatible_tws.collect{ |tw| tw[:end] }.compact.min
                new_tw[:start] = [new_tw[:start], compatible_start].max if compatible_start
                new_tw[:end] = [new_tw[:end], compatible_end].min if compatible_end
              end
            }
          end
        }
        raise OptimizerWrapper::DiscordantProblemError, 'Zip cluster : no intersecting tw could be found' if !new_tws.empty? && (new_tws - to_remove_tws).empty?
        new_services[i].activity.timewindows = (new_tws - to_remove_tws).compact
      end
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
      vehicle = original_vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] } ? original_vrp.vehicles.find{ |vehicle| vehicle[:id] == route[:vehicle_id] } : original_vrp.vehicles[0]
      new_activities = []
      activities = route[:activities].collect.with_index{ |activity, idx_a|
        idx_s = original_vrp.services.index{ |s| s.id == activity[:service_id] }
        idx_z = zip_key.index{ |z| z.data_items.flatten.include? idx_s }
        if idx_z && idx_z < zip_key.length && zip_key[idx_z].data_items.length > 1
          sub = zip_key[idx_z].data_items.collect{ |i| i[0] }
          matrix = original_vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }[original_vrp.vehicles[0].router_dimension.to_sym]

          # Cluster start: Last non rest-without-location stop before current cluster
          start = new_activities.reverse.find{ |r| r[:service_id] }
          start_index = start ? original_vrp.services.index{ |s| s.id == start[:service_id] } : 0

          j = 0
          while route[:activities][idx_a + j] && !route[:activities][idx_a + j][:service_id] do # Next non rest-without-location stop after current cluster
            j += 1
          end

          if route[:activities][idx_a + j] && route[:activities][idx_a + j][:service_id]
            stop_index = original_vrp.services.index{ |s| s.id == route[:activities][idx_a + j][:service_id] }
          else
            stop_index = original_vrp.services.length - 1
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
              r = index == 0 ? r : r[index..-1] + r[0..index - 1] # shift to replace start at beginning
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
            }.delete_if { |k, v| !v }
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
        total_distance: route[:total_distance] ? route[:total_distance] : 0,
        total_time: route[:total_time] ? route[:total_time] : 0,
        total_travel_time: route[:total_travel_time] ? route[:total_travel_time] : 0,
        total_travel_value: route[:total_travel_value] ? route[:total_travel_value] : 0,
        geometry: route[:geometry]
      }.delete_if{ |_k, v| v.nil? }
    }
    result[:unassigned] = routes.find{ |route| route[:vehicle_id] == 'unassigned' } ? routes.find{ |route| route[:vehicle_id] == 'unassigned' }[:activities] : []
    result[:routes] = routes.reject{ |route| route[:vehicle_id] == 'unassigned' }
    result
  end

  def self.add_day_skill(vehicle, result, unfeasible_services)
    day_names = { 0 => 'mon', 1 => 'tue', 2 => 'wed', 3 => 'thu', 4 => 'fri', 5 => 'sat', 6 => 'sun' }
    day = day_names[result[:routes].collect{ |route| route[:vehicle_id].split('_').last.to_i }.min]

    result[:routes].each{ |route| route[:activities].each{ |activity|
      next if !activity[:service_id]

      activity[:detail][:skills] << day
    }}

    (result[:unassigned] + unfeasible_services).each{ |unassigned|
      unassigned[:detail][:skills] = unassigned[:detail][:skills].to_a + [day]
    }
  end
end

module SimAnnealing
  class SimAnnealingVrp < SimAnnealing
    attr_accessor :start, :stop, :matrix, :vrp

    def euc_2d(c1, c2)
      if (c1 == start || c1 == stop) && (c2 == start || c2 == stop)
        0
      else
        matrix[vrp.services[c1].activity.point.matrix_index][vrp.services[c2].activity.point.matrix_index]
      end
    end
  end
end
