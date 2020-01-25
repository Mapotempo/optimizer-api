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
require './lib/heuristics/scheduling_heuristic.rb'

module Interpreters
  class PeriodicVisits

    def initialize(vrp)
      @periods = []
      @equivalent_vehicles = {}
      @epoch = Date.new(1970, 1, 1)

      if vrp.schedule_range_indices
        @have_services_day_index = !vrp.services.empty? && vrp.services.none?{ |service| (service.activity ? [service.activity] : service.activities).all?{ |activity| activity.timewindows.none?{ |timewindow| timewindow[:day_index] } } }
        @have_shipments_day_index = !vrp.shipments.empty? && vrp.shipments.none?{ |shipment| shipment.pickup.timewindows.none?{ |timewindow| timewindow[:day_index] } || shipment.delivery.timewindows.none?{ |timewindow| timewindow[:day_index] } }
        @have_vehicles_day_index = vrp.vehicles.none?{ |vehicle| vehicle.sequence_timewindows.none? || vehicle.sequence_timewindows.none?{ |timewindow| timewindow[:day_index] }}

        @unavailable_indices = if vrp.schedule_unavailable_indices
          vrp.schedule_unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= vrp.schedule_range_indices[:start] && unavailable_index <= vrp.schedule_range_indices[:end]
          }.compact
        end
      end
    end

    def expand(vrp, job, &block)
      return vrp unless vrp.schedule_range_indices

      if vrp.preprocessing_first_solution_strategy.to_a.first == 'periodic'
        if vrp.services.empty?
          vrp[:preprocessing_heuristic_result] = {
            cost: nil,
            solvers: ['scheduling_heuristic'],
            iterations: nil,
            routes: [],
            unassigned: [],
            elapsed: nil,
            total_distance: nil
          }
        else
          scheduling_heuristic = Heuristics::Scheduling.new(vrp, generate_vehicles(vrp), job)
          vrp.routes = scheduling_heuristic.compute_initial_solution(vrp, &block)
        end
      end

      vehicles_linked_by_duration = save_relations(vrp, 'vehicle_group_duration').concat(save_relations(vrp, 'vehicle_group_duration_on_weeks')).concat(save_relations(vrp, 'vehicle_group_duration_on_months'))

      vrp.relations = generate_relations(vrp)
      vrp.services = generate_services(vrp)
      compute_days_interval(vrp)
      vrp.shipments = generate_shipments(vrp)

      @periods.uniq!

      vrp.rests = []
      vrp.vehicles = generate_vehicles(vrp).sort{ |a, b|
        a.global_day_index && b.global_day_index && a.global_day_index != b.global_day_index ? a.global_day_index <=> b.global_day_index : a.id <=> b.id
      }
      vehicles_linked_by_duration = get_all_vehicles_in_relation(vehicles_linked_by_duration)
      generate_relations_on_periodic_vehicles(vrp, vehicles_linked_by_duration)

      if vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic'
        vrp.routes = generate_routes(vrp)
      end

      vrp
    end

    def generate_relations(vrp)
      new_relations = vrp.relations.collect{ |relation|
        first_service = vrp.services.find{ |service| service.id == relation.linked_ids.first } ||
        vrp.shipments.find{ |shipment| "#{shipment.id}pickup" == relation.linked_ids.first || "#{shipment.id}delivery" == relation.linked_ids.first }
        relation_linked_ids = relation.linked_ids.select{ |mission_id|
          vrp.services.one? { |service| service.id == mission_id } ||
          vrp.shipments.one? { |shipment| "#{shipment.id}pickup" == relation.linked_ids.first || "#{shipment.id}delivery" == relation.linked_ids.first }
        }
        related_missions = relation_linked_ids.collect{ |mission_id|
          vrp.services.find{ |service| service.id == mission_id } ||
          vrp.shipments.find{ |shipment| "#{shipment.id}pickup" == mission_id || "#{shipment.id}delivery" == mission_id }
        }
        if first_service && first_service.visits_number &&
        related_missions.all?{ |mission| mission.visits_number == first_service.visits_number }
          (1..(first_service.visits_number || 1)).collect{ |relation_index|
            new_relation = Marshal::load(Marshal.dump(relation))
            new_relation.linked_ids = relation_linked_ids.collect.with_index{ |mission_id, index|
              additional_tag = if mission_id == "#{related_missions[index].id}pickup"
                'pickup'
              elsif  mission_id == "#{related_missions[index].id}delivery"
                'delivery'
              else
                ''
              end
              "#{related_missions[index].id}_#{relation_index}_#{first_service.visits_number || 1}#{additional_tag}"
            }
            new_relation
          }
        end
      }.compact.flatten
    end

    def generate_services(vrp)
      new_services = vrp.services.collect{ |service|
        if !service.unavailable_visit_day_indices.empty?
          service.unavailable_visit_day_indices.delete_if{ |unavailable_index|
            unavailable_index.negative? || unavailable_index > vrp.schedule_range_indices[:end]
          }.compact
        end
        if @unavailable_indices
          service.unavailable_visit_day_indices += @unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= vrp.schedule_range_indices[:start] && unavailable_index <= vrp.schedule_range_indices[:end]
          }.compact
          service.unavailable_visit_day_indices.uniq
        end

        if service.visits_number
          if service.minimum_lapse && service.maximum_lapse && service.visits_number > 1
            (2..service.visits_number).each{ |index|
              current_lapse = (index -1) * service.minimum_lapse.to_i
              vrp.relations << Models::Relation.new(:type => "minimum_day_lapse",
              :linked_ids => ["#{service.id}_1_#{service.visits_number}", "#{service.id}_#{index}_#{service.visits_number}"],
              :lapse => current_lapse)
            }
            (2..service.visits_number).each{ |index|
              current_lapse = (index -1) * service.maximum_lapse.to_i
              vrp.relations << Models::Relation.new(:type => "maximum_day_lapse",
              :linked_ids => ["#{service.id}_1_#{service.visits_number}", "#{service.id}_#{index}_#{service.visits_number}"],
              :lapse => current_lapse)
            }
          else
            if service.minimum_lapse && service.visits_number > 1
              (2..service.visits_number).each{ |index|
                current_lapse = service.minimum_lapse.to_i
                vrp.relations << Models::Relation.new(:type => "minimum_day_lapse",
                :linked_ids => ["#{service.id}_#{index-1}_#{service.visits_number}", "#{service.id}_#{index}_#{service.visits_number}"],
                :lapse => current_lapse)
              }
            end
            if service.maximum_lapse && service.visits_number > 1
              (2..service.visits_number).each{ |index|
                current_lapse = service.maximum_lapse.to_i
                vrp.relations << Models::Relation.new(:type => "maximum_day_lapse",
                :linked_ids => ["#{service.id}_#{index-1}_#{service.visits_number}", "#{service.id}_#{index}_#{service.visits_number}"],
                :lapse => current_lapse)
              }
            end
          end
          @periods << service.visits_number
          visit_period = (vrp.schedule_range_indices[:end] + 1).to_f / service.visits_number
          timewindows_iterations = (visit_period /(6 || 1)).ceil
          ## Create as much service as needed
          (0..service.visits_number - 1).collect{ |visit_index|
            new_service = nil
            if !service.unavailable_visit_indices || service.unavailable_visit_indices.none?{ |unavailable_index| unavailable_index == visit_index }
              new_service = Marshal::load(Marshal.dump(service))
              new_service.id = "#{new_service.id}_#{visit_index+1}_#{service.visits_number}"
              new_service.visits_number = 1
              (new_service.activity ? [new_service.activity] : new_service.activities).each{ |activity|
                activity.timewindows = if !activity.timewindows.empty?
                  new_timewindows = activity.timewindows.collect{ |timewindow|
                    if timewindow.day_index
                      Models::Timewindow.new(start: (timewindow.start || 0) + timewindow.day_index * 86400,
                                            end: (timewindow.end || 86399) + timewindow.day_index * 86400)
                    elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                      (0..[6, vrp.schedule_range_indices[:end]].min).collect{ |day_index|
                        Models::Timewindow.new(start: (timewindow.start || 0) + (day_index).to_i * 86400,
                                              end: (timewindow.end || 86399) + (day_index).to_i * 86400)
                      }
                    else
                      Models::Timewindow.new(start: timewindow.start, end: timewindow.end)
                    end
                  }.flatten.sort_by{ |timewindow| timewindow.start }.compact.uniq
                  if new_timewindows.size > 0
                    new_timewindows
                  end
                end
                if !service.minimum_lapse && !service.maximum_lapse
                  new_service.skills += ["#{visit_index+1}_f_#{service.visits_number}"]
                end
              }

              new_service
            else
              nil
            end
            new_service
          }.compact
        else
          service
        end
      }.flatten
    end

    def generate_shipments(vrp)
      new_shipments = vrp.shipments.collect{ |shipment|
        if !shipment.unavailable_visit_day_indices.empty?
          shipment.unavailable_visit_day_indices.delete_if{ |unavailable_index|
            unavailable_index.negative? || unavailable_index > vrp.schedule_range_indices[:end]
          }.compact
        end
        if @unavailable_indices
          shipment.unavailable_visit_day_indices += @unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= vrp.schedule_range_indices[:start] && unavailable_index <= vrp.schedule_range_indices[:end]
          }.compact
          shipment.unavailable_visit_day_indices.uniq
        end

        if shipment.visits_number
          if shipment.minimum_lapse && shipment.maximum_lapse && shipment.visits_number > 1
            (2..shipment.visits_number).each{ |index|
              current_lapse = (index -1) * shipment.minimum_lapse.to_i
              vrp.relations << Models::Relation.new(:type => "minimum_day_lapse",
              :linked_ids => ["#{shipment.id}_1_#{shipment.visits_number}", "#{shipment.id}_#{index}_#{shipment.visits_number}"],
              :lapse => current_lapse)
            }
            (2..shipment.visits_number).each{ |index|
              current_lapse = (index -1) * shipment.maximum_lapse.to_i
              vrp.relations << Models::Relation.new(:type => "maximum_day_lapse",
              :linked_ids => ["#{shipment.id}_1_#{shipment.visits_number}", "#{shipment.id}_#{index}_#{shipment.visits_number}"],
              :lapse => current_lapse)
            }
          else
            if shipment.minimum_lapse && shipment.visits_number > 1
              (2..shipment.visits_number).each{ |index|
                current_lapse = shipment.minimum_lapse.to_i
                vrp.relations << Models::Relation.new(:type => "minimum_day_lapse",
                :linked_ids => ["#{shipment.id}_#{index - 1}_#{shipment.visits_number}", "#{shipment.id}_#{index}_#{shipment.visits_number}"],
                :lapse => current_lapse)
              }
            end
            if shipment.maximum_lapse && shipment.visits_number > 1
              (2..shipment.visits_number).each{ |index|
                current_lapse = shipment.maximum_lapse.to_i
                vrp.relations << Models::Relation.new(:type => "maximum_day_lapse",
                :linked_ids => ["#{shipment.id}_#{index - 1}_#{shipment.visits_number}", "#{shipment.id}_#{index}_#{shipment.visits_number}"],
                :lapse => current_lapse)
              }
            end
          end
          @periods << shipment.visits_number
          visit_period = (vrp.schedule_range_indices[:end] + 1).to_f / shipment.visits_number
          timewindows_iterations = (visit_period /(6 || 1)).ceil
          ## Create as much shipment as needed
          (0..shipment.visits_number-1).collect{ |visit_index|
            new_shipment = nil
            if !shipment.unavailable_visit_indices || shipment.unavailable_visit_indices.none?{ |unavailable_index| unavailable_index == visit_index }
              new_shipment = Marshal::load(Marshal.dump(shipment))
              new_shipment.id = "#{new_shipment.id}_#{visit_index + 1}_#{new_shipment.visits_number}"

              new_shipment.pickup.timewindows = if !shipment.pickup.timewindows.empty?
                new_timewindows = shipment.pickup.timewindows.collect{ |timewindow|
                  if timewindow.day_index
                    Models::Timewindow.new(
                      start: timewindow[:start] + timewindow.day_index * 86400,
                      end: timewindow[:end] + timewindow.day_index * 86400
                    )
                  elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                    (0..[6, vrp.schedule_range_indices[:end]].min).collect{ |day_index|
                      Models::Timewindow.new(
                        start: timewindow[:start] + (day_index).to_i * 86400,
                        end: timewindow[:end] + (day_index).to_i * 86400
                      )
                    }
                  else
                    Models::Timewindow.new(
                      start: timewindow[:start],
                      end: timewindow[:end]
                    )
                  end
                }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
                if new_timewindows.size > 0
                  new_timewindows
                end
              end

              new_shipment.delivery.timewindows = if !shipment.delivery.timewindows.empty?
                new_timewindows = shipment.delivery.timewindows.collect{ |timewindow|
                  if timewindow.day_index
                    Models::Timewindow.new(start: timewindow.start + timewindow.day_index * 86400,
                                           end: timewindow.end + timewindow.day_index * 86400)
                  elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                    (0..[6, vrp.schedule_range_indices[:end]].min).collect{ |day_index|
                      Models::Timewindow.new(start: timewindow.start + (day_index).to_i * 86400,
                                             end: timewindow.end + (day_index).to_i * 86400)
                    }
                  else
                    Models::Timewindow.new(start: timewindow.start, end: timewindow.end)
                  end
                }.flatten.sort_by{ |timewindow| timewindow.start }.compact.uniq
                if new_timewindows.size > 0
                  new_timewindows
                end
              end

              if !shipment.minimum_lapse && !shipment.maximum_lapse
                new_shipment.skills += ["#{visit_index+1}_f_#{shipment.visits_number}"]
              end
              new_shipment
            else
              nil
            end
            new_shipment
          }.compact
        else
          shipment
        end
      }.flatten
    end

    def build_vehicle_unavailable_work_day_indices(vehicle)
      if @unavailable_indices
        vehicle.unavailable_work_day_indices += @unavailable_indices.collect{ |unavailable_index|
          unavailable_index
        }
        vehicle.unavailable_work_day_indices.uniq!
      end
    end

    def build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations, same_vehicle_list, lapses_list)
      new_vehicle = Marshal::load(Marshal.dump(vehicle))
      new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index}"
      @equivalent_vehicles[vehicle.id] << new_vehicle.id
      if vehicle.overall_duration
        same_vehicle_list[-1].push(new_vehicle.id)
        lapses_list[-1] = vehicle.overall_duration
      end
      new_vehicle.global_day_index = vehicle_day_index
      new_vehicle.skills = associate_skills(new_vehicle, vehicle_day_index, vrp.schedule_range_indices[:end])
      new_vehicle.rests = generate_rests(vehicle, vehicle_day_index % 7, rests_durations)
      new_vehicle.sequence_timewindows = nil
      vrp.rests += new_vehicle.rests
      vrp.services.select{ |service| service.sticky_vehicles.any?{ |sticky_vehicle| sticky_vehicle == vehicle } }.each{ |service|
        service.sticky_vehicles.insert(-1, new_vehicle)
      }
      new_vehicle
    end

    def generate_vehicles(vrp)
      same_vehicle_list = []
      lapses_list = []
      rests_durations = Array.new(vrp.vehicles.size, 0)
      vrp.vehicles.each{ |vehicle|
        vehicle.id = vehicle.original_id if vehicle.original_id # if we used work_day clustering
        vehicle.original_id = vehicle.id if vehicle.original_id.nil?
      }
      new_vehicles = vrp.vehicles.collect{ |vehicle|
        build_vehicle_unavailable_work_day_indices(vehicle)
        @equivalent_vehicles[vehicle.id] = []
        if vehicle.overall_duration
          same_vehicle_list << []
          lapses_list.push(-1)
        end
        if vehicle.sequence_timewindows && !vehicle.sequence_timewindows.empty?
          (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |vehicle_day_index|
            next if vehicle.unavailable_work_day_indices && vehicle.unavailable_work_day_indices.include?(vehicle_day_index)

            vehicle.sequence_timewindows.select{ |timewindow| timewindow[:day_index].nil? || timewindow[:day_index] == vehicle_day_index % 7 }.collect{ |associated_timewindow|
              new_vehicle = build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations, same_vehicle_list, lapses_list)
              t_start = (vehicle_day_index % 7) * 86400 + associated_timewindow[:start]
              t_end = (vehicle_day_index % 7) * 86400 + associated_timewindow[:end]
              new_vehicle.timewindow = Models::Timewindow.new(start: t_start, end: t_end)
              new_vehicle.timewindow.day_index = nil
              new_vehicle
            }
          }.compact
        elsif !@have_services_day_index.nil? && !@have_shipments_day_index || vehicle.timewindow
          (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |vehicle_day_index|
            next if vehicle.unavailable_work_day_indices && vehicle.unavailable_work_day_indices.include?(vehicle_day_index) ||
                    vehicle.timewindow&.day_index && vehicle_day_index % 7 != vehicle.timewindow.day_index

            new_vehicle = build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations, same_vehicle_list, lapses_list)
            new_vehicle
          }.compact
        else
          @equivalent_vehicles[vehicle.id] << vehicle.id
          if vehicle.overall_duration
            same_vehicle_list[-1].push(new_vehicle.id)
            lapses_list[-1] = vehicle.overall_duration
          end
          vehicle
        end
      }.flatten
      same_vehicle_list.each.with_index{ |list, index|
        if lapses_list[index] && lapses_list[index] != -1
          new_relation = Models::Relation.new(
            type: 'vehicle_group_duration',
            linked_vehicle_ids: list,
            lapse: lapses_list[index] + rests_durations[index]
          )
          vrp.relations << new_relation
      end
      }
      new_vehicles
    end

    def check_with_vroom(vrp, route, service, residual_time, residual_time_for_vehicle)
      vroom = OptimizerWrapper::VROOM
      problem = {
        matrices: vrp[:matrices],
        points: vrp[:points].collect{ |pt|
          {
            id: pt.id,
            matrix_index: pt.matrix_index
          }
        },
        vehicles: [{
          id: route[:vehicle].id,
          start_point_id: route[:vehicle].start_point_id,
          matrix_id: route[:vehicle].matrix_id
        }],
        services: route[:mission_ids].collect{ |s|
          {
            id: s,
            activity: {
              point_id: vrp[:services].select{ |service| s == service.id }[0][:activity][:point_id],
              duration: vrp[:services].select{ |service| s == service.id }[0][:activity][:duration]
            }
          }
        }
      }
      problem[:services] << {
        id: service.id,
          activity: {
            point_id: service[:activity][:point_id],
            duration: service[:activity][:duration]
          }
      }
      vrp = Models::Vrp.create(problem)
      progress = 0
      result = vroom.solve(vrp){ |avancement, total|
        progress += 1
      }
      travel_time = 0
      first = true
      result[:routes][0][:activities].each{ |a|
        first ? first = false : travel_time += (a[:detail][:setup_duration] ? a[:travel_time] + a[:detail][:duration] + a[:detail][:setup_duration] : a[:travel_time] + a[:detail][:duration])
      }

      time_back_to_depot = 0
      if route[:vehicle][:end_point_id] != nil
        this_service_index = vrp.services.find{|s| s.id == service.id}[:activity][:point][:matrix_index]
        time_back_to_depot = vrp[:matrices][0][:time][this_service_index][route[:vehicle][:end_point][:matrix_index]]
      end

      if !residual_time_for_vehicle[route[:vehicle][:id]]
        true
      else
        additional_time = travel_time + time_back_to_depot - residual_time_for_vehicle[route[:vehicle].id][:last_computed_time]
        if additional_time <= residual_time[residual_time_for_vehicle[route[:vehicle].id][:idx]]
          residual_time[residual_time_for_vehicle[route[:vehicle].id][:idx]] -= additional_time
          residual_time_for_vehicle[route[:vehicle].id][:last_computed_time] += additional_time
          true
        else
          false
        end
      end
    end

    def generate_routes(vrp)
      # preparation for route creation
      residual_time = []
      idx = 0
      residual_time_for_vehicle = {}
      vrp.relations.select{ |r| r.type == 'vehicle_group_duration'}.each{ |r|
        r.linked_vehicle_ids.each{ |v|
          residual_time_for_vehicle[v] = {
            idx: idx,
            last_computed_time: 0
          }
        }
        residual_time.push(r[:lapse])
        idx += 1
      }

      # route creation
      routes = vrp.vehicles.collect{ |vehicle|
        {
          mission_ids: [],
          vehicle: vehicle
        }
      }
      vrp.services.each{ |service|
        service_sequence_data = /(.+)_([0-9]+)\_([0-9]+)/.match(service.id).to_a
        service_id = service_sequence_data[1]
        current_index = service_sequence_data[2].to_i
        sequence_size = service_sequence_data[-1].to_i
        related_indices = vrp.services.collect{ |r_service|
          match_result = /(.+)_([0-9]+)\_([0-9]+)/.match(r_service.id).to_a
          match_result[2].to_i if match_result[1] == service_id && match_result[2].to_i < current_index
        }.compact
        previous_service_index = related_indices.max
        gap_with_previous = current_index - previous_service_index if previous_service_index
        previous_service_route = routes.find{ |sub_route|
          !sub_route[:mission_ids].empty? && sub_route[:mission_ids].find{ |id|
            id == "#{service_id}_#{previous_service_index}_#{sequence_size}"
          }
        }
        candidate_route = routes.find{ |route|
          # looking for the first vehicle possible
          # days are compatible
          (service.unavailable_visit_day_indices.nil? || !service.unavailable_visit_day_indices.include?(route[:vehicle].global_day_index)) &&
          (current_index == 1 || current_index > 1 && service.minimum_lapse &&
          previous_service_index && previous_service_route && route[:vehicle].global_day_index >= previous_service_route[:vehicle].global_day_index + (gap_with_previous * service.minimum_lapse).truncate ||
          !service.minimum_lapse && (route[:vehicle].skills & service.skills).size == service.skills.size) &&
          # we do not exceed vehicles max duration
          (!residual_time_for_vehicle[route[:vehicle][:id]] || check_with_vroom(vrp, route, service, residual_time, residual_time_for_vehicle))
          # Verify timewindows too
        }
        if candidate_route
          candidate_route[:mission_ids] << service.id
        else
          log "Can't insert mission #{service.id}"
        end
      }
      routes
    end

    def generate_rests(vehicle, day_index, rests_durations)
      new_rests = vehicle.rests.collect{ |rest|
        new_rest = nil
        if rest.timewindows.empty? || rest.timewindows.any?{ |timewindow| timewindow[:day_index] == day_index }
          new_rest = Marshal::load(Marshal.dump(rest))
          new_rest.id = "#{new_rest.id}_#{day_index+1}"
          rests_durations[-1] += new_rest.duration
          new_rest.timewindows = rest.timewindows.select{ |timewindow| timewindow[:day_index] == day_index }.collect{ |timewindow|
            if timewindow.day_index && timewindow.day_index == day_index
              {
                id: ("#{timewindow[:id]} #{timewindow.day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                start: timewindow[:start] ? timewindow[:start] + timewindow[:day_index] * 86400 : nil,
                end: timewindow[:end] ? timewindow[:end] + timewindow[:day_index] * 86400 : nil
              }.delete_if { |k, v| !v }
            else
                {
                  id: ("#{timewindow[:id]} #{day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                  start: timewindow[:start] ? timewindow[:start] + (day_index).to_i * 86400 : nil,
                  end: timewindow[:end] ? timewindow[:end] + (day_index).to_i * 86400 : nil
                }.delete_if { |k, v| !v }
            end
          }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
        end
        new_rest
      }.compact
    end

    def associate_skills(new_vehicle, vehicle_day_index, schedule_end)
      if new_vehicle.skills.empty?
        new_vehicle.skills = [@periods.collect{ |period| "#{(vehicle_day_index * period / (schedule_end + 1)).to_i + 1}_f_#{period}" }]
      else
        new_vehicle.skills.collect!{ |alternative_skill|
          alternative_skill + @periods.collect{ |period| "#{(vehicle_day_index * period / (schedule_end + 1)).to_i + 1}_f_#{period}" }
        }
      end
    end

    def compute_days_interval(vrp)
      first_day = vrp.schedule_range_indices[:start]
      last_day = vrp.schedule_range_indices[:end]

      vrp.services.each{ |service|
        service_index, service_total_quantity = service[:id].split('_')[-2].to_i, service[:id].split('_')[-1].to_i

        day = first_day
        nb_services_seen = 0
        service_first_possible_day = -1
        service_last_possible_day = -1

        while day <= last_day && service_first_possible_day == -1
          if !service.unavailable_visit_day_indices.include?(day)
            nb_services_seen += 1
            service_first_possible_day = nb_services_seen == service_index ? day : -1
            day += service.minimum_lapse || 1
          end

          day += 1
        end

        day = last_day
        nb_services_seen = service_total_quantity
        while day >= first_day && service_last_possible_day == -1
          service_last_possible_day = nb_services_seen == service_index ? day : -1

          if !service.unavailable_visit_day_indices.include?(day)
            nb_services_seen -= 1
            day -= service.minimum_lapse || 1
          end

          day -= 1
        end
        service[:first_possible_day] = service_first_possible_day
        service[:last_possible_day] = service_last_possible_day
      }
    end

    def save_relations(vrp, relation_type)
      relations_to_save = vrp.relations.select{ |r| r.type == relation_type }.collect{ |r|
        {
          type: r.type,
          linked_vehicle_ids: r.linked_vehicle_ids,
          lapse: r.lapse,
          periodicity: r.periodicity
        }
      }
    end

    def get_all_vehicles_in_relation(relations)
      relations&.each{ |r|
        new_list = []
        r[:linked_vehicle_ids].each{ |v|
            new_list.concat(@equivalent_vehicles[v])
        }
        r[:linked_vehicle_ids] = new_list
      }
    end

    def generate_relations_on_periodic_vehicles(vrp, list)
      new_relations = []
      list.each{ |r|
        case r[:type]
        when 'vehicle_group_duration'
          new_relations << [r[:linked_vehicle_ids], r[:lapse]]
        when 'vehicle_group_duration_on_weeks'
          current_sub_list = []
          first_index = r[:linked_vehicle_ids].min.split('_').last.to_i
          in_periodicity = first_index + 7 * (r[:periodicity] - 1)
          max_index = (in_periodicity..in_periodicity + 7).find{ |index| index % 7 == 6 }
          r[:linked_vehicle_ids].sort_by{ |v_id| v_id.split('_').last.to_i }.each{ |v_id|
            this_index = v_id.split('_').last.to_i
            if this_index <= max_index
              current_sub_list << v_id
            else
              new_relations << [current_sub_list, r[:lapse]]
              current_sub_list = [v_id]
              first_index = this_index
              in_periodicity = first_index + 7 * (r[:periodicity] - 1)
              max_index = (in_periodicity..in_periodicity + 7).find{ |index| index % 7 == 6 }
            end
          }
          new_relations << [current_sub_list, r[:lapse]]
        when 'vehicle_group_duration_on_months'
          (0..vrp.schedule_months_indices.size - 1).step(r[:periodicity]).collect{ |v| p vrp.schedule_months_indices.slice(v, v + r[:periodicity]).flatten }.each{ |month_indices|
            new_relations << [r[:linked_vehicle_ids].select{ |id| month_indices.include?(id.split('_').last.to_i) }, r[:lapse]]
          }
        end
      }

      new_relations.each{ |linked_vehicle_ids, lapse|
        vrp.relations << Models::Relation.new(
          type: 'vehicle_group_duration',
          linked_vehicle_ids: linked_vehicle_ids,
          lapse: lapse
        )
      }
    end
  end
end
