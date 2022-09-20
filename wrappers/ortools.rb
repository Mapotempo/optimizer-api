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
require './wrappers/wrapper'
require './wrappers/ortools_vrp_pb'
require './wrappers/ortools_result_pb'

module Wrappers
  class Ortools < Wrapper
    def initialize(hash = {})
      super(hash)
      @exec_ortools =
        hash[:exec_ortools] ||
        'LD_LIBRARY_PATH=../or-tools/dependencies/install/lib/:../or-tools/lib/ ../optimizer-ortools/tsp_simple'
      @optimize_time = hash[:optimize_time]
      @previous_result = nil
      @iterations_without_improvment ||= nil
      @time_out_multiplier ||= nil
    end

    def solver_constraints
      super + [
        :assert_end_optimization,
        :assert_vehicles_objective,
        :assert_vehicles_no_alternative_skills,
        :assert_zones_only_size_one_alternative,
        :assert_only_empty_or_fill_quantities,
        :assert_points_same_definition,
        :assert_correctness_matrices_vehicles_and_points_definition,
        :assert_square_matrix,
        :assert_vehicle_tw_if_periodic,
        :assert_if_periodic_heuristic_then_schedule,
        :assert_only_force_centroids_if_kmeans_method,
        :assert_no_periodic_if_evaluation,
        :assert_route_if_evaluation,
        :assert_wrong_vehicle_shift_preference_with_heuristic,
        :assert_no_vehicle_overall_duration_if_heuristic,
        :assert_no_vehicle_distance_if_heuristic,
        :assert_possible_to_get_distances_if_maximum_ride_distance,
        :assert_no_vehicle_free_approach_or_return_if_heuristic,
        :assert_no_vehicle_limit_if_heuristic,
        :assert_no_same_point_day_if_no_heuristic,
        :assert_no_allow_partial_if_no_heuristic,
        :assert_solver_if_not_periodic,
        :assert_first_solution_strategy_is_possible,
        :assert_first_solution_strategy_is_valid,
        :assert_clustering_compatible_with_periodic_heuristic,
        :assert_lat_lon_for_partition,
        :assert_vehicle_entity_only_before_work_day,
        :assert_partitions_entity,
        :assert_valid_partitions,
        :assert_route_date_or_indice_if_periodic,
        :assert_not_too_many_visits_in_route,
        # :assert_no_overall_duration, # TODO: Requires a complete rework
      ]
    end

    def solve(vrp, job, thread_proc = nil, &block)
      tic = Time.now
      order_relations = vrp.relations.select{ |relation| relation.type == :order }
      already_begin = order_relations.collect{ |relation| relation.linked_service_ids[0..-2] }.flatten
      duplicated_begins = already_begin.uniq.select{ |linked_id| already_begin.count{ |link| link == linked_id } > 1 }
      already_end = order_relations.collect{ |relation| relation.linked_service_ids[1..-1] }.flatten
      duplicated_ends = already_end.uniq.select{ |linked_id| already_end.count{ |link| link == linked_id } > 1 }
      if vrp.routes.empty? && order_relations.size == 1 && vrp.services.none?{ |service| service.activities.any? }
        order_relations.select{ |relation|
          (relation.linked_service_ids[0..-2] & duplicated_begins).empty? &&
            (relation.linked_service_ids[1..-1] & duplicated_ends).empty?
        }.each{ |relation|
          order_route = {
            vehicle: vrp.vehicles.size == 1 ? vrp.vehicles.first : nil,
            mission_ids: relation.linked_service_ids
          }
          vrp.routes += [order_route]
        }
      end

      problem_units =
        vrp.units.collect{ |unit|
          {
            unit_id: unit.id,
            fill: false,
            empty: false
          }
        }
      total_quantities = vrp.units.map{ |unit| [unit.id, 0] }.to_h

      vrp.relations.select{ |r| r.type == :shipment }.each{ |r|
        vrp.units.each{ |unit|
          total_negative = 0
          total_positive = 0
          r.linked_services.each{ |s|
            quantity = s.quantities.find{ |q| q.unit_id == unit.id }&.value || 0
            if quantity > 0
              total_positive += quantity
            else
              total_negative -= quantity
            end
          }
          total_quantities[unit.id] += [total_positive, total_negative].max
        }
      }

      vrp.services.each{ |service|
        next if service.relations.any?{ |r| r.type == :shipment }

        service.quantities.each{ |q|
          total_quantities[q.unit.id] += (q.value || 0).abs
        }
      }

      vrp.services.each{ |service|
        service.quantities.each{ |quantity|
          unit_status = problem_units.find{ |unit| unit[:unit_id] == quantity.unit_id }
          unit_status[:fill] ||= quantity.fill
          unit_status[:empty] ||= quantity.empty
        }
      }
      # FIXME: or-tools can handle no end-point itself
      @job = job
      @previous_result = nil
      relations = []
      services = []
      routes = []
      services_activity_positions = { always_first: [], always_last: [], never_first: [], never_last: [] }
      vrp.services.each_with_index{ |service, service_index|
        vehicles_indices = []
        detect_unfeasible_services(vrp) if service.vehicle_compatibility.nil?
        vrp.vehicles.each_with_index{ |vehicle, index|
          next if service.vehicle_compatibility[vehicle.id] == false || # let nil through
                  !service.vehicle_compatibility[vehicle.original_id] || # can't be nil
                  !check_services_compatible_days(vrp, vehicle, service)

          vehicles_indices << index
        }

        if service.activity
          services << OrtoolsVrp::Service.new(
            time_windows: service.activity.timewindows.collect{ |tw|
              OrtoolsVrp::TimeWindow.new(start: tw.start, end: tw.end || 2147483647,
                                         maximum_lateness: tw.maximum_lateness)
            },
            quantities: vrp.units.collect{ |unit|
              is_fill_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:fill]
              is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              # make sure that if it is
              #   - an empty unit then the amount is negative for the empty service and positive for the proper services
              #   - a fill unit then the amount is positive for the fill service and negative for the proper services
              if is_empty_unit || is_fill_unit
                empty_fill_value = q&.value.to_f.abs
                if q&.empty && empty_fill_value == 0
                  # The empty operation itself having nil/0 value means complete empty operation
                  empty_fill_value = total_quantities[unit.id].abs
                end
                empty_fill_value * ((is_empty_unit && q&.empty) || (is_fill_unit && !q&.fill) ? -1 : 1)
              else
                q&.value.to_f
              end
            },
            duration: service.activity.duration,
            additional_value: service.activity.additional_value,
            priority: service.priority,
            matrix_index: service.activity.point.matrix_index,
            vehicle_indices: vehicles_indices,
            setup_duration: service.activity.setup_duration,
            id: service.id.to_s,
            late_multiplier: service.activity.late_multiplier || 0,
            setup_quantities: vrp.units.collect{ |unit|
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              q && q.setup_value && unit.counting ? q.setup_value.to_i : 0
            },
            exclusion_cost: service.exclusion_cost && service.exclusion_cost.to_i || -1,
            refill_quantities: vrp.units.collect{ |unit|
              q = service.quantities.find{ |quantity| quantity.unit == unit }
              !q.nil? && (q.fill || q.empty)
            },
            problem_index: service_index,
            point_id: service.activity.point_id,
            alternative_index: 0
          )

          services = update_services_activity_positions(services, services_activity_positions, service.id,
                                                        service.activity.position, service_index, 0)
        elsif service.activities
          service.activities.each_with_index{ |possible_activity, activity_index|
            services << OrtoolsVrp::Service.new(
              time_windows: possible_activity.timewindows.collect{ |tw|
                OrtoolsVrp::TimeWindow.new(start: tw.start, end: tw.end || 2147483647,
                                           maximum_lateness: tw.maximum_lateness)
              },
              quantities: vrp.units.collect{ |unit|
                is_fill_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:fill]
                is_empty_unit = problem_units.find{ |unit_status| unit_status[:unit_id] == unit.id }[:empty]
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                # make sure that if it is
                # - an empty unit then the amount is negative for the empty service and positive for the proper services
                # - a fill unit then the amount is positive for the fill service and negative for the proper services
                if is_empty_unit || is_fill_unit
                  empty_fill_value = q&.value.to_f.abs
                  if q&.empty && empty_fill_value == 0
                    # The empty operation itself having nil/0 value means complete empty operation
                    empty_fill_value = total_quantities[unit.id].abs
                  end
                  empty_fill_value * ((is_empty_unit && q&.empty) || (is_fill_unit && !q&.fill) ? -1 : 1)
                else
                  q&.value.to_f
                end
              },
              duration: possible_activity.duration,
              additional_value: possible_activity.additional_value,
              priority: service.priority,
              matrix_index: possible_activity.point.matrix_index,
              vehicle_indices: vehicles_indices,
              setup_duration: possible_activity.setup_duration,
              id: service.id.to_s,
              late_multiplier: possible_activity.late_multiplier || 0,
              setup_quantities: vrp.units.collect{ |unit|
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                q&.setup_value && unit.counting ? q.setup_value.to_i : 0
              },
              exclusion_cost: service.exclusion_cost || -1,
              refill_quantities: vrp.units.collect{ |unit|
                q = service.quantities.find{ |quantity| quantity.unit == unit }
                !q.nil? && (q.fill || q.empty)
              },
              problem_index: service_index,
              point_id: possible_activity.point_id,
              alternative_index: activity_index
            )

            services = update_services_activity_positions(services, services_activity_positions, service.id,
                                                          possible_activity.position, service_index, activity_index)
          }
        end
      }

      matrices =
        vrp.matrices.collect{ |matrix|
          matrix_size = (matrix[:time] || matrix[:distance]).size
          OrtoolsVrp::Matrix.new(
            size: matrix_size,
            time: matrix[:time] ? matrix[:time].flatten : Array.new(matrix_size**2, 0),
            distance: matrix[:distance] ? matrix[:distance].flatten : Array.new(matrix_size**2, 0),
            value: matrix[:value] ? matrix[:value].flatten : []
          )
        }

      vehicles =
        vrp.vehicles.collect{ |vehicle|
          OrtoolsVrp::Vehicle.new(
            id: vehicle.id.to_s,
            cost_fixed: vehicle.cost_fixed,
            cost_distance_multiplier: vehicle.cost_distance_multiplier,
            cost_time_multiplier: vehicle.cost_time_multiplier,
            cost_waiting_time_multiplier: vehicle.cost_waiting_time_multiplier || vehicle.cost_time_multiplier,
            cost_value_multiplier: vehicle.cost_value_multiplier || 0,
            cost_late_multiplier: vehicle.cost_late_multiplier || 0,
            coef_service: vehicle.coef_service || 1,
            coef_setup: vehicle.coef_setup || 1,
            additional_service: vehicle.additional_service || 0,
            additional_setup: vehicle.additional_setup || 0,
            capacities: vrp.units.collect{ |unit|
              q = vehicle.capacities.find{ |capacity| capacity.unit == unit }
              OrtoolsVrp::Capacity.new(
                limit: q&.limit && q.limit < 1e+22 ? q.limit : -1,
                overload_multiplier: q&.overload_multiplier || 0,
                counting: unit&.counting || false,
                initial_limit: q&.initial || [total_quantities[unit.id], q&.limit].compact.max
              )
            },
            time_window: OrtoolsVrp::TimeWindow.new(
              start: vehicle.timewindow&.start || 0,
              end: vehicle.timewindow&.end || 2147483647,
              maximum_lateness: vehicle.timewindow&.maximum_lateness || 0,
            ),
            rests: vehicle.rests.collect{ |rest|
              OrtoolsVrp::Rest.new(
                time_window:
                  if rest.timewindows.any?
                    log 'optimiser-ortools supports one timewindow per rest', level: :warn if rest.timewindows.size > 1

                    OrtoolsVrp::TimeWindow.new(start: rest.timewindows[0].start,
                                               end: rest.timewindows[0].end || 2147483647)
                  else
                    OrtoolsVrp::TimeWindow.new(start: 0, end: 2147483647) # Rests should always have a timewindow
                  end,
                duration: rest.duration,
                id: rest.id.to_s,
                late_multiplier: rest.late_multiplier,
                exclusion_cost: rest.exclusion_cost || -1
              )
            },
            matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.matrix_id },
            value_matrix_index: vrp.matrices.index{ |matrix| matrix.id == vehicle.value_matrix_id } || 0,
            start_index: vehicle.start_point ? vehicle.start_point.matrix_index : -1,
            end_index: vehicle.end_point ? vehicle.end_point.matrix_index : -1,
            duration: vehicle.duration || 0,
            distance: vehicle.distance || 0,
            shift_preference: (vehicle.force_start ? 'force_start' : vehicle.shift_preference.to_s),
            day_index: vehicle.global_day_index || -1,
            max_ride_time: vehicle.maximum_ride_time || 0,
            max_ride_distance: vehicle.maximum_ride_distance || 0,
            free_approach: vehicle.free_approach || false,
            free_return: vehicle.free_return || false,
            start_point_id: vehicle.start_point_id.to_s
          )
        }

      vrp.relations.each{ |relation|
        relation.split_regarding_lapses.each{ |portion_linked_ids, portion_vehicle_ids, portion_lapse|
          current_linked_ids = (portion_linked_ids.map!(&:to_s) & services.map(&:id)).uniq if portion_linked_ids
          if portion_vehicle_ids
            current_linked_vehicles = vrp.vehicles.select{ |v| portion_vehicle_ids.include?(v.id) }.map(&:id)
          end
          next if current_linked_ids.to_a.empty? && current_linked_vehicles.to_a.empty?

          # NOTE: we collect lapse because optimizer-ortools expects one lapse per relation for now
          relations << OrtoolsVrp::Relation.new(
            type: relation.type,
            linked_ids: current_linked_ids,
            linked_vehicle_ids: current_linked_vehicles&.map!(&:to_s),
            lapse: portion_lapse
          )
        }
      }

      vrp.routes.collect{ |route|
        next if route.vehicle.nil? || route.mission_ids.empty?

        service_ids = corresponding_mission_ids(services.collect(&:id), route.mission_ids)
        next if service_ids.empty?

        routes << OrtoolsVrp::Route.new(
          vehicle_id: route.vehicle.id.to_s,
          service_ids: service_ids.map(&:to_s)
        )
      }

      unless services_activity_positions[:always_first].empty?
        relations << OrtoolsVrp::Relation.new(type: :force_first,
                                              linked_ids: services_activity_positions[:always_first])
      end
      unless services_activity_positions[:never_first].empty?
        relations << OrtoolsVrp::Relation.new(type: :never_first,
                                              linked_ids: services_activity_positions[:never_first])
      end
      unless services_activity_positions[:never_last].empty?
        relations << OrtoolsVrp::Relation.new(type: :never_last,
                                              linked_ids: services_activity_positions[:never_last])
      end
      unless services_activity_positions[:always_last].empty?
        relations << OrtoolsVrp::Relation.new(type: :force_end,
                                              linked_ids: services_activity_positions[:always_last])
      end

      problem = OrtoolsVrp::Problem.new(
        vehicles: vehicles,
        services: services,
        matrices: matrices,
        relations: relations,
        routes: routes
      )

      log "ortools solve problem creation elapsed: #{Time.now - tic}sec", level: :debug
      run_ortools(problem, vrp, thread_proc, &block)
    end

    private

    def build_cost_details(cost_details)
      Models::Solution::CostInfo.create(
        fixed: cost_details&.fixed || 0,
        time: cost_details && (cost_details.time + cost_details.time_fake + cost_details.time_without_wait) || 0,
        distance: cost_details && (cost_details.distance + cost_details.distance_fake) || 0,
        value: cost_details&.value || 0,
        lateness: cost_details&.lateness || 0,
        overload: cost_details&.overload || 0
      )
    end

    def build_route_stop(vrp, vehicle, problem_services, problem_rests, activity)
      times = { begin_time: activity.start_time, current_distance: activity.current_distance }
      loads =
        activity.quantities.map.with_index{ |quantity, index|
          Models::Solution::Load.new(quantity: Models::Quantity.new(unit: vrp.units[index]), current: quantity)
        }
      case activity.type
      when 'start'
        Models::Solution::StopDepot.new(vehicle.start_point, info: times, loads: loads) if vehicle.start_point
      when 'end'
        Models::Solution::StopDepot.new(vehicle.end_point, info: times, loads: loads) if vehicle.end_point
      when 'service'
        service = vrp.services[activity.index]
        problem_services.delete(service.id)
        Models::Solution::Stop.new(service, info: times, loads: loads, index: activity.alternative)
      when 'break'
        vehicle_rest = problem_rests[vehicle.id][activity.id]
        problem_rests[vehicle.id].delete(activity.id)
        Models::Solution::Stop.new(vehicle_rest, info: times, loads: loads)
      end
    end

    def build_routes(vrp, problem_services, problem_rests, routes)
      routes.map.with_index{ |route, index|
        previous_matrix_index = nil
        vehicle = vrp.vehicles[index]
        route_costs = build_cost_details(route.cost_details)
        stops = route.activities.map{ |activity|
          current_matrix_index =
            case activity.type
            when 'service'
              service = vrp.services[activity.index]
              service.activity&.point&.matrix_index ||
              !service.activities.empty? && service.activities[activity.alternative].point.matrix_index
            when 'start'
              vrp.vehicles[index].start_point&.matrix_index
            when 'end'
              vrp.vehicles[index].end_point&.matrix_index
            end
          stop = build_route_stop(vrp, vehicle, problem_services, problem_rests, activity)
          next stop if activity.type == 'rest'

          matrix = vrp.matrices.find{ |m| m.id == vehicle.matrix_id }
          build_route_data(stop, matrix, previous_matrix_index, current_matrix_index)
          previous_matrix_index = current_matrix_index
          stop
        }.compact
        route_detail = Models::Solution::Route::Info.new({})
        initial_loads =
          route.activities.first.quantities.map.with_index{ |quantity, q_index|
            Models::Solution::Load.new(quantity: Models::Quantity.new(unit: vrp.units[q_index]), current: quantity)
          }
        Models::Solution::Route.new(
          stops: stops,
          initial_loads: initial_loads,
          cost_info: route_costs,
          info: route_detail,
          vehicle: vehicle
        )
      }
    end

    def build_unassigned(problem_services, problem_rests)
      problem_services.values.map{ |service| Models::Solution::Stop.new(service) } +
        problem_rests.flat_map{ |_v_id, v_rests| v_rests.values.map{ |v_rest| Models::Solution::Stop.new(v_rest) } }
    end

    def build_solution(vrp, content)
      problem_services = vrp.services.map{ |service| [service.id, service] }.to_h
      problem_rests = vrp.vehicles.map{ |vehicle|
        [vehicle.id, vehicle.rests.map{ |rest| [rest.id, rest] }.to_h]
      }.to_h
      routes = build_routes(vrp, problem_services, problem_rests, content.routes)
      Models::Solution.new(
        solvers: [:ortools],
        iterations: content.iterations,
        elapsed: content.duration * 1000,
        routes: routes,
        unassigned_stops: build_unassigned(problem_services, problem_rests)
      )
    end

    def check_services_compatible_days(vrp, vehicle, service)
      !vrp.schedule? || (
        service.unavailable_days.exclude?(vehicle.global_day_index) &&
        (
          (!service.minimum_lapse && !service.maximum_lapse) ||
          vehicle.global_day_index.between?(service.first_possible_days.first, service.last_possible_days.first)
        )
      )
    end

    def build_route_data(stop, vehicle_matrix, previous_matrix_index, current_matrix_index)
      if previous_matrix_index && current_matrix_index
        travel_distance =
          vehicle_matrix[:distance] ? vehicle_matrix[:distance][previous_matrix_index][current_matrix_index] : 0
        travel_time = vehicle_matrix[:time] ? vehicle_matrix[:time][previous_matrix_index][current_matrix_index] : 0
        travel_value = vehicle_matrix[:value] ? vehicle_matrix[:value][previous_matrix_index][current_matrix_index] : 0
        {
          travel_distance: travel_distance,
          travel_time: travel_time,
          travel_value: travel_value
        }.each{ |key, value| stop.info.send("#{key}=", value) }
      end
      {}
    end

    def parse_output(vrp, output)
      if vrp.vehicles.empty? || vrp.services.empty?
        return vrp.empty_solution(:ortools)
      end

      output.rewind
      content = OrtoolsResult::Result.decode(output.read)
      output.rewind

      return @previous_result if content.routes.empty? && @previous_result

      solution = build_solution(vrp, content)

      solution.parse(vrp)
    end

    def run_ortools(problem, vrp, thread_proc = nil, &block)
      log "----> run_ortools services(#{vrp.services.size}) " \
          "preassigned(#{vrp.routes.flat_map{ |r| r[:mission_ids].size }.sum}) vehicles(#{vrp.vehicles.size})"
      tic = Time.now
      if vrp.vehicles.empty? || vrp.services.empty?
        return vrp.empty_solution(:ortools)
      end

      input = Tempfile.new('optimize-or-tools-input', @tmp_dir, binmode: true)
      input.write(OrtoolsVrp::Problem.encode(problem))
      input.close

      output = Tempfile.new('optimize-or-tools-output', @tmp_dir, binmode: true)

      correspondant =
        {
          'path_cheapest_arc' => 0, 'global_cheapest_arc' => 1,
          'local_cheapest_insertion' => 2, 'savings' => 3,
          'parallel_cheapest_insertion' => 4, 'first_unbound' => 5,
          'christofides' => 6
        }

      if vrp.configuration.preprocessing.first_solution_strategy.any? &&
         correspondant[vrp.configuration.preprocessing.first_solution_strategy.first].nil?
        first_solution_strategy = vrp.configuration.preprocessing.first_solution_strategy
        raise "Inconsistent first solution strategy used internally: #{first_solution_strategy}"
      end

      config = vrp.configuration
      resolution = config.resolution
      preprocessing = config.preprocessing

      time_limit_in_ms = resolution.duration || @optimize_time
      neighbourhood = preprocessing.neighbourhood_size
      no_solution_improvement_limit = resolution.iterations_without_improvment || @iterations_without_improvment
      time_out_multiplier = resolution.time_out_multiplier || @time_out_multiplier
      vehicle_limit = resolution.vehicle_limit
      solver_parameter = preprocessing.first_solution_strategy.first
      cmd =
        [
          "#{@exec_ortools} ",
          time_limit_in_ms && "-time_limit_in_ms #{time_limit_in_ms.round}",
          preprocessing.prefer_short_segment ? '-nearby' : nil,
          (!resolution.evaluate_only && neighbourhood) ? "-neighbourhood #{neighbourhood}" : nil,
          no_solution_improvement_limit && "-no_solution_improvement_limit #{no_solution_improvement_limit}",
          resolution.minimum_duration && "-minimum_duration #{resolution.minimum_duration.round}",
          time_out_multiplier && "-time_out_multiplier #{time_out_multiplier}",
          resolution.init_duration && "-init_duration #{resolution.init_duration.round}",
          vehicle_limit && vehicle_limit < problem.vehicles.size && "-vehicle_limit #{vehicle_limit}",
          solver_parameter ? "-solver_parameter #{correspondant[solver_parameter]}" : nil,
          (resolution.evaluate_only || resolution.batch_heuristic) ? '-only_first_solution' : nil,
          config.restitution.intermediate_solutions ? '-intermediate_solutions' : nil,
          "-instance_file '#{input.path}'",
          "-solution_file '#{output.path}'"
        ].compact.join(' ')

      log cmd

      block&.call() # before creating the optimization process in case optim is canceled

      # Thread.abort_on_exception = true # This doesn't work with Open3.popen
      stdin, stdout_and_stderr, @thread = Open3.popen2e(cmd)

      return if !@thread

      out = ''
      iterations = 0
      cost = nil
      time = 0.0
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        r = /Iteration : ([0-9]+)/.match(line)
        r && (iterations = Integer(r[1]))
        s = / Cost : ([0-9.eE+-]+)/.match(line)
        s && (cost = Float(s[1]))
        t = /Time : ([0-9.eE+-]+)/.match(line)
        t && (time = t[1].to_f)
        log_level =
          if /Final Iteration :/.match(line) ||
             /First solution strategy :/.match(line) ||
             /Using the provided initial solution./.match(line) ||
             /OR-Tools v[0-9]+\.[0-9]+\n/.match(line)
            :info
          elsif r || s || t
            :debug
          else
            :error
          end
        log line.strip, level: log_level
        out += line

        next unless r && t # if there is no iteration and time then there is nothing to do

        begin
          @previous_result =
            if vrp.configuration.restitution.intermediate_solutions && s && !/Final Iteration :/.match(line)
              parse_output(vrp, output)
            end
          # if @previous_result=nil, the block will not override the existing solution
          block&.call(self, iterations, nil, nil, cost, time, @previous_result)
        rescue Google::Protobuf::ParseError => e
          # log and ignore protobuf parsing errors
          log "#{e.class}: #{e.message} (in run_ortools during parse_output)", level: :error
          Raven.capture_exception(e, level: :warn)
        end
      }

      stdin&.close
      stdout_and_stderr&.close

      result = out.split("\n")[-1]
      if @thread.value.success?
        @previous_result =
          if result == 'No solution found...'
            vrp.empty_solution(:ortools)
          else
            parse_output(vrp, output)
          end
        @previous_result
      else # Fatal Error
        message =
          case @thread.value
          when 127
            'Executable does not exist'
          when 137 # Segmentation Fault
            "SIGKILL received: manual intervention or 'oom-killer' [OUT-OF-MEMORY]"
          else
            "Job terminated with unknown thread status: #{@thread.value}"
          end
        raise message
      end
    ensure
      input&.unlink
      output&.close
      output&.unlink
      stdin&.close
      stdout_and_stderr&.close
      if @thread&.alive? # Need to kill the job and its children if it is still alive
        child_pids = []
        IO.popen("ps -ef | grep #{@thread.pid}") { |io|
          child_pids = io.readlines.map do |line|
            parts = line.split(/\s+/)
            parts[1].to_i if parts[2] == @thread.pid.to_s
          end.compact || []
        }
        child_pids << @thread.pid
        child_pids.each{ |pid| Process.kill('KILL', pid) }
      end
      thread_proc&.call([])
      log "<---- run_ortools #{Time.now - tic}sec elapsed", level: :debug
    end

    def update_services_activity_positions(services, services_activity_positions,
                                           id, position, service_index, alternative_index)
      services_activity_positions[:always_first] << "#{id}##{alternative_index}" if
        [:always_first, :exclusive].include?(position)
      services_activity_positions[:never_first] << "#{id}##{alternative_index}" if
        [:never_first, :always_middle].include?(position)
      services_activity_positions[:never_last] << "#{id}##{alternative_index}" if
        [:never_last, :always_middle].include?(position)
      services_activity_positions[:always_last] << "#{id}##{alternative_index}" if
        [:always_last, :exclusive].include?(position)

      return services if position != :never_middle

      services + services.select{ |s| s.problem_index == service_index }.collect{ |s|
        services_activity_positions[:always_first] << id.to_s
        services_activity_positions[:always_last] << "#{id}_alternative"
        copy_s = s.dup
        copy_s.id += '_alternative'
        copy_s
      }
    end

    def corresponding_mission_ids(available_ids, mission_ids)
      mission_ids.collect{ |mission_id|
        correct_id =
          if available_ids.include?(mission_id)
            mission_id
          elsif available_ids.include?("#{mission_id}pickup")
            "#{mission_id}pickup"
          elsif available_ids.include?("#{mission_id}delivery")
            "#{mission_id}delivery"
          end

        available_ids.delete(correct_id)
        correct_id
      }.compact
    end
  end
end
