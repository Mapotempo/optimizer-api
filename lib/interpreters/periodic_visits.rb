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

    def self.initialize
      @periods = []
      @equivalent_vehicles = {}
      @planning = {}
      @indices = {}
      @order = []
      @candidate_service_ids = []
      @temporary_planning = {}
      @services_of_period = {}
      @problem_vehicles = {}
      @candidate_routes = {}
      @candidate_vehicles = []
      @unworkable_days = []
      @vehicle_day_completed = {}
      @limit = nil
      @uninserted = {}
      @min_nb_scheduled_in_one_day = nil
      @cost = 0
      @travel_time = 0
      @same_point_day = false
      @allow_vehicle_change = false
    end

    def self.expand(vrp)
      if vrp.schedule_range_indices || vrp.schedule_range_date

        epoch = Date.new(1970,1,1)
        @real_schedule_start = vrp.schedule_range_indices ? vrp.schedule_range_indices[:start] : (vrp.schedule_range_date[:start].to_date - epoch).to_i
        real_schedule_end = vrp.schedule_range_indices ? vrp.schedule_range_indices[:end] : (vrp.schedule_range_date[:end].to_date - epoch).to_i
        @shift = vrp.schedule_range_indices ? @real_schedule_start : vrp.schedule_range_date[:start].to_date.cwday - 1
        @schedule_end = real_schedule_end - @real_schedule_start
        @schedule_start = 0
        @allow_vehicle_change = vrp.schedule_allow_vehicle_change

        unfeasible_services = Interpreters::PeriodicVisits.detect_planning_data_unconsistency(vrp, {})
        vrp.services.delete_if{ |service| unfeasible_services.key?(service.id)}

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
          vrp.routes = compute_initial_solution(vrp)
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

        vrp[:rejected_by_periodic] = unfeasible_services

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

    def self.detect_planning_data_unconsistency(vrp, unfeasible)
      if vrp.schedule_range_date || vrp.schedule_range_indices
        vrp.services.each{ |service|
          if service[:visits_number] > 0
            if service[:minimum_lapse] && @schedule_end - (service[:visits_number] - 1) * service[:minimum_lapse] < 0
              if !(unfeasible.key?(service.id))
                unfeasible[service.id] = { reason: "Unconsistency with visits_number, minimum_lapse and number of days in schedule." }
              end
            end
          end
        }
      end

      unfeasible
    end

    def self.generate_relations(vrp)
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

    def self.generate_services(vrp)
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

    def self.generate_shipments(vrp)
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

    def self.generate_vehicles(vrp)
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

    def self.check_with_vroom(vrp, route, service, residual_time, residual_time_for_vehicle)
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

    def self.generate_routes(vrp)
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

    def self.generate_rests(vehicle, day_index, rests_durations)
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

    def self.associate_skills(new_vehicle, vehicle_day_index)
      if new_vehicle.skills.empty?
        new_vehicle.skills = [@periods.collect{ |period| "#{(vehicle_day_index * period / (@schedule_end + 1)).to_i + 1}_f_#{period}" }]
      else
        new_vehicle.skills.collect!{ |alternative_skill|
          alternative_skill + @periods.collect{ |period| "#{(vehicle_day_index * period / (@schedule_end + 1)).to_i + 1}_f_#{period}" }
        }
      end
    end

    def self.compute_days_interval(vrp)
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

    def self.save_relations(vrp, relation_type)
      relations_to_save = vrp.relations.select{ |r| r.type == relation_type }.collect{ |r|
        {
          type: r.type,
          linked_vehicle_ids: r.linked_vehicle_ids,
          lapse: r.lapse,
          periodicity: r.periodicity
        }
      }
    end

    def self.get_all_vehicles_in_relation(relations)
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

    def self.generate_relations_on_periodic_vehicles(vrp, list)
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

    def self.solve_tsp(vrp)
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
          id: vrp[:vehicles][0][:id],
          start_point_id: vrp[:vehicles][0][:start_point_id],
          matrix_id: vrp[:vehicles][0][:matrix_id]
        }],
        services: vrp.services.collect{ |s|
          {
            id: s[:id],
            activity: {
              point_id: s[:activity][:point_id],
              duration: s[:activity][:duration]
            }
          }
        }
      }
      tsp = Models::Vrp.create(problem)
      progress = 0
      result = vroom.solve(tsp){ |avancement, total|
        progress += 1
      }
      @order = result[:routes][0][:activities].collect{ |stop|
        (stop[:service_id] ? stop[:service_id] : (stop[:shipment_id] ? stop[:shipment_id] : stop[:point_id]))
      }
    end

    def self.compute_positions(vehicle, day)
      route = @candidate_routes[vehicle][day]
      positions = []
      last_inserted = 0

      route[:current_route].each{ |point_seen|
        real_position = @order.index(point_seen[:id])
        positions << (last_inserted > -1 && real_position >= last_inserted ? @order.index(point_seen[:id]) : -1 )
        last_inserted = positions.last
      }

      @candidate_routes[vehicle][day][:positions_in_order] = positions
    end

    def self.insert_point_in_route(current_route, point_to_add)
      current_route.insert(point_to_add[:position], {
        id: point_to_add[:id],
        point_id: point_to_add[:point],
        start: point_to_add[:start],
        end: point_to_add[:end],
        max_shift: point_to_add[:potential_shift],
        number_in_sequence: 1
      })

      if point_to_add[:position] < current_route.size - 1
        current_route[point_to_add[:position]+1][:start] = point_to_add[:next_start_time]
        current_route[point_to_add[:position]+1][:end] = point_to_add[:next_final_time]
        current_route[point_to_add[:position]+1][:max_shift] = current_route[point_to_add[:position]+1][:max_shift] ? current_route[point_to_add[:position]+1][:max_shift] - point_to_add[:shift] : nil
        (point_to_add[:position]+2..current_route.size-1).each{ |point|
          current_route[point][:start] += point_to_add[:shift]
          current_route[point][:end] += point_to_add[:shift]
          current_route[point][:max_shift] = current_route[point][:max_shift] ? current_route[point][:max_shift] - point_to_add[:shift] : nil
        }
      end

      current_route.each_with_index{ |service, position|
        service[:max_shift] = (position..current_route.size-1).collect{ |other_position| current_route[other_position][:max_shift] }.compact.min
      }
    end

    def self.fill_day_in_planning(vehicle, route_data, services)
      day = route_data[:global_day_index]
      current_route = route_data[:current_route]
      positions_in_order = route_data[:positions_in_order]
      service_to_insert = true
      temporary_excluded_services = []

      while service_to_insert
        insertion_costs =  compute_insertion_costs(vehicle, day, current_route, positions_in_order, services, route_data, temporary_excluded_services)
        if !insertion_costs.empty?
          # there are services we can add
          point_to_add = insertion_costs.sort_by{ |s| s[:additional_route_time]/services[s[:id]][:nb_visits]**2 }[0] # au carré?

          # are we obliged to assign this service today ?
          # remaining_days = @candidate_routes[vehicle].keys
          # enough_days = true
          # heuristic_period = services[point_to_add[:id]][:heuristic_period]
          # if heuristic_period && heuristic_period > 0
          #   remaining_days.delete_if{ |current_day| current_day > (@schedule_end/(@schedule_end/heuristic_period).floor).ceil }
          #   enough_days = (@min_nb_scheduled_in_one_day.nil? || remaining_days.size * @min_nb_scheduled_in_one_day >= @services_of_period[heuristic_period].size)
          # end

          # if enough_days && insertion_costs.any?{ |point| point[:additional_route_time] < @limit } &&
          #   (point_to_add[:position] > 0 && point_to_add[:position] < current_route.size && point_to_add[:additional_route_time] > @limit ||
          #   point_to_add[:position] == 0 && !current_route.empty? && matrix(route_data, point_to_add[:id], current_route[0][:id]) > @limit ||
          #   point_to_add[:position] == current_route.size && !current_route.empty? && matrix(route_data, current_route.last[:id], point_to_add[:id]) > @limit )
          #   # the service is far, there are other possible days to assign it and we potentially will be able to assign another service with a lower period instead

          #   puts "#{point_to_add[:id]} trop loin"
          #   temporary_excluded_services << point_to_add[:id]
          # else
            best_index = find_best_index(current_route, services, point_to_add[:id], 0, route_data)
            insert_point_in_route(current_route, best_index)

            @candidate_service_ids.delete(point_to_add[:id])
            services[point_to_add[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
            positions_in_order.insert(point_to_add[:position], point_to_add[:position_in_order])

            if !@common_day[services[point_to_add[:id]][:point_id]] && @same_point_day
              @common_day[services[point_to_add[:id]][:point_id]] = day%7
              @candidate_service_ids.select{ |id| services[id][:point_id] == services[point_to_add[:id]][:point_id] }.each{ |id|
                insertion_costs = compute_insertion_costs(vehicle, day, current_route, positions_in_order, services, route_data, temporary_excluded_services)
                point = insertion_costs.find{ |service| service[:id] == id }
                if point
                  best_index = find_best_index(current_route, services, point[:id], 0, route_data)
                  insert_point_in_route(current_route, best_index)
                  @candidate_service_ids.delete(point[:id])
                  services[point[:id]][:capacity].each{ |need, qty| route_data[:capacity_left][need] -= qty }
                  positions_in_order.insert(point[:position], point[:position_in_order])
                end
              }
            end

            # if heuristic_period
            #   @services_of_period[heuristic_period].delete(point_to_add[:id])
            # end
          # end

        else
          service_to_insert = false
          @vehicle_day_completed[vehicle][day] = true
          if current_route.size > 0
            @travel_time += route_data[:start_point_id] ? matrix( route_data, route_data[:start_point_id], current_route.first[:id] ) : 0
            @travel_time += (0..current_route.size-2).collect{ |position| matrix(route_data, current_route[position][:id], current_route[position+1][:id]) }.sum
            @travel_time += route_data[:end_point_id] ? matrix( route_data, current_route.last[:id], route_data[:start_point_id] ) : 0
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

    def self.find_timewindows(insertion_index, previous_service, previous_service_end, inserted_service, inserted_service_info, route_data)
      list = []
      route_time = (insertion_index == 0 ? matrix(route_data, route_data[:start_point_id], inserted_service) : matrix(route_data, previous_service, inserted_service))

      if inserted_service_info[:tw].nil? || inserted_service_info[:tw].empty?
        start = insertion_index == 0 ? route_data[:tw_start] : previous_service_end
        final = start + route_time + inserted_service_info[:duration]
        list << {
          start_time: start,
          final_time: final,
          end_tw: nil,
          max_shift: nil
        }
      else
        inserted_service_info[:tw].each{ |tw|
          start_time = (insertion_index == 0 ? [route_data[:tw_start], tw[:start] - route_time].max : [previous_service_end, tw[:start] - route_time].max)
          final_time = start_time + route_time + inserted_service_info[:duration]

          if start_time <= tw[:end] # check days available too
            list << {
              start_time: start_time,
              final_time: final_time,
              end_tw: tw[:end],
              max_shift: tw[:end] - start_time
            }
          end
        }
      end

      # will only contain values associated to one tw, that is : only one start,final and max_shift will be returned
      list
    end

    def self.compute_shift(dist_to_next, inserted_final_time, comparative_time, next_service_info, position_is_at_the_end)
      if !position_is_at_the_end
        next_start, next_end = compute_tw_for_next(inserted_final_time, next_service_info, dist_to_next)
        [next_start, next_end, next_end - comparative_time]
      else
        [nil, nil, inserted_final_time - comparative_time]
      end
    end

    def self.find_best_index(route, services, service, current_indice, route_data)
      possibles = []
      service_duration = services[service][:duration]

      if route.empty?
        # this case is only usefull if we always look for best position instead of looking at the order
        tw = find_timewindows(0, nil, nil, service, services[service], route_data)[0]
        if tw[:final_time] + matrix(route_data, service, route_data[:end_point_id]) <= route_data[:tw_end]
          possibles << {
            id: service,
            point: services[service][:point_id],
            shift: 0,
            start: tw[:start_time],
            end: tw[:final_time],
            position: 0,
            position_in_order: -1,
            next_start_time: nil,
            next_final_time: nil,
            potential_shift: (tw[:max_shift] ? tw[:max_shift] - matrix(route_data, route_data[:start_point_id], service) : nil),
            additional_route_time: matrix(route_data, route_data[:start_point_id], service) + matrix(route_data, service, route_data[:end_point_id]),
            dist_from_current_route: (0..route.size-1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min
          }
        end
      else
        (current_indice..route.size).each{ |position|
          previous_service = (position == 0 ? route_data[:start_point_id] : route[position-1][:id])
          previous_service_end = (position == 0 ? nil : route[position-1][:end])
          list = find_timewindows(position, previous_service, previous_service_end, service, services[service], route_data)

          list.each{ |current_tw|
            start_time = current_tw[:start_time]
            arrival_time = start_time + matrix(route_data, previous_service, service)
            final_time = current_tw[:final_time]
            next_end = nil
            if position < route.size
              next_start, next_end, shift = compute_shift(matrix(route_data, service, route[position][:id]), final_time, route[position][:end], services[route[position][:id]], false)
            elsif position == route.size
              next_start, next_end, shift = compute_shift(nil, final_time, route.last[:end], nil, true)
              shift = (final_time + matrix(route_data, service, route_data[:end_point_id])) - (route.last[:end] + matrix(route_data, route.last[:id], route_data[:end_point_id]))
            end

            time_back_to_depot = (position == route.size ? final_time + matrix(route_data, service, route_data[:end_point_id]) : route.last[:end] + matrix(route_data, route.last[:id], route_data[:end_point_id]) + shift )
            acceptable_shift = (position < route.size ? route[position][:max_shift].nil? || shift < route[position][:max_shift] : true)
            acceptable_shift_for_itself = (current_tw[:end_tw] ? arrival_time <= current_tw[:end_tw] : true)
            if acceptable_shift && time_back_to_depot <= route_data[:tw_end] && acceptable_shift_for_itself
              possibles << {
                id: service,
                point: services[service][:point_id],
                shift: shift,
                start: start_time,
                end: final_time,
                position: position,
                position_in_order: -1, # to not consider this service, which does not respect order, to compute first_bigger_position
                next_start_time: next_start,
                next_final_time: next_end,
                potential_shift: (current_tw[:max_shift] ? current_tw[:max_shift] - matrix(route_data, previous_service, service) : nil),
                additional_route_time: [0, shift - services[service][:duration]].max,
                dist_from_current_route: (0..route.size-1).collect{ |current_service| matrix(route_data, service, route[current_service][:id]) }.min,
                last_service_end: (position == route.size ? final_time : route.last[:end] + shift)
              }
            end
          }
        }
      end

      possibles.sort_by!{ |possible_position| possible_position[:last_service_end] }[0]
    end

    def self.compute_tw_for_next(inserted_final_time, this_service_info, dist_from_inserted)
      sooner_start = (this_service_info[:tw] && !this_service_info[:tw].empty? ? this_service_info[:tw][0][:start]-dist_from_inserted : inserted_final_time)
      new_start = [sooner_start, inserted_final_time].max
      new_end = new_start + dist_from_inserted + this_service_info[:duration]

      [new_start, new_end]
    end

    def self.matrix(route_data, start, arrival)
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

    def self.compute_insertion_costs(vehicle, day, route, positions_in_order, services, route_data, excluded)
      insertion_costs = []

      @candidate_service_ids.select{ |service| !excluded.include?(service) &&
                    services[service][:capacity].all?{ |need, quantity| quantity <= route_data[:capacity_left][need] } &&
                    !services[service][:unavailable_days].include?(day) &&
                    !@same_point_day || @common_day[services[service][:point_id]].nil? || (@common_day[services[service][:point_id]]) == day%7 }.each{ |service_id|
        period = services[service_id][:heuristic_period]
        n_visits = services[service_id][:nb_visits]
        latest_authorized_day = @schedule_end - (period || 0) * (n_visits - 1)
        # Verify if the potential nexts visits days are still available
        if period.nil? || day <= latest_authorized_day && (day+period..@schedule_end).step(period).find{ |current_day| @vehicle_day_completed[vehicle][current_day] }.nil?
          s_position_in_order = @order.index(service_id)
          first_bigger_position_in_sol = positions_in_order.select{ |pos| pos > s_position_in_order }.min
          insertion_index = positions_in_order.index(first_bigger_position_in_sol).nil? ? route.size : positions_in_order.index(first_bigger_position_in_sol)

          previous_service = insertion_index - 1 if insertion_index > 0
          previous_service_id = (previous_service ? route[previous_service][:id] : nil )
          previous_service_end = (previous_service ? route[previous_service][:end] : nil)
          next_service = insertion_index if !route.empty? && insertion_index < route.size
          next_service_id = (next_service.nil? ? nil : route[next_service][:id])

          potential_tw = find_timewindows(insertion_index, previous_service_id, previous_service_end, service_id, services[service_id], route_data)

          if !potential_tw.empty?
            start_time = potential_tw[0][:start_time]
            arrival_time = start_time + (previous_service_id ? matrix(route_data, previous_service_id, service_id) : matrix(route_data, route_data[:start_point_id], service_id))
            final_time = potential_tw[0][:final_time]
            max_shift = potential_tw[0][:max_shift]
            if max_shift
              max_shift -= (arrival_time - start_time)
            end

            # if we insert at this postion, what would be the planning shift :
            shift = 0
            if next_service
              dist_to_next = matrix(route_data, service_id, next_service_id)
              next_start, next_end = compute_tw_for_next(final_time, services[route[next_service][:id]], dist_to_next)
              shift = next_end - route[next_service][:end]
            elsif insertion_index == route.size && !route.empty?
              shift = final_time - route.last[:end]
              # more consistent but worse results : (provides same result now)
              # shift = (final_time + matrix(service_id, @end_point)) - (route.last[:end] + matrix(route.last[:id], @end_point))
            elsif route.empty?
              shift = matrix(route_data, route_data[:start_point_id], service_id) + matrix(route_data, service_id, route_data[:end_point_id]) + services[service_id][:duration]
            end
            acceptable_shift = (next_service ? route[next_service][:max_shift].nil? || shift < route[next_service][:max_shift] : true)
            acceptable_shift_for_itself = (potential_tw[0][:end_tw] ? arrival_time <= potential_tw[0][:end_tw] : true)

            # do we still have time to go back to depot ?
            time_back_to_depot = (insertion_index == route.size ? final_time + matrix(route_data, service_id, route_data[:end_point_id]) : route.last[:end] + matrix(route_data, route.last[:id], route_data[:end_point_id]) + shift)
            if acceptable_shift && time_back_to_depot <= route_data[:tw_end] && acceptable_shift_for_itself
              # we can add this service at this position so add in possible services list
              insertion_costs << {
                id: service_id,
                point: services[service_id][:point_id],
                shift: shift,
                start: start_time,
                end: final_time,
                position: insertion_index,
                position_in_order: s_position_in_order,
                next_start_time: next_start,
                next_final_time: next_end,
                potential_shift: max_shift,
                additional_route_time: [0 , shift - services[service_id][:duration]].max,
                dist_from_current_route: (0..route.size-1).collect{ |current_service| matrix(route_data, service_id, route[current_service][:id]) }.min
              }
            else
              # we can try to find another index
              if route.size > 0
                other_indices = find_best_index(route, services, service_id, insertion_index, route_data)

                if !other_indices.nil?
                  insertion_costs << other_indices
                end
              end
            end
          end
        end
      }

      insertion_costs
    end

    def self.recompute_times(vehicle, day, services, route_data)
      if !route_data[:current_route].empty?
        first_service = route_data[:current_route].first[:id]
        times = find_timewindows(0, nil, nil, first_service, services[first_service], route_data)[0]

        services_list = []
        services_list << {
          id: first_service,
          point_id: services[first_service][:point_id],
          start: times[:start_time],
          end: times[:final_time],
          max_shift: (times[:max_shift] ? times[:max_shift] - matrix(route_data, route_data[:start_point_id], first_service) : nil), # start point is now contained in route_data
          number_in_sequence: route_data[:current_route][0][:number_in_sequence]
        }

        previous_service = route_data[:current_route][0][:id]
        (1..route_data[:current_route].size - 1).each{ |position|
          service = route_data[:current_route][position][:id]
          route_time = matrix(route_data, previous_service, service)
          start_time = (services[service][:tw].nil? || services[service][:tw].empty? ? services_list[position-1][:end] : [services_list[position-1][:end], services[service][:tw][0][:start] - route_time].max)
          arrival_time = start_time + route_time
          final_time = start_time + route_time + services[service][:duration]

          if final_time < route_data[:tw_end]
            services_list << {
              id: service,
              point_id: services[service][:point_id],
              start: start_time,
              end: final_time,
              max_shift: (services[service][:tw].nil? || services[service][:tw].empty? ? nil : services[service][:tw][0][:end] - arrival_time),
              number_in_sequence: route_data[:current_route][position][:number_in_sequence]
            }
            previous_service = service
          else
            @uninserted[service] = {
              original_service: service
            }
          end
        }

        route_data[:capacity_left].keys.each{ |unit| route_data[:capacity_left][unit] = route_data[:capacity][unit] }
        services_list.each_with_index{ |service, position|
          service[:max_shift] = (position..services_list.size-1).collect{ |other_position| services_list[other_position][:max_shift] }.compact.min
          services[service[:id]][:capacity].each{ |unit,qty| route_data[:capacity_left][unit] -= qty }
        }

        route_data[:current_route] = services_list
      end
    end

    def self.readjust_times(route, all_services)
      if (route.collect{ |s| s[:id] } & all_services.collect{ |s| s[:id] }).size == route.size
        route.collect{ |s| s[:id] }.each_with_index{ |service, i|
            service_planned = all_services.find{ |s| s[:id] == service }
            route[i][:start] = service_planned[:start]
            route[i][:end] = service_planned[:end]
            route[i][:max_shift] = service_planned[:max_shift]
          }
          route.sort_by!{ |s| s[:start] }
      end
    end

    def self.try_on_different_vehicle(day, service, all_services)
      experiment = Marshal::load(Marshal.dump(@candidate_routes[@candidate_vehicles[1]][day]))
      experiment[:current_route] << Marshal::load(Marshal.dump(service))
      readjust_times(experiment[:current_route], all_services)
      recompute_times(vehicle, day, services, experiment)
      if experiment[:current_route].last[:end] + matrix(@candidate_routes[@candidate_vehicles[1]][day], experiment[:current_route].last[:id], @candidate_routes[@candidate_vehicles[1]][day][:end_point_id] ) < @candidate_routes[@candidate_vehicles[1]][day][:tw_end]
        @candidate_routes[@candidate_vehicles[1]][day][:current_route] = experiment[:current_route]
        @candidate_routes[@candidate_vehicles[1]][day][:current_route].find{ |act| act[:id] == service[:id] }[:number_in_sequence] += nb_added
        true
      else
        false
      end
    end

    def self.adjust_candidate_routes(vehicle, day_finished, services, services_to_add, all_services, days_available)
      days_filled = []
      services_to_add.each{ |service|
        peri = services[service[:id]][:heuristic_period]
        if peri && peri > 0
          nb_added = 0
          (day_finished + peri..@schedule_end).step(peri).each{ |day|
            if days_available.include?(day)
              nb_added += 1
              inserted = false
              if @candidate_routes[vehicle].keys.include?(day) && !@vehicle_day_completed[vehicle][day] && nb_added < services[service[:id]][:nb_visits]
                days_filled << day

                experiment = Marshal::load(Marshal.dump(@candidate_routes[vehicle][day]))
                experiment[:current_route] << Marshal::load(Marshal.dump(service))
                readjust_times(experiment[:current_route], all_services)
                recompute_times(vehicle, day, services, experiment)
                if experiment[:current_route].last[:end] + matrix(@candidate_routes[vehicle][day], experiment[:current_route].last[:id], @candidate_routes[vehicle][day][:end_point_id] ) < @candidate_routes[vehicle][day][:tw_end]
                  found_service = experiment[:current_route].find{ |act| act[:id] == service[:id] }
                  if found_service
                    inserted = true
                    @candidate_routes[vehicle][day][:current_route] = experiment[:current_route]
                    @candidate_routes[vehicle][day][:current_route].find{ |act| act[:id] == service[:id] }[:number_in_sequence] += nb_added
                  end
                elsif @candidate_vehicles.size > 2 && @allow_vehicle_change
                  inserted = try_on_different_vehicle(day, service, all_services)
                end
              elsif @vehicle_day_completed[vehicle][day] && @allow_vehicle_change
                inserted = try_on_different_vehicle(day, service, all_services)
              end

              if !inserted
                @uninserted["#{service[:id]}_#{service[:number_in_sequence] + nb_added}/#{services[service[:id]][:nb_visits]}"] = {
                  original_service: service[:id]
                }
              end
            end
          }
          if nb_added + 1 < services[service[:id]][:nb_visits]
            first_missing = nb_added+2
            (first_missing..services[service[:id]][:nb_visits]).each{ |missing_s|
              @uninserted["#{service[:id]}_#{missing_s}/#{services[service[:id]][:nb_visits]}"] = {
                original_service: service[:id]
              }
            }
          end
        end
      }

      days_filled.each{ |d|
        compute_positions(vehicle, d)
      }
    end

    def self.rebalance_days(services, route_data)
      something_permuted = false

      # rebalance days scheduled
      # when removing one service, adjust capacity of the route
      few_filled_days = @planning.select{ |day_key, day_plan| day_plan[:services].size <= 3 }.to_a.sort_by{ |day_key, day_plan| @planning[day_key][:services].size }
      max_per_day = @planning.collect{ |day_key, day_plan| day_plan[:services].size }.max
      very_filled_days = @planning.select{ |day_key, day_plan| day_plan[:services].size >= max_per_day - 3 }.to_a.sort_by{ |day_key, day_plan| @planning[day_key][:services].size }

      few_filled_days.each{ |day, plan|
        permutation_values = []
        # find best service to insert
        very_filled_days.each{ |overloaded_day, overloaded_plan|
          @planning[overloaded_day][:services].each{ |service|
            if services[service[:id]][:heuristic_period] == 0
              permutation_values << {
                day: overloaded_day,
                route_id: route_data[:vehicle_id],
                value: find_best_index(@planning[day][:services], services, service[:id], 0, route_data)
              }
            end
          }
        }
        permutation_to_apply = permutation_values.sort_by!{ |possibility| possibility[:additional_route_time] }[0]
        if !permutation_to_apply.nil? && !permutation_to_apply[:value].nil? && permutation_to_apply[:value][:additional_route_time] < @limit
          something_permuted = true
          insert_point_in_route(@planning[day][:services], permutation_to_apply[:value])
          @planning[permutation_to_apply[:day]][:services].delete_if{ |service| service[:id] == permutation_to_apply[:value][:id] }
        end
      }

      something_permuted
    end

    def self.compute_capacities(quantities, vehicle)
      capacities = {}

      if quantities
        quantities.each{ |unit|
          if vehicle
            if capacities[unit[:unit][:id]]
              capacities[unit[:unit][:id]] += unit[:limit].to_f
            else
              capacities[unit[:unit][:id]] = unit[:limit].to_f
            end
          else
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

    def self.compute_initial_solution(vrp)
      starting_time = Time.now
      puts "starting at #{starting_time}"

      @limit = 1700
      @same_point_day = vrp.resolution_same_point_day
      @common_day = {}

      # Solve TSP - Build a large Tour to define an arbitrary insertion order
      solve_tsp(vrp)

      services_data = {}
      has_sequence_timewindows = vrp[:vehicles][0][:timewindow].nil?

      # Collect services data
      units = vrp.units.collect{ |unit| unit[:id] }
      vrp.services.each{ |service|
        epoch = Date.new(1970,1,1)
        service[:unavailable_visit_day_indices] += service[:unavailable_visit_day_date].to_a.collect{ |unavailable_date|
          (unavailable_date.to_date - epoch).to_i - @real_schedule_start if (unavailable_date.to_date - epoch).to_i >= @real_schedule_start
        }.compact
        has_every_day_index = has_sequence_timewindows && !vrp.vehicles[0].sequence_timewindows.empty? && !((vrp.vehicles[0].sequence_timewindows.collect{ |tw| tw.day_index }.uniq & (0..6).to_a).size == 7)
        services_data[service.id] = {
          capacity: compute_capacities(service[:quantities], false),
          duration: service[:activity][:duration] + service[:activity][:setup_duration],
          heuristic_period: (service[:visits_number] == 1 ? nil : (has_sequence_timewindows && !has_every_day_index ? (service[:minimum_lapse].to_f/7).to_i * 7 : (service[:minimum_lapse].nil? ? 1 : service[:minimum_lapse].floor ))),
          nb_visits: service[:visits_number],
          point_id: service[:activity][:point][:location][:id],
          tw: service[:activity][:timewindows],
          unavailable_days: service[:unavailable_visit_day_indices]
        }

        @candidate_service_ids << service.id

        @indices[service[:id]] = vrp[:points].find{ |pt| pt[:id] == service[:activity][:point][:id] }[:matrix_index]
      }

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
        original_vehicle_id = vehicle[:id].split("_").slice(0, vehicle[:id].split("_").size-1).join("_")
        capacity = compute_capacities(vehicle[:capacities], true)
        vrp.units.select{ |unit| !capacity.keys.include?(unit[:id]) }.each{ |unit| capacity[unit[:id]] = 0.0 }
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
          capacity_left: capacity,
          positions_in_order: []
        }
        @vehicle_day_completed[original_vehicle_id][vehicle[:global_day_index]] = false
      }

      # if vrp[:vehicles][0][:cost_time_multiplier] > 0
      #   @matrix = vrp[:matrices][0][:time]
      # else
      #   @matrix = vrp[:matrices][0][:distance]
      # end

      while !@candidate_vehicles.empty?
        current_vehicle = @candidate_vehicles[0]
        days_available = @candidate_routes[current_vehicle].keys.sort_by!{ |day|
          [@candidate_routes[current_vehicle][day][:current_route].size, @candidate_routes[current_vehicle][day][:tw_end] - @candidate_routes[current_vehicle][day][:tw_start]]
        }
        current_day = days_available[0]
        recompute_times(current_vehicle, current_day, services_data, @candidate_routes[current_vehicle][current_day])

        while @candidate_service_ids.size > 0 && !current_day.nil?
          initial_services = @candidate_routes[current_vehicle][current_day][:current_route].collect{ |s| s[:id] }
          fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day], services_data)
          new_services = @planning[current_vehicle][current_day][:services].select{ |s| !initial_services.include?(s[:id]) }
          days_available.delete(current_day)
          @candidate_routes[current_vehicle].delete(current_day)
          adjust_candidate_routes(current_vehicle, current_day, services_data, new_services, @planning[current_vehicle][current_day][:services], days_available)

          while @candidate_routes[current_vehicle].any?{ |day, day_data| day_data[:current_route].size > 0 }
            current_day = @candidate_routes[current_vehicle].max_by{ |day, day_data| day_data[:current_route].size }.first
            # assign each service as soon as possible
            recompute_times(current_vehicle, current_day, services_data, @candidate_routes[current_vehicle][current_day])

            initial_services = @candidate_routes[current_vehicle][current_day][:current_route].collect{ |s| s[:id] }
            fill_day_in_planning(current_vehicle, @candidate_routes[current_vehicle][current_day], services_data)
            new_services = @planning[current_vehicle][current_day][:services].select{ |s| !initial_services.include?(s[:id]) }
            adjust_candidate_routes(current_vehicle, current_day, services_data, new_services, @planning[current_vehicle][current_day][:services], days_available)

            days_available.delete(current_day)
            @candidate_routes[current_vehicle].delete(current_day)
          end

          current_day = days_available[0]
        end

        # we have filled all days for current vehicle
        @candidate_vehicles.delete(current_vehicle)
      end

      # post-processing
      # try_permutation = true
      # while
      #   try_permutation = rebalance_days(services_data, @planning)
      # end

      really_uninserted = 0
      uninserted = @candidate_service_ids.size
      @candidate_service_ids.each{ |service_id|
        really_uninserted += services_data[service_id][:nb_visits]
      }
      puts "uninserted : #{really_uninserted + @uninserted.size} (#{uninserted} missions)"

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

          route[:services].each{ |point|
            service_in_vrp = vrp.services.find{ |s| s[:id] == point[:id] }
            computed_activities << {
              service_id: "#{point[:id]}_#{point[:number_in_sequence]}/#{service_in_vrp[:visits_number]}",
              point_id: service_in_vrp[:activity][:point_id],
              begin_time: point[:end].to_i - service_in_vrp[:activity][:duration],
              departure_time: point[:end].to_i,
              detail: {
                lat: vrp[:points].find{ |pt| pt[:location][:id] == point[:point_id] }[:location][:lat],
                lon: vrp[:points].find{ |pt| pt[:location][:id] == point[:point_id] }[:location][:lon],
                skills: services_data[point[:id]][:skills],
                setup_duration: service_in_vrp[:activity][:setup_duration],
                duration: service_in_vrp[:activity][:duration],
                timewindows: service_in_vrp[:activity][:timewindows] && !service_in_vrp[:activity][:timewindows].empty? ? [{
                  start: service_in_vrp[:activity][:timewindows][0][:start],
                  end: service_in_vrp[:activity][:timewindows][0][:end],
                }] : nil,
                quantities: service_in_vrp[:quantities] ? service_in_vrp[:quantities].collect{ |qte| { unit: qte[:unit], value: qte[:value] } } : nil
              }
            }
            missions_list << "#{point[:id]}_#{point[:number_in_sequence]}/#{service_in_vrp[:visits_number]}"
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
        # puts "#{point} uninserted"
        service_in_vrp = vrp.services.find{ |service| service[:id] == point }
        (1..service_in_vrp[:visits_number]).each{ |index|
          unassigned << {
            service_id: "#{point}_#{index}/#{service_in_vrp[:visits_number]}",
            point_id: service_in_vrp[:activity][:point_id],
            detail: {
              lat: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lat],
              lon: vrp.points.find{ |point| point[:id] == service_in_vrp[:activity][:point_id] }[:location][:lon],
              setup_duration: service_in_vrp[:activity][:setup_duration],
              duration: service_in_vrp[:activity][:duration],
              timewindows: service_in_vrp[:activity][:timewindows] && !service_in_vrp[:activity][:timewindows].empty? ? [{
                start: service_in_vrp[:activity][:timewindows][0][:start],
                end: service_in_vrp[:activity][:timewindows][0][:start],
              }] : [],
              quantities: service_in_vrp[:quantities].collect{ |qte|
                {
                  id: qte[:id],
                  unit_id: qte[:unit_id],
                  value: qte[:value],
                  unit: qte[:unit]
                }
              }
            },
            reason: "unaffected by heuristic"
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
            timewindows: service_in_vrp[:activity][:timewindows] && !service_in_vrp[:activity][:timewindows].empty? ? [{
              start: service_in_vrp[:activity][:timewindows][0][:start],
              end: service_in_vrp[:activity][:timewindows][0][:start],
            }] : [],
            quantities: service_in_vrp[:quantities].collect{ |qte|
              {
                id: qte[:id],
                unit_id: qte[:unit_id],
                value: qte[:value],
                unit: qte[:unit]
              }
            }
          },
          reason: "unaffected by heuristic"
        }
      }

      puts "vehicle times respected?"
      @planning.each{ |vehicle, all_days_routes|
        all_days_routes.each{ |day, route|
          if route[:services].empty?
            # puts "day #{day} empty"
          else
            last_service = route[:services].last[:id]
            time_back_to_depot = route[:services].last[:end] + matrix(route[:vehicle], last_service, route[:vehicle][:end_point_id])
            if route[:services][0][:start] < route[:vehicle][:tw_start]
              puts "#{day} noooo start : #{route[:services][0]}"
            end
            if time_back_to_depot > route[:vehicle][:tw_end]
              puts "#{day} nooo end : #{vehicle} #{route[:services].last}"
            end
          end
        }
      }

      puts "services times respected?"
      @planning.each{ |vehicle, all_days_routes|
        all_days_routes.each{ |day, route|
          route[:services].each_with_index{ |s,i|
            if !services_data[s[:id]][:tw].nil? && !services_data[s[:id]][:tw].empty?
              time_to_arrive = ( i == 0 ? matrix(route[:vehicle], route[:vehicle][:start_point_id], s[:id]) : matrix( route[:vehicle], route[:services][i - 1][:id], s[:id] ))
              if s[:start] + time_to_arrive < services_data[s[:id]][:tw][0][:start]
                puts "#{day} noooo start : #{s}"
              end
              if s[:start] + time_to_arrive > services_data[s[:id]][:tw][0][:end]
                puts "#{day} noooo start overpasses end #{s}"
              end
            end
          }
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

      puts "ending at #{Time.now}"

      routes
    end
  end
end
