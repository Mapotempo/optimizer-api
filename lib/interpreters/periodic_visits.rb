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
module Interpreters
  class PeriodicVisits

    def initialize(vrp)
      @periods = []
      @equivalent_vehicles = {}
      @planning = {}
      @indices = {}
      @order = []
      @candidate_service_ids = []
      @to_plan_service_ids = []
      @same_located = {}
      @point_available_days = {}
      @services_unlocked_by = {} # in the case of same_point_day, service with higher heuristic period unlocks others
      @services_of_period = {}
      @problem_vehicles = {}
      @candidate_routes = {}
      @candidate_vehicles = []
      @vehicle_day_completed = {}
      @limit = 1700
      @uninserted = {}
      @min_nb_scheduled_in_one_day = nil
      @cost = 0
      @travel_time = 0
      @same_point_day = vrp.resolution_same_point_day
      @allow_vehicle_change = vrp.schedule_allow_vehicle_change
    end

    def expand(vrp)
      if vrp.schedule_range_indices || vrp.schedule_range_date

        epoch = Date.new(1970,1,1)
        @real_schedule_start = vrp.schedule_range_indices ? vrp.schedule_range_indices[:start] : (vrp.schedule_range_date[:start].to_date - epoch).to_i
        real_schedule_end = vrp.schedule_range_indices ? vrp.schedule_range_indices[:end] : (vrp.schedule_range_date[:end].to_date - epoch).to_i
        @shift = vrp.schedule_range_indices ? @real_schedule_start : vrp.schedule_range_date[:start].to_date.cwday - 1
        @schedule_end = real_schedule_end - @real_schedule_start
        @schedule_start = 0

        @have_services_day_index = !vrp.services.empty? && vrp.services.none?{ |service| service.activity.timewindows.none? || service.activity.timewindows.none?{ |timewindow| timewindow[:day_index] }}
        @have_shipments_day_index = !vrp.shipments.empty? && vrp.shipments.none?{ |shipment| shipment.pickup.timewindows.none? || shipment.pickup.timewindows.none?{ |timewindow| timewindow[:day_index] } ||
          shipment.delivery.timewindows.none? || shipment.delivery.timewindows.none?{ |timewindow| timewindow[:day_index] }}
        @have_vehicles_day_index = vrp.vehicles.none?{ |vehicle| vehicle.sequence_timewindows.none? || vehicle.sequence_timewindows.none?{ |timewindow| timewindow[:day_index] }}

        @unavailable_indices = if vrp.schedule_unavailable_indices
          vrp.schedule_unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= @schedule_start && unavailable_index <= @schedule_end
          }.compact
        elsif vrp.schedule_unavailable_date
          vrp.schedule_unavailable_date.collect{ |date|
            (date - epoch).to_i - @real_schedule_start if (date - epoch).to_i >= @real_schedule_start
          }.compact
        end

        if vrp.preprocessing_use_periodic_heuristic
          if vrp.services.empty?
            vrp[:preprocessing_heuristic_result] = {
              cost: nil,
              solvers: ["heuristic"],
              iterations: nil,
              routes: [],
              unassigned: [],
              elapsed: nil,
              total_distance: nil
            }
          else
            vrp.routes = compute_initial_solution(vrp)
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
        generate_relations_on_periodic_vehicles(vrp,vehicles_linked_by_duration)

        if !vrp.preprocessing_use_periodic_heuristic
          vrp.routes = generate_routes(vrp)
        end
      end
      vrp
    rescue => e
      puts e
      puts e.backtrace
      raise
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
            unavailable_index < 0 || unavailable_index > @schedule_end
          }.compact
        end
        if service.unavailable_visit_day_date
          epoch = Date.new(1970,1,1)
          service.unavailable_visit_day_indices += service.unavailable_visit_day_date.collect{ |unavailable_date|
            (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
          }.compact
        end
        if @unavailable_indices
          service.unavailable_visit_day_indices += @unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= @schedule_start && unavailable_index <= @schedule_end
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
          visit_period = (@schedule_end + 1).to_f/service.visits_number
          timewindows_iterations = (visit_period /(6 || 1)).ceil
          ## Create as much service as needed
          (0..service.visits_number-1).collect{ |visit_index|
            new_service = nil
            if !service.unavailable_visit_indices || service.unavailable_visit_indices.none?{ |unavailable_index| unavailable_index == visit_index }
              new_service = Marshal::load(Marshal.dump(service))
              new_service.id = "#{new_service.id}_#{visit_index+1}_#{new_service.visits_number}"
              new_service.activity.timewindows = if !service.activity.timewindows.empty?
                new_timewindows = service.activity.timewindows.collect{ |timewindow|
                  if timewindow.day_index
                    {
                      id: ("#{timewindow[:id]} #{timewindow.day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start] + timewindow.day_index * 86400,
                      end: timewindow[:end] + timewindow.day_index * 86400
                    }.delete_if { |k, v| !v }
                  elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                    (0..[6, @schedule_end].min).collect{ |day_index|
                      {
                        id: ("#{timewindow[:id]} #{day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                        start: timewindow[:start] + (day_index).to_i * 86400,
                        end: timewindow[:end] + (day_index).to_i * 86400
                      }.delete_if { |k, v| !v }
                    }
                  else
                    {
                      id: (timewindow[:id] if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start],
                      end: timewindow[:end]
                    }.delete_if { |k, v| !v }
                  end
                }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
                if new_timewindows.size > 0
                  new_timewindows
                end
              end
              if !service.minimum_lapse && !service.maximum_lapse
                new_service.skills += ["#{visit_index+1}_f_#{service.visits_number}"]
              end
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
            unavailable_index < 0 || unavailable_index > @schedule_end
          }.compact
        end
        if shipment.unavailable_visit_day_date
          epoch = Date.new(1970,1,1)
          shipment.unavailable_visit_day_indices = shipment.unavailable_visit_day_date.collect{ |unavailable_date|
            (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
          }.compact
        end
        if @unavailable_indices
          shipment.unavailable_visit_day_indices += @unavailable_indices.collect{ |unavailable_index|
            unavailable_index if unavailable_index >= @schedule_start && unavailable_index <= @schedule_end
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
          visit_period = (@schedule_end + 1).to_f/shipment.visits_number
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
                    {
                      id: ("#{timewindow[:id]} #{timewindow.day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start] + timewindow.day_index * 86400,
                      end: timewindow[:end] + timewindow.day_index * 86400
                    }.delete_if { |k, v| !v }
                  elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                    (0..[6, @schedule_end].min).collect{ |day_index|
                      {
                        id: ("#{timewindow[:id]} #{day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                        start: timewindow[:start] + (day_index).to_i * 86400,
                        end: timewindow[:end] + (day_index).to_i * 86400
                      }.delete_if { |k, v| !v }
                    }
                  else
                    {
                      id: (timewindow[:id] if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start],
                      end: timewindow[:end]
                    }.delete_if { |k, v| !v }
                  end
                }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
                if new_timewindows.size > 0
                  new_timewindows
                end
              end

              new_shipment.delivery.timewindows = if !shipment.delivery.timewindows.empty?
                new_timewindows = shipment.delivery.timewindows.collect{ |timewindow|
                  if timewindow.day_index
                    {
                      id: ("#{timewindow[:id]} #{timewindow.day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start] + timewindow.day_index * 86400,
                      end: timewindow[:end] + timewindow.day_index * 86400
                    }.delete_if { |k, v| !v }
                  elsif @have_services_day_index || @have_vehicles_day_index || @have_shipments_day_index
                    (0..[6, @schedule_end].min).collect{ |day_index|
                      {
                        id: ("#{timewindow[:id]} #{day_index}" if timewindow[:id] && !timewindow[:id].nil?),
                        start: timewindow[:start] + (day_index).to_i * 86400,
                        end: timewindow[:end] + (day_index).to_i * 86400
                      }.delete_if { |k, v| !v }
                    }
                  else
                    {
                      id: (timewindow[:id] if timewindow[:id] && !timewindow[:id].nil?),
                      start: timewindow[:start],
                      end: timewindow[:end]
                    }.delete_if { |k, v| !v }
                  end
                }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
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

    def generate_vehicles(vrp)
      same_vehicle_list = []
      lapses_list = []
      rests_durations = []
      new_vehicles = vrp.vehicles.collect{ |vehicle|
        @equivalent_vehicles[vehicle.id] = []
        if vehicle.overall_duration
          same_vehicle_list.push([])
          lapses_list.push(-1)
        end
        rests_durations.push(0)
        if vehicle.unavailable_work_date
          epoch = Date.new(1970,1,1)
          vehicle.unavailable_work_day_indices = vehicle.unavailable_work_date.collect{ |unavailable_date|
            (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
          }.compact
        end
        if @unavailable_indices
          vehicle.unavailable_work_day_indices += @unavailable_indices.collect{ |unavailable_index|
            unavailable_index
          }
          vehicle.unavailable_work_day_indices.uniq!
        end

        if vehicle.sequence_timewindows && !vehicle.sequence_timewindows.empty?
          new_periodic_vehicle = []
          (@schedule_start..@schedule_end).each{ |vehicle_day_index|
            if !vehicle.unavailable_work_day_indices || vehicle.unavailable_work_day_indices.none?{ |index| index == vehicle_day_index}
              vehicle.sequence_timewindows.select{ |timewindow| !timewindow[:day_index] || timewindow[:day_index] == (vehicle_day_index + @shift) % 7 }.each{ |associated_timewindow|
                new_vehicle = Marshal::load(Marshal.dump(vehicle))
                new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index}"
                new_vehicle.vehicle_id = vehicle.id
                @equivalent_vehicles[vehicle.id] << "#{vehicle.id}_#{vehicle_day_index}"
                if vehicle.overall_duration
                  same_vehicle_list[-1].push(new_vehicle.id)
                  lapses_list[-1] = vehicle.overall_duration
                end
                new_vehicle.timewindow = Marshal::load(Marshal.dump(associated_timewindow))
                new_vehicle.timewindow.id = ("#{associated_timewindow[:id]} #{(vehicle_day_index + @shift) % 7}" if associated_timewindow[:id] && !associated_timewindow[:id].nil?),
                new_vehicle.timewindow.start = (((vehicle_day_index + @shift) % 7 )* 86400 + associated_timewindow[:start]),
                new_vehicle.timewindow.end = (((vehicle_day_index + @shift) % 7 )* 86400 + associated_timewindow[:end])
                new_vehicle.timewindow.day_index = nil
                new_vehicle.global_day_index = vehicle_day_index
                new_vehicle.sequence_timewindows = nil
                new_vehicle.rests = generate_rests(vehicle, (vehicle_day_index + @shift) % 7, rests_durations)
                new_vehicle.skills = associate_skills(new_vehicle, vehicle_day_index)
                vrp.rests += new_vehicle.rests
                vrp.services.select{ |service| service.sticky_vehicles.any?{ sticky_vehicle == vehicle }}.each{ |service|
                  service.sticky_vehicles.insert(-1, new_vehicle)
                }
                new_periodic_vehicle << new_vehicle
              }
            end
          }
          new_periodic_vehicle
        elsif !@have_services_day_index && !@have_shipments_day_index
          new_periodic_vehicle = (@schedule_start..@schedule_end).collect{ |vehicle_day_index|
            if !vehicle.unavailable_work_day_indices || vehicle.unavailable_work_day_indices.none?{ |index| index == vehicle_day_index}
              new_vehicle = Marshal::load(Marshal.dump(vehicle))
              new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index}"
              @equivalent_vehicles[vehicle.id] << "#{vehicle.id}_#{vehicle_day_index}"
              if vehicle.overall_duration
                same_vehicle_list[-1].push(new_vehicle.id)
                lapses_list[-1] = vehicle.overall_duration
              end
              new_vehicle.global_day_index = vehicle_day_index
              new_vehicle.rests = generate_rests(vehicle, (vehicle_day_index + @shift) % 7, rests_durations)
              vrp.rests += new_vehicle.rests
              new_vehicle.skills = associate_skills(new_vehicle, vehicle_day_index)
              vrp.services.select{ |service| service.sticky_vehicles.any?{ |sticky_vehicle| sticky_vehicle == vehicle }}.each{ |service|
                service.sticky_vehicles.insert(-1, new_vehicle)
              }
              new_vehicle
            end
          }.compact
          new_periodic_vehicle
        elsif vehicle.timewindow
          new_periodic_vehicle = []
          (@schedule_start..@schedule_end).each{ |vehicle_day_index|
            if !vehicle.unavailable_work_day_indices || vehicle.unavailable_work_day_indices.none?{ |index| index == vehicle_day_index }
              new_vehicle = Marshal::load(Marshal.dump(vehicle))
              new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index}"
              new_vehicle.vehicle_id = vehicle.id
              new_vehicle.timewindow.id = ("#{new_vehicle.timewindow[:id]} #{(vehicle_day_index + @shift) % 7}" if new_vehicle.timewindow[:id] && !new_vehicle.timewindow[:id].nil?),
              new_vehicle.global_day_index = vehicle_day_index
              new_vehicle.sequence_timewindows = nil
              new_vehicle.rests = generate_rests(vehicle, (vehicle_day_index + @shift) % 7, rests_durations)
              vrp.rests += new_vehicle.rests
              new_vehicle.skills = associate_skills(new_vehicle, vehicle_day_index)
              @equivalent_vehicles[vehicle.id] << "#{vehicle.id}_#{vehicle_day_index}"
              if vehicle.overall_duration
                same_vehicle_list[-1].push(new_vehicle.id)
                lapses_list[-1] = vehicle.overall_duration
              end
              vrp.services.select{ |service| service.sticky_vehicles.any?{ sticky_vehicle == vehicle }}.each{ |service|
                service.sticky_vehicles.insert(-1, new_vehicle)
              }
              new_periodic_vehicle << new_vehicle
            end
          }
          new_periodic_vehicle
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
          new_relation = Models::Relation.new({
            type: 'vehicle_group_duration',
            linked_vehicle_ids: list,
            lapse: lapses_list[index] + rests_durations[index]
          })
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
          puts "Can't insert mission #{service.id}"
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

    def associate_skills(new_vehicle, vehicle_day_index)
      if new_vehicle.skills.empty?
        new_vehicle.skills = [@periods.collect{ |period| "#{(vehicle_day_index * period / (@schedule_end + 1)).to_i + 1}_f_#{period}" }]
      else
        new_vehicle.skills.collect!{ |alternative_skill|
          alternative_skill + @periods.collect{ |period| "#{(vehicle_day_index * period / (@schedule_end + 1)).to_i + 1}_f_#{period}" }
        }
      end
    end

    def compute_days_interval(vrp)
      if vrp.schedule_range_indices
        first_day = vrp[:schedule_range_indices][:start]
        last_day = vrp[:schedule_range_indices][:end]
      else
        first_day = vrp[:schedule_range_date][:start].to_date
        last_day = vrp[:schedule_range_date][:end].to_date
      end

      vrp[:services].each{ |service|
        service_index, service_total_quantity = service[:id].split('_')[-2].to_i, service[:id].split('_')[-1].to_i

        day = first_day
        day_index = 0
        nb_services_seen = 0
        service_first_possible_day = -1
        service_last_possible_day = -1

        while day <= last_day && service_first_possible_day == -1
          if ((!service[:unavailable_visit_day_indices] || service[:unavailable_visit_day_indices].size == 0 || !(service[:unavailable_visit_day_indices].include? day_index))) &&
              (!service[:unavailable_visit_day_date] || service[:unavailable_visit_day_date].size == 0 || !(service[:unavailable_visit_day_date].include? day))
            nb_services_seen += 1
            service_first_possible_day = nb_services_seen == service_index ? day_index : -1
            if service[:minimum_lapse]
              day += service[:minimum_lapse]
              day_index += service[:minimum_lapse]
            end
          end

          day += 1
          day_index += 1
        end

        day = last_day
        day_index = (last_day-first_day).to_i
        nb_services_seen = service_total_quantity
        while day >= first_day && service_last_possible_day == -1
          service_last_possible_day = nb_services_seen == service_index ? day_index : -1

          if (!service[:unavailable_visit_day_indices] || service[:unavailable_visit_day_indices].size == 0 || !(service[:unavailable_visit_day_indices].include? day)) &&
              (!service[:unavailable_visit_day_date] || service[:unavailable_visit_day_date].size == 0 || !(service[:unavailable_visit_day_date].include? day))
            nb_services_seen -= 1
            if service[:minimum_lapse]
              day -= service[:minimum_lapse]
              day_index -= service[:minimum_lapse]
            end
          end

          day -= 1
          day_index -= 1
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
      if relations
        relations.each{ |r|
          new_list = []
          r[:linked_vehicle_ids].each{ |v|
            new_list.concat(@equivalent_vehicles[v])
          }
          r[:linked_vehicle_ids] = new_list
        }
      end
    end

    def generate_relations_on_periodic_vehicles(vrp, list)
      list.each{ |r|
        case r[:type]
        when 'vehicle_group_duration'
          vrp.relations << Models::Relation.new({
            type: 'vehicle_group_duration',
            linked_vehicle_ids: r[:linked_vehicle_ids],
            lapse: r[:lapse]
          })
        when 'vehicle_group_duration_on_weeks', 'vehicle_group_duration_on_months'
          relations = {}
          if vrp.schedule_range_date
            first_date = (r[:type]=='vehicle_group_duration_on_months' ? vrp.schedule_range_date[:start].month : vrp.schedule_range_date[:start].strftime('%W').to_i)
            r[:linked_vehicle_ids].each{ |v|
              v_date = (r[:type]=='vehicle_group_duration_on_months' ? (vrp.schedule_range_date[:start] + v.split("_").last.to_i).month : (vrp.schedule_range_date[:start] + v.split("_").last.to_i).strftime('%W').to_i)
              relation_nb = ((v_date - first_date) / r[:periodicity]).floor
              if relations.key?(relation_nb)
                relations[relation_nb][:vehicles] << v
              else
                relations[relation_nb] = {
                  type: 'vehicle_group_duration',
                  vehicles: [v],
                  lapse: r[:lapse]
                }
              end
            }
          else
            r[:linked_vehicle_ids].each{ |v|
              vrp[:vehicles].select{ |vehicle| vehicle.id == v }.each{ |vehicle|
                week_nb = (vehicle.global_day_index + @shift)/7.floor
                periodicity = (r[:periodicity].nil? ? 1 : r[:periodicity])
                relation_nb = week_nb/periodicity.floor
                if relations.key?(relation_nb)
                  relations[relation_nb][:vehicles] << vehicle.id
                else
                  relations[relation_nb] = {
                    type: 'vehicle_group_duration',
                    vehicles: [vehicle.id],
                    lapse: r[:lapse]
                  }
                end
              }
            }
          end
          relations.each{ |key, relation|
            vrp.relations << Models::Relation.new({
              type: 'vehicle_group_duration',
              linked_vehicle_ids: relation[:vehicles],
              lapse: relation[:lapse]
            })
          }
        end
      }
    end

    def solve_tsp(vrp)
      if vrp.points.size == 1
        @order = [vrp.points[0][:location][:id]]
      else
        vroom = OptimizerWrapper::VROOM

        # creating services to use
        services = []
        vrp.points.each{ |pt|
          service = vrp.services.find{ |service_| service_[:activity][:point_id] == pt[:id] }
          if service
            services << {
              id: service[:id],
              activity: {
                point_id: service[:activity][:point_id],
                duration: service[:activity][:duration]
              }
            }
          end
        }
        problem = {
          matrices: vrp[:matrices],
          points: vrp[:points].collect{ |pt|
            {
              id: pt.id,
              matrix_index: pt.matrix_index
            }
          },
          vehicles: [{
            id: vrp[:vehicles][0][:id],
            start_point_id: vrp[:vehicles][0][:start_point_id],
            matrix_id: vrp[:vehicles][0][:matrix_id]
          }],
          services: services
        }
        tsp = Models::Vrp.create(problem)
        progress = 0
        result = vroom.solve(tsp){
          progress += 1
        }
        @order = result[:routes][0][:activities].collect{ |stop| 
          vrp.points.find{ |pt| pt[:id] == stop[:point_id]}[:location][:id]
        }
      end
    end

    def compute_positions(vehicle, day)
      route = @candidate_routes[vehicle][day]
      positions = []
      last_inserted = 0

      route[:current_route].each{ |point_seen|
        real_position = @order.index(point_seen[:point_id])
        positions << (last_inserted > -1 && real_position >= last_inserted ? @order.index(point_seen[:point_id]) : -1 )
        last_inserted = positions.last
      }

      @candidate_routes[vehicle][day][:positions_in_order] = positions
    end

    def insert_point_in_route(route_data, point_to_add, day, services)
      current_route = route_data[:current_route]
      @candidate_service_ids.delete(point_to_add[:id])
      first_at_this_point = current_route.find{ |step| step[:point_id] == point_to_add[:point] }

      current_route.insert(point_to_add[:position],
        id: point_to_add[:id],
        point_id: point_to_add[:point],
        start: point_to_add[:start],
        arrival: point_to_add[:arrival],
        end: point_to_add[:end],
        considered_setup_duration: point_to_add[:considered_setup_duration],
        max_shift: point_to_add[:potential_shift],
        number_in_sequence: 1)

      if point_to_add[:position] < current_route.size - 1
        current_route[point_to_add[:position] + 1][:start] = point_to_add[:next_start_time]
        current_route[point_to_add[:position] + 1][:arrival] = point_to_add[:next_arrival_time]
        current_route[point_to_add[:position] + 1][:end] = point_to_add[:next_final_time]
        current_route[point_to_add[:position] + 1][:max_shift] = current_route[point_to_add[:position] + 1][:max_shift] ? current_route[point_to_add[:position] + 1][:max_shift] - point_to_add[:shift] : nil
        if !point_to_add[:shift].zero?
          shift = point_to_add[:shift]
          (point_to_add[:position] + 2..current_route.size - 1).each{ |point|
            if shift > 0
              initial_shift_with_previous = current_route[point][:start] - (current_route[point - 1][:end] - shift)
              shift = [shift - initial_shift_with_previous, 0].max
              current_route[point][:start] += shift
              current_route[point][:arrival] += shift
              current_route[point][:end] += shift
              current_route[point][:max_shift] = current_route[point][:max_shift] ? current_route[point][:max_shift] - shift : nil
            elsif shift < 0
              new_potential_start = current_route[point][:start] + shift
              soonest_authorized = services[current_route[point][:id]][:tw].empty? ? new_potential_start : services[current_route[point][:id]][:tw].find{ |tw| tw[:day_index].nil? || tw[:day_index] == day % 7 && current_route[point][:start] }[:start] - matrix(route_data, current_route[point - 1][:id], current_route[point][:id])
              if soonest_authorized > new_potential_start
                # barely tested because very few cases :
                shift = shift - (soonest_authorized - new_potential_start)
              end
              current_route[point][:start] += shift
              current_route[point][:end] += shift
              current_route[point][:max_shift] = current_route[point][:max_shift] ? current_route[point][:max_shift] - shift : nil
            end
          }
        end
      end
    end

    def fill_day_in_planning(vehicle, route_data, services)
      day = route_data[:global_day_index]
      current_route = route_data[:current_route]
      positions_in_order = route_data[:positions_in_order]
      service_to_insert = true
      temporary_excluded_services = []

      while service_to_insert
        insertion_costs = compute_insertion_costs(vehicle, day, positions_in_order, services, route_data, temporary_excluded_services)
        if !insertion_costs.empty?
          # there are services we can add
          point_to_add = insertion_costs.sort_by{ |s| s[:additional_route_time] / services[s[:id]][:nb_visits]**2 }[0] # au carré?
          best_index = find_best_index(services, point_to_add[:id], route_data)

          if @same_point_day
            best_index[:end] = best_index[:end] - services[best_index[:id]][:group_duration] + services[best_index[:id]][:duration]
          end

          insert_point_in_route(route_data, best_index, day, services)
          @to_plan_service_ids.delete(point_to_add[:id])
          services[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
          if point_to_add[:position] == best_index[:position]
            positions_in_order.insert(point_to_add[:position], point_to_add[:position_in_order])
          else
            positions_in_order.insert(best_index[:position], best_index[:position_in_order])
          end

        else
          service_to_insert = false
          @vehicle_day_completed[vehicle][day] = true
          if !current_route.empty?
            @travel_time += route_data[:start_point_id] ? matrix(route_data, route_data[:start_point_id], current_route.first[:id]) : 0
            @travel_time += (0..current_route.size - 2).collect{ |position| matrix(route_data, current_route[position][:id], current_route[position + 1][:id]) }.sum
            @travel_time += route_data[:end_point_id] ? matrix(route_data, current_route.last[:id], route_data[:start_point_id]) : 0
            @cost = @travel_time
          end
          @planning[vehicle][day] = {
            vehicle: {
              vehicle_id: route_data[:vehicle_id],
              start_point_id: route_data[:start_point_id],
              end_point_id: route_data[:end_point_id],
              tw_start: route_data[:tw_start],
              tw_end: route_data[:tw_end],
              matrix_id: route_data[:matrix_id]
            },
            services: current_route
          }
          @min_nb_scheduled_in_one_day = [current_route.size, @min_nb_scheduled_in_one_day.to_i].min
        end
      end
    end

    def find_timewindows(insertion_index, previous_service, previous_service_end, inserted_service, inserted_service_info, route_data, duration, filling_candidate_route = false)
      list = []
      route_time = (insertion_index.zero? ? matrix(route_data, route_data[:start_point_id], inserted_service) : matrix(route_data, previous_service, inserted_service))
      setup_duration = route_data[:current_route].find{ |step| step[:point_id] == inserted_service_info[:point_id] }.nil? ? inserted_service_info[:setup_duration] : 0
      if filling_candidate_route
        duration = inserted_service_info[:duration]
      end

      if inserted_service_info[:tw].nil? || inserted_service_info[:tw].empty?
        start = insertion_index.zero? ? route_data[:tw_start] : previous_service_end
        final = start + route_time + setup_duration + duration
        list << {
          start_time: start,
          final_time: final,
          end_tw: nil,
          max_shift: nil,
          setup_duration: setup_duration
        }
      else
        inserted_service_info[:tw].select{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:global_day_index] % 7 }.each{ |tw|
          start_time = (insertion_index.zero? ? [route_data[:tw_start], tw[:start] - route_time].max : [previous_service_end, tw[:start] - route_time].max)
          final_time = start_time + route_time + setup_duration + duration

          if start_time <= tw[:end]
            list << {
              start_time: start_time,
              final_time: final_time,
              end_tw: tw[:end],
              max_shift: tw[:end] - (start_time + route_time),
              setup_duration: setup_duration
            }
          end
        }
      end

      # will only contain values associated to one tw, that is : only one start,final and max_shift will be returned
      list
    end

    def compute_shift(route_data, services_info, service_inserted, inserted_final_time, next_service, next_service_id)
      route = route_data[:current_route]

      if route.empty?
        [nil, nil, nil, matrix(route_data, route_data[:start_point_id], service_inserted) + matrix(route_data, service_inserted, route_data[:end_point_id])]
      elsif next_service_id
        dist_to_next = matrix(route_data, service_inserted, next_service_id)
        next_start, next_end = compute_tw_for_next(inserted_final_time, services_info[next_service_id], route[next_service][:considered_setup_duration], dist_to_next)
        shift = next_end - route[next_service][:end]

        [next_start, next_start + dist_to_next, next_end, shift]
      else
        [nil, nil, nil, inserted_final_time - route.last[:end]]
      end
    end

    def compute_value_at_position(route_data, services, service, position, possibles, duration, position_in_order, filling_candidate_route = false)
      value_inserted = false

      route = route_data[:current_route]
      previous_service = (position.zero? ? route_data[:start_point_id] : route[position - 1][:id])
      previous_service_end = (position.zero? ? nil : route[position - 1][:end])
      list = find_timewindows(position, previous_service, previous_service_end, service, services[service], route_data, duration, filling_candidate_route)
      list.each{ |current_tw|
        start_time = current_tw[:start_time]
        arrival_time = start_time + matrix(route_data, previous_service, service)
        final_time = current_tw[:final_time]
        next_id = route[position] ? route[position][:id] : nil
        next_start, next_arrival, next_end, shift = compute_shift(route_data, services, service, final_time, position, next_id)
        time_back_to_depot = (position == route.size ? final_time + matrix(route_data, service, route_data[:end_point_id]) : route.last[:end] + matrix(route_data, route.last[:id], route_data[:end_point_id]) + shift)
        acceptable_shift = route[position] && route[position][:max_shift] ? route[position][:max_shift] >= shift : true
        if acceptable_shift && route[position + 1]
          computed_shift = Marshal.load(Marshal.dump(shift))
          (position + 1..route.size - 1).each{ |pos|
            initial_shift_with_previous = route[pos][:start] - (route[pos - 1][:end])
            computed_shift = [shift - initial_shift_with_previous, 0].max
            if route[pos][:max_shift] && route[pos][:max_shift] < computed_shift
              acceptable_shift = false
              break
            end
          }
        end
        acceptable_shift_for_itself = (current_tw[:end_tw] ? arrival_time <= current_tw[:end_tw] : true)
        acceptable_shift_for_group = true
        if @same_point_day && !filling_candidate_route && !services[service][:tw].empty?
          # all services start on time
          additional_durations = services[service][:duration] + current_tw[:setup_duration]
          @same_located[service].each{ |id|
            acceptable_shift_for_group = current_tw[:max_shift] - additional_durations >= 0
            additional_durations += services[id][:duration]
          }
        end
        if acceptable_shift && time_back_to_depot <= route_data[:tw_end] && acceptable_shift_for_itself && acceptable_shift_for_group
          value_inserted = true
          possibles << {
            id: service,
            point: services[service][:point_id],
            shift: shift,
            start: start_time,
            arrival: arrival_time,
            end: final_time,
            position: position,
            position_in_order: position_in_order,
            considered_setup_duration: current_tw[:setup_duration],
            next_start_time: next_start,
            next_arrival_time: next_arrival,
            next_final_time: next_end,
            potential_shift: current_tw[:max_shift],
            additional_route_time: [0, shift - duration].max,
            dist_from_current_route: (0..route.size - 1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min,
            last_service_end: (position == route.size ? final_time : route.last[:end] + shift)
          }
        end
      }
      [possibles, value_inserted]
    end

    def find_best_index(services, service, route_data, in_adjust = false)
      route = route_data[:current_route]
      possibles = []
      duration = services[service][:duration]
      if !in_adjust
        duration = @same_point_day ? services[service][:group_duration] : services[service][:duration] # this should always work
      end

      if route.empty?
        if services[service][:tw].empty? || services[service][:tw].find{ |tw| tw[:day_index].nil? || tw[:day_index] == route_data[:global_day_index] % 7 }
          tw = find_timewindows(0, nil, nil, service, services[service], route_data, duration)[0]
          if tw[:final_time] + matrix(route_data, service, route_data[:end_point_id]) <= route_data[:tw_end]
            possibles << {
              id: service,
              point: services[service][:point_id],
              shift: matrix(route_data, route_data[:start_point_id], service) + matrix(route_data, service, route_data[:end_point_id]) + services[service][:duration],
              start: tw[:start_time],
              arrival: tw[:start_time] + matrix(route_data, route_data[:start_point_id], service),
              end: tw[:final_time],
              position: 0,
              position_in_order: -1,
              considered_setup_duration: tw[:setup_duration],
              next_start_time: nil,
              next_arrival_time: nil,
              next_final_time: nil,
              potential_shift: tw[:max_shift],
              additional_route_time: matrix(route_data, route_data[:start_point_id], service) + matrix(route_data, service, route_data[:end_point_id]),
              dist_from_current_route: (0..route.size - 1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min
            }
          end
        end
      elsif route.find_index{ |stop| stop[:point_id] == services[service][:point_id] }
        same_point_index = route.size - route.reverse.find_index{ |stop| stop[:point_id] == services[service][:point_id] }
        if in_adjust
          possibles, value_inserted = compute_value_at_position(route_data, services, service, same_point_index, possibles, services[service][:duration], -1, true)
        else
          possibles, value_inserted = compute_value_at_position(route_data, services, service, same_point_index, possibles, duration, -1, false)
        end
      else
        previous_point = route_data[:start_point_id]
        (0..route.size).each{ |position|
          if position == route.size || route[position][:point_id] != previous_point
            if in_adjust
              possibles, value_inserted = compute_value_at_position(route_data, services, service, position, possibles, services[service][:duration], -1, true)
            else
              possibles, value_inserted = compute_value_at_position(route_data, services, service, position, possibles, duration, -1, false)
            end
          end
          if position < route.size
            previous_point = route[position][:point_id]
          end
        }
      end

      possibles.sort_by!{ |possible_position| possible_position[:last_service_end] }[0]
    end

    def compute_tw_for_next(inserted_final_time, next_service_info, next_service_considered_setup, dist_from_inserted)
      sooner_start = (next_service_info[:tw] && !next_service_info[:tw].empty? ? next_service_info[:tw][0][:start] - dist_from_inserted : inserted_final_time)
      new_start = [sooner_start, inserted_final_time].max
      new_end = new_start + dist_from_inserted + next_service_considered_setup + next_service_info[:duration]

      [new_start, new_end]
    end

    def matrix(route_data, start, arrival)
      if start.nil? || arrival.nil?
        0
      else
        if start.is_a?(String)
          start = @indices[start]
        end

        if arrival.is_a?(String)
          arrival = @indices[arrival]
        end
        # Time matrix is mandatory !
        @matrices.find{ |matrix| matrix[:id] == route_data[:matrix_id] }[:time][start][arrival]
      end
    end

    def compute_insertion_costs(vehicle, day, positions_in_order, services, route_data, excluded)
      route = route_data[:current_route]
      insertion_costs = []

      @to_plan_service_ids.select{ |service| !excluded.include?(service) &&
                    (@same_point_day && services[service][:group_capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] } || !@same_point_day && services[service][:capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] }) &&
                    (!@same_point_day || @point_available_days[services[service][:point_id]].empty? || @point_available_days[services[service][:point_id]].include?(day)) &&
                    !services[service][:unavailable_days].include?(day) }.each{ |service_id|
        period = services[service_id][:heuristic_period]
        n_visits = services[service_id][:nb_visits]
        duration = @same_point_day ? services[service_id][:group_duration] : services[service_id][:duration]
        latest_authorized_day = @schedule_end - (period || 0) * (n_visits - 1)

        if period.nil? || day <= latest_authorized_day && (day + period..@schedule_end).step(period).find{ |current_day| @vehicle_day_completed[vehicle][current_day] }.nil?
          s_position_in_order = @order.index(services[service_id][:point_id])
          first_bigger_position_in_sol = positions_in_order.select{ |pos| pos > s_position_in_order }.min
          insertion_index = positions_in_order.index(first_bigger_position_in_sol).nil? ? route.size : positions_in_order.index(first_bigger_position_in_sol)

          if route.find{ |stop| stop[:point_id] == services[service_id][:point_id] }
            insertion_index = route.size - route.reverse.find_index{ |stop| stop[:point_id] == services[service_id][:point_id] }
          end

          insertion_costs, index_accepted = compute_value_at_position(route_data, services, service_id, insertion_index, insertion_costs, duration, s_position_in_order, false)

          if !index_accepted && !route.empty? && !route.find{ |stop| stop[:point_id] == services[service_id][:point_id] }
            # we can try to find another index
            other_indices = find_best_index(services, service_id, route_data)
            # if !other_indices.nil?
            if other_indices
              insertion_costs << other_indices
            end
          end
        end
      }

      insertion_costs
    end

    def clean_routes(services, service, day_finished, vehicle)
      peri = services[service][:heuristic_period]
      (day_finished..@schedule_end).step(peri).each{ |changed_day|
        if @planning[vehicle] && @planning[vehicle][changed_day]
          @planning[vehicle][changed_day][:services].delete_if{ |stop| stop[:id] == service }
        end

        if @candidate_routes[vehicle] && @candidate_routes[vehicle][changed_day]
          @candidate_routes[vehicle][changed_day][:current_route].delete_if{ |stop| stop[:id] == service }
        end
      }

      (1..services[service][:nb_visits]).each{ |number_in_sequence|
        @uninserted["#{service}_#{number_in_sequence}_#{services[service][:nb_visits]}"] = {
          original_service: service,
          reason: 'Only partial assignment could be found'
        }
      }
    end

    def adjust_candidate_routes(vehicle, day_finished, services, services_to_add, all_services, days_available)
      days_filled = []
      services_to_add.each{ |service|
        peri = services[service[:id]][:heuristic_period]
        if peri && peri > 0
          added = [1]
          visit_number = 1
          (day_finished + peri..@schedule_end).step(peri).each{ |day|
            if days_available.include?(day) && visit_number < services[service[:id]][:nb_visits]
              inserted = false
              if @candidate_routes[vehicle].keys.include?(day) && !@vehicle_day_completed[vehicle][day] && visit_number < services[service[:id]][:nb_visits]

                best_index = find_best_index(services, service[:id], @candidate_routes[vehicle][day], true) if services[service[:id]][:capacity].all?{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] - qty >= 0 }
                if best_index
                  days_filled << day

                  insert_point_in_route(@candidate_routes[vehicle][day], best_index, day, services)
                  services[service[:id]][:capacity].each{ |need, qty| @candidate_routes[vehicle][day][:capacity_left][need] -= qty }
                  inserted = true
                  added << visit_number + 1
                  @candidate_routes[vehicle][day][:current_route].find{ |stop| stop[:id] == service[:id] }[:number_in_sequence] += visit_number

                elsif @candidate_vehicles.size > 2 && @allow_vehicle_change
                  # not used yet
                  inserted = try_on_different_vehicle(day, service, all_services)
                end
              elsif @vehicle_day_completed[vehicle][day] && @allow_vehicle_change
                # not used yet
                inserted = try_on_different_vehicle(day, service, all_services)
              end

              if !inserted
                @uninserted["#{service[:id]}_#{service[:number_in_sequence] + visit_number}_#{services[service[:id]][:nb_visits]}"] = {
                  original_service: service[:id],
                  reason: 'Visit not assignable by heuristic'
                }
              end
            elsif visit_number < services[service[:id]][:nb_visits]
              @uninserted["#{service[:id]}_#{service[:number_in_sequence] + visit_number}_#{services[service[:id]][:nb_visits]}"] = {
                original_service: service[:id],
                reason: 'First visit day does not allow to affect this visit'
              }
            end
            # even if we do not add it we should increment this value in order not to add too many services
            visit_number += 1
          }
          if visit_number < services[service[:id]][:nb_visits]
            first_missing = visit_number + 1
            (first_missing..services[service[:id]][:nb_visits]).each{ |missing_s|
              @uninserted["#{service[:id]}_#{missing_s}_#{services[service[:id]][:nb_visits]}"] = {
                original_service: service[:id],
                reason: 'First visit assigned too late to affect other visits'
              }
            }
          end
        end
      }

      days_filled.uniq.each{ |d|
        compute_positions(vehicle, d)
      }
    end

    def compute_capacities(quantities, vehicle, available_units = [])
      capacities = {}

      if quantities
        quantities.each{ |unit|
          if vehicle
            if capacities[unit[:unit][:id]]
              capacities[unit[:unit][:id]] += unit[:limit].to_f
            else
              capacities[unit[:unit][:id]] = unit[:limit].to_f
            end
          elsif available_units.include?(unit[:unit][:id])
            # if vehicled do not have this unit then this unit should be ignored
            # with clustering, issue is open about assigning vehicles with right capacities to services
            if capacities[unit[:unit][:id]]
              capacities[unit[:unit][:id]] += unit[:value].to_f
            else
              capacities[unit[:unit][:id]] = unit[:value].to_f
            end
          end
        }
      end

      capacities
    end

    def compute_best_common_tw(services, set)
      first_with_tw = set.find{ |service| services[service[:id]][:tw] && !services[service[:id]][:tw].empty? }
      if first_with_tw
        group_tw = services[first_with_tw[:id]][:tw].collect{ |tw| {day_index: tw[:day_index], start: tw[:start], end: tw[:end] } }
        # all timewindows are assigned to a day
        group_tw.select{ |timewindow| timewindow[:day_index].nil? }.each{ |tw| (0..6).each{ |day|
            group_tw << { day_index: day, start: tw[:start], end: tw[:end] }
        }}
        group_tw.delete_if{ |tw| tw[:day_index].nil? }

        # finding minimal common timewindow
        set.each{ |service|
          if !services[service[:id]][:tw].empty?
            # remove all tws with no intersection with this service tws
            group_tw.delete_if{ |tw1|
              services[service[:id]][:tw].none?{ |tw2|
                (tw2[:day_index].nil? || tw2[:day_index] == tw1[:day_index]) &&
                (tw2[:start].between?(tw1[:start], tw1[:end]) || tw2[:end].between?(tw1[:start], tw1[:end]) || tw2[:start] <= tw1[:start] && tw2[:end] >= tw1[:end])
              }
            }

            if !group_tw.empty?
              # adjust all tws with intersections with this point tws
              services[service[:id]][:tw].each{ |tw|
                intersecting_tws = group_tw.select{ |t| (t[:day_index].nil? || tw[:day_index].nil? || t[:day_index] == tw[:day_index]) && (tw[:start].between?(t[:start], t[:end]) || tw[:end].between?(t[:start], t[:end]) || tw[:start] <= t[:start] && tw[:end] >= t[:start]) }
                if !intersecting_tws.empty?
                  intersecting_tws.each{ |t|
                    t[:start] = [t[:start], tw[:start]].max
                    t[:end] = [t[:end], tw[:end]].min
                  }
                end
              }
            end
          end
        }

        group_tw.delete_if{ |tw| tw[:start] && tw[:end] && tw[:start] == tw[:end] }
        group_tw
      else
        []
      end
    end

    def basic_fill(services_data)
      until @candidate_vehicles.empty?
        current_vehicle = @candidate_vehicles[0]
        days_available = @candidate_routes[current_vehicle].keys.sort_by!{ |day|
          [@candidate_routes[current_vehicle][day][:current_route].size, @candidate_routes[current_vehicle][day][:tw_end] - @candidate_routes[current_vehicle][day][:tw_start]]
        }
        current_day = days_available[0]

        until @candidate_service_ids.empty? || current_day.nil?
          initial_services = @candidate_routes[current_vehicle][current_day][:current_route].collect{ |s| s[:id] }
          fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day], services_data)
          new_services = @planning[current_vehicle][current_day][:services].reject{ |s| initial_services.include?(s[:id]) }
          days_available.delete(current_day)
          @candidate_routes[current_vehicle].delete(current_day)
          adjust_candidate_routes(current_vehicle, current_day, services_data, new_services, @planning[current_vehicle][current_day][:services], days_available)
          while @candidate_routes[current_vehicle].any?{ |_day, day_data| !day_data[:current_route].empty? }
            current_day = @candidate_routes[current_vehicle].max_by{ |_day, day_data| day_data[:current_route].size }.first
            initial_services = @candidate_routes[current_vehicle][current_day][:current_route].collect{ |s| s[:id] }
            fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day], services_data)
            new_services = @planning[current_vehicle][current_day][:services].reject{ |s| initial_services.include?(s[:id]) }
            adjust_candidate_routes(current_vehicle, current_day, services_data, new_services, @planning[current_vehicle][current_day][:services], days_available)

            days_available.delete(current_day)
            @candidate_routes[current_vehicle].delete(current_day)
          end

          current_day = days_available[0]
        end

        # we have filled all days for current vehicle
        @candidate_vehicles.delete(current_vehicle)
      end
    end

    def grouped_fill(services_data)
      @candidate_vehicles.each{ |current_vehicle|
        possible_to_fill = true
        nb_of_days = @candidate_routes[current_vehicle].keys.size
        forbbiden_days = []

        while possible_to_fill
          best_day = @candidate_routes[current_vehicle].reject{ |day, _route| forbbiden_days.include?(day) }.sort_by{ |_day, route_data| route_data[:current_route].empty? ? 0 : route_data[:current_route].sum{ |stop| stop[:end] - stop[:start] } }[0][0]
          route_data = @candidate_routes[current_vehicle][best_day]
          insertion_costs = compute_insertion_costs(current_vehicle, best_day, route_data[:positions_in_order], services_data, route_data, [])

          if !insertion_costs.empty?

            initial_services = @candidate_routes[current_vehicle][best_day][:current_route].collect{ |s| s[:id] }
            point_to_add = insertion_costs.sort_by{ |s| s[:additional_route_time] / services_data[s[:id]][:nb_visits]**2 }[0]
            best_index = find_best_index(services_data, point_to_add[:id], route_data)
            best_index[:end] = best_index[:end] - services_data[best_index[:id]][:group_duration] + services_data[best_index[:id]][:duration]

            insert_point_in_route(route_data, best_index, best_day, services_data)

            services_data[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
            if point_to_add[:position] == best_index[:position]
              route_data[:positions_in_order].insert(point_to_add[:position], point_to_add[:position_in_order])
            else
              route_data[:positions_in_order].insert(best_index[:position], -1)
            end
            @to_plan_service_ids.delete(best_index[:id])

            # adding all points of same familly and frequence
            start = best_index[:end]
            max_shift = best_index[:potential_shift]
            additional_durations = services_data[best_index[:id]][:duration] + best_index[:considered_setup_duration]
            @same_located[best_index[:id]].each_with_index{ |service_id, i|
              route_data[:current_route].insert(best_index[:position] + i + 1,
                id: service_id,
                point_id: best_index[:point],
                start: start,
                arrival: start,
                end: start + services_data[service_id][:duration],
                considered_setup_duration: 0,
                max_shift: max_shift ? max_shift - additional_durations : nil,
                number_in_sequence: 1)
              additional_durations += services_data[service_id][:duration]
              @to_plan_service_ids.delete(service_id)
              @candidate_service_ids.delete(service_id)
              start += services_data[service_id][:duration]
              services_data[service_id][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
              route_data[:positions_in_order].insert(best_index[:position] + i + 1, route_data[:positions_in_order][best_index[:position]])
            }

            new_services = route_data[:current_route].reject{ |s| initial_services.include?(s[:id]) }
            adjust_candidate_routes(current_vehicle, best_day, services_data, new_services, route_data[:current_route], @candidate_routes[current_vehicle].keys)

            if @services_unlocked_by[best_index[:id]] && !@services_unlocked_by[best_index[:id]].empty?
              @to_plan_service_ids += @services_unlocked_by[best_index[:id]]
              forbbiden_days = [] # new services are available so we may need these days
            end
          else
            forbbiden_days << best_day
          end

          if @to_plan_service_ids.empty? || forbbiden_days.size == nb_of_days
            possible_to_fill = false
          end
        end
      }
    end

    def compute_initial_solution(vrp)
      starting_time = Time.now

      # Solve TSP - Build a large Tour to define an arbitrary insertion order
      solve_tsp(vrp)

      services_data = {}
      has_sequence_timewindows = vrp[:vehicles][0][:timewindow].nil?

      # Collect services data
      available_units = vrp.vehicles.collect{ |vehicle| vehicle[:capacities] ? vehicle[:capacities].collect{ |capacity| capacity[:unit_id] } : nil }.flatten.compact.uniq
      vrp.services.each{ |service|
        epoch = Date.new(1970, 1, 1)
        service[:unavailable_visit_day_indices] += service[:unavailable_visit_day_date].to_a.collect{ |unavailable_date|
          (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
        }.compact
        has_every_day_index = has_sequence_timewindows && !vrp.vehicles[0].sequence_timewindows.empty? && ((vrp.vehicles[0].sequence_timewindows.collect{ |tw| tw.day_index }.uniq & (0..6).to_a).size == 7)
        services_data[service.id] = {
          capacity: compute_capacities(service[:quantities], false, available_units),
          setup_duration: service[:activity][:setup_duration],
          duration: service[:activity][:duration],
          heuristic_period: (service[:visits_number] == 1 ? nil : (@schedule_end > 7 && has_sequence_timewindows && !has_every_day_index ? (service[:minimum_lapse].to_f / 7).ceil * 7 : (service[:minimum_lapse].nil? ? 1 : service[:minimum_lapse].ceil))),
          nb_visits: service[:visits_number],
          point_id: service[:activity][:point][:location][:id],
          tw: service[:activity][:timewindows] ?  service[:activity][:timewindows] : [],
          unavailable_days: service[:unavailable_visit_day_indices]
        }

        @candidate_service_ids << service.id
        @to_plan_service_ids << service.id

        @indices[service[:id]] = vrp[:points].find{ |pt| pt[:id] == service[:activity][:point][:id] }[:matrix_index]
      }

      if @same_point_day
        @to_plan_service_ids = []
        vrp.points.each{ |point|
          same_located_set = vrp.services.select{ |service| service[:activity][:point][:location][:id] == point[:location][:id] }.sort_by{ |s| s[:visits_number] }

          if !same_located_set.empty?
            group_tw = compute_best_common_tw(services_data, same_located_set)

            if group_tw.empty? && !same_located_set.all?{ |service| services_data[service[:id]][:tw].nil? || services_data[service[:id]][:tw].empty? }
              # reject group because no common tw
              same_located_set.each{ |service|
                (1..service[:visits_number]).each{ |index|
                  @candidate_service_ids.delete(service[:id])
                  @to_plan_service_ids.delete(service[:id])
                  @uninserted["#{service[:id]}_#{index}_#{service[:visits_number]}"] = {
                    original_service: service[:id],
                    reason: 'Same_point_day option related : services at this geografical point have no compatible timewindow'
                  }
                }
              }
            else
              representative_ids = []
              last_representative = nil
              # one representative per freq
              same_located_set.collect{ |service| services_data[service[:id]][:heuristic_period] }.uniq.each{ |period|
                sub_set = same_located_set.select{ |s| services_data[s[:id]][:heuristic_period] == period }
                representative_id = sub_set[0][:id]
                last_representative = representative_id
                representative_ids << representative_id
                services_data[representative_id][:tw] = group_tw
                services_data[representative_id][:group_duration] = sub_set.sum{ |s| s[:activity][:duration] }

                @same_located[representative_id] = sub_set.delete_if{ |s| s[:id] == representative_id }.collect{ |s| s[:id] }
                services_data[representative_id][:group_capacity] = Marshal.load(Marshal.dump(services_data[representative_id][:capacity]))
                @same_located[representative_id].each{ |service_id|
                  services_data[service_id][:capacity].each{ |unit, value| services_data[representative_id][:group_capacity][unit] += value }
                }
              }

              # each set has available days
              @point_available_days[point[:location][:id]] = []
              @to_plan_service_ids << representative_ids.last
              @services_unlocked_by[representative_ids.last] = representative_ids.slice(0, representative_ids.size - 1).to_a
            end

          end
        }
      end

      @matrices = vrp[:matrices]
      vrp[:vehicles].each{ |vehicle|
        @candidate_vehicles << vehicle[:id]
        @candidate_routes[vehicle[:id]] = {}
        @vehicle_day_completed[vehicle[:id]] = {}
        @planning[vehicle[:id]] = {}
      }
      generate_vehicles(vrp).each{ |vehicle|
        if vehicle[:start_point_id]
           @indices[vehicle[:start_point_id]] = vrp[:points].find{ |pt| pt[:id] == vehicle[:start_point_id] }[:matrix_index]
        end
        if vehicle[:end_point_id]
         @indices[vehicle[:end_point_id]] = vrp[:points].find{ |pt| pt[:id] == vehicle[:end_point_id] }[:matrix_index]
        end
        @problem_vehicles[vehicle[:vehicle_id]] = Hash.new if !@problem_vehicles.has_key?(vehicle[:vehicle_id])
        @problem_vehicles[vehicle[:vehicle_id]][vehicle[:global_day_index]] = vehicle
        original_vehicle_id = vehicle[:id].split("_").slice(0, vehicle[:id].split('_').size-1).join('_')
        capacity = compute_capacities(vehicle[:capacities], true)
        vrp.units.reject{ |unit| capacity.keys.include?(unit[:id]) }.each{ |unit| capacity[unit[:id]] = 0.0 }
        @candidate_routes[original_vehicle_id][vehicle[:global_day_index]] = {
          vehicle_id: vehicle[:id],
          global_day_index: vehicle[:global_day_index],
          tw_start: vehicle[:timewindow][:start] < 84600 ? vehicle[:timewindow][:start] : vehicle[:timewindow][:start] - ((vehicle[:global_day_index] + @shift) % 7) * 86400,
          tw_end: vehicle[:timewindow][:end] < 84600 ? vehicle[:timewindow][:end] : vehicle[:timewindow][:end] - ((vehicle[:global_day_index] + @shift) % 7) * 86400,
          start_point_id: vehicle[:start_point_id],
          end_point_id: vehicle[:end_point_id],
          matrix_id: vehicle[:matrix_id],
          current_route: [],
          capacity: capacity,
          capacity_left: Marshal.load(Marshal.dump(capacity)),
          positions_in_order: []
        }
        @vehicle_day_completed[original_vehicle_id][vehicle[:global_day_index]] = false
      }

      if @same_point_day
        # group_services here ?
        grouped_fill(services_data)
      else
        basic_fill(services_data)
      end

      @candidate_routes.each{ |vehicle, data| data.each{ |day, route_data|
        @planning[vehicle][day] = {
          vehicle: {
            vehicle_id: route_data[:vehicle_id],
            start_point_id: route_data[:start_point_id],
            end_point_id: route_data[:end_point_id],
            tw_start: route_data[:tw_start],
            tw_end: route_data[:tw_end],
            matrix_id: route_data[:matrix_id]
          },
          services: route_data[:current_route]
        }
      }}

      really_uninserted = 0
      @candidate_service_ids.each{ |service_id|
        really_uninserted += services_data[service_id][:nb_visits]
      }

      tws = services_data.keys.any?{ |s| services_data[s][:tw] && !services_data[s][:tw].empty? }
      routes = []
      solution = []
      unassigned = []
      @planning.each{ |vehicle, all_days_routes|
        ordered_days = all_days_routes.keys.sort
        ordered_days.each{ |day|
          route = all_days_routes[day]
          missions_list = []
          computed_activities = []
          if route[:vehicle][:start_point_id]
            computed_activities << {
              point_id: route[:vehicle][:start_point_id],
              detail: {
                lat: vrp[:points].find{ |point| point[:id] == route[:vehicle][:start_point_id] }[:location][:lat],
                lon: vrp[:points].find{ |point| point[:id] == route[:vehicle][:start_point_id] }[:location][:lon],
                quantities: []
              }
            }
          end

          day_name = { 0 => "mon", 1 => "tue", 2 => "wed", 3 => "thu", 4 => "fri", 5 => "sat", 6 => "sun" }
          route[:services].each{ |point|
            service_in_vrp = vrp.services.find{ |s| s[:id] == point[:id] }
            computed_activities << {
              day_week_num: "#{day%7}_#{day/7}",
              day_week: "#{day_name[day%7]}_w#{day/7 + 1}",
              service_id: "#{point[:id]}_#{point[:number_in_sequence]}_#{service_in_vrp[:visits_number]}",
              point_id: service_in_vrp[:activity][:point_id],
              begin_time: point[:end].to_i - service_in_vrp[:activity][:duration],
              departure_time: point[:end].to_i,
              detail: {
                lat: vrp[:points].find{ |pt| pt[:location][:id] == point[:point_id] }[:location][:lat],
                lon: vrp[:points].find{ |pt| pt[:location][:id] == point[:point_id] }[:location][:lon],
                skills: services_data[point[:id]][:skills],
                setup_duration: point[:considered_setup_duration],
                duration: service_in_vrp[:activity][:duration],
                timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].select{ |t| t[:day_index] == day % 7 }.collect{ |tw| {start: tw[:start], end: tw[:end] } } : [],
                quantities: service_in_vrp[:quantities] ? service_in_vrp[:quantities].collect{ |qte| { unit: qte[:unit], value: qte[:value] } } : nil
              }
            }
            missions_list << "#{point[:id]}_#{point[:number_in_sequence]}_#{service_in_vrp[:visits_number]}"
          }

          if route[:vehicle][:end_point_id]
            computed_activities << {
              point_id: route[:vehicle][:end_point_id],
              detail: {
                lat: vrp[:points].find{ |point| point[:id] == route[:vehicle][:end_point_id] }[:location][:lat],
                lon: vrp[:points].find{ |point| point[:id] == route[:vehicle][:end_point_id] }[:location][:lon],
                quantities: []
              }
            }
          end

          routes << {
            vehicle: {
              id: route[:vehicle][:vehicle_id]
              },
            mission_ids: missions_list
          }

          solution << {
            vehicle_id: route[:vehicle][:vehicle_id],
            activities: computed_activities,
            total_travel_time: @travel_time
          }
        }
      }

      @candidate_service_ids.each{ |point|
        service_in_vrp = vrp.services.find{ |service| service[:id] == point }
        (1..service_in_vrp[:visits_number]).each{ |index|
          unassigned << {
            service_id: "#{point}_#{index}_#{service_in_vrp[:visits_number]}",
            point_id: service_in_vrp[:activity][:point_id],
            detail: {
              lat: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lat],
              lon: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lon],
              setup_duration: service_in_vrp[:activity][:setup_duration],
              duration: service_in_vrp[:activity][:duration],
              timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].collect{ |tw| {start: tw[:start], end: tw[:end] } }.sort_by{ |t| t[:start] } : [],
              quantities: service_in_vrp[:quantities] ? service_in_vrp[:quantities].collect{ |qte| { id: qte[:id], unit: qte[:unit], value: qte[:value] } } : nil
            },
            reason: 'Heuristic could not affect this service before all vehicles are full'
          }
        }
      }

      @uninserted.keys.each{ |service|
        s = @uninserted[service][:original_service]
        service_in_vrp = vrp.services.find{ |current_service| current_service[:id] == s }
        unassigned << {
          service_id: service,
          point_id: service_in_vrp[:activity][:point_id],
          detail: {
            lat: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lat],
            lon: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lon],
            setup_duration: service_in_vrp[:activity][:setup_duration],
            duration: service_in_vrp[:activity][:duration],
            timewindows: service_in_vrp[:activity][:timewindows] ? service_in_vrp[:activity][:timewindows].collect{ |tw| {start: tw[:start], end: tw[:end] } }.sort_by{ |t| t[:start] } : [],
            quantities: service_in_vrp[:quantities] ? service_in_vrp[:quantities].collect{ |qte| { id: qte[:id], unit: qte[:unit], value: qte[:value] } } : nil
          },
          reason: @uninserted[service][:reason]
        }
      }

      # providing solution in right form
      vrp[:preprocessing_heuristic_result] = {
        cost: @cost,
        solvers: ["heuristic"],
        iterations: 0,
        routes: solution,
        unassigned: unassigned,
        elapsed: Time.now - starting_time
      }

      routes
    end
  end
end
