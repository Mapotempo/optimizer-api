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
require './lib/heuristics/periodic_heuristic.rb'

module Interpreters
  class PeriodicVisits
    def initialize(vrp)
      @periods = []
      @equivalent_vehicles = {}
      @epoch = Date.new(1970, 1, 1)

      if vrp.schedule?
        have_services_day_index = !vrp.services.empty? && vrp.services.any?{ |service| (service.activity ? [service.activity] : service.activities).any?{ |activity| activity.timewindows.any?(&:day_index) } }
        have_vehicles_day_index = vrp.vehicles.any?{ |vehicle| (vehicle.timewindow ? [vehicle.timewindow] : vehicle.sequence_timewindows ).any?(&:day_index) }
        have_rest_day_index = vrp.rests.any?{ |rest| rest.timewindows.any?(&:day_index) }
        @have_day_index = have_services_day_index || have_vehicles_day_index || have_rest_day_index

        @schedule_start = vrp.schedule_range_indices[:start]
        @schedule_end = vrp.schedule_range_indices[:end]

        compute_possible_days(vrp)
      end
    end

    def expand(vrp, job, &block)
      return vrp unless vrp.schedule?

      vehicles_linking_relations = save_vehicle_linking_relations(vrp)
      vrp.rests = []
      vrp.vehicles = generate_vehicles(vrp).sort{ |a, b|
        (a.global_day_index && b.global_day_index && a.global_day_index != b.global_day_index) ? a.global_day_index <=> b.global_day_index : a.id <=> b.id
      }

      if vrp.periodic_heuristic?
        periodic_heuristic = Wrappers::PeriodicHeuristic.new(vrp, job)
        vrp.routes = periodic_heuristic.compute_initial_solution(vrp, &block)
      end

      vrp.services = generate_services(vrp)
      vrp.relations = generate_relations(vrp)

      @periods.uniq!
      generate_relations_on_periodic_vehicles(vrp, vehicles_linking_relations)

      if vrp.preprocessing_first_solution_strategy.to_a.first != 'periodic' && vrp.services.any?{ |service| service.visits_number > 1 }
        vrp.routes = generate_routes(vrp)
      end

      vrp
    end

    def generate_timewindows(timewindows_set)
      return nil if timewindows_set.empty?

      timewindows_set.collect{ |timewindow|
        if @have_day_index
          first_day =
            if timewindow.day_index
              (@schedule_start..@schedule_end).find{ |day| day % 7 == timewindow.day_index }
            else
              @schedule_start
            end

          if first_day
            (first_day..@schedule_end).step(timewindow.day_index ? 7 : 1).collect{ |day_index|
              Models::Timewindow.create(start: timewindow.start + day_index * 86400,
                                        end: (timewindow.end || 86400) + day_index * 86400)
            }
          end
        else
          timewindow
        end
      }.flatten.sort_by(&:start).compact.uniq
    end

    def generate_relations(vrp)
      vrp.relations.flat_map{ |relation|
        unless relation.linked_ids.uniq{ |s_id| @expanded_services[s_id].size }.size <= 1
          raise "Cannot expand relations of #{relation.linked_ids} because they have different visits_number"
        end

        # keep the original relation if it is another type of relation or if it doesn't belong to an unexpanded service.
        next relation if relation.linked_services.empty? || @expanded_services[relation.linked_ids.first].empty?

        Array.new(@expanded_services[relation.linked_ids.first].size){ |visit_index|
          linked_ids = relation.linked_ids.collect{ |s_id| @expanded_services[s_id][visit_index].id }

          Models::Relation.create(
            type: relation.type, linked_ids: linked_ids, lapses: relation.lapses, periodicity: relation.periodicity
          )
        }
      }
    end

    def generate_relations_between_visits(vrp, mission)
      # TODO : need to uniformize generated relations whether mission has minimum AND maximum lapse or only one of them
      return unless mission.visits_number > 1

      if mission.minimum_lapse && mission.maximum_lapse
        (2..mission.visits_number).each{ |index|
          current_lapse = (index - 1) * mission.minimum_lapse.to_i
          vrp.relations << Models::Relation.create(
            type: :minimum_day_lapse,
            linked_ids: ["#{mission.id}_1_#{mission.visits_number}", "#{mission.id}_#{index}_#{mission.visits_number}"],
            lapses: [current_lapse]
          )
        }
        (2..mission.visits_number).each{ |index|
          current_lapse = (index - 1) * mission.maximum_lapse.to_i
          vrp.relations << Models::Relation.create(
            type: :maximum_day_lapse,
            linked_ids: ["#{mission.id}_1_#{mission.visits_number}", "#{mission.id}_#{index}_#{mission.visits_number}"],
            lapses: [current_lapse]
          )
        }
      elsif mission.minimum_lapse
        (2..mission.visits_number).each{ |index|
          current_lapse = mission.minimum_lapse.to_i
          vrp.relations << Models::Relation.create(
            type: :minimum_day_lapse,
            linked_ids: ["#{mission.id}_#{index - 1}_#{mission.visits_number}", "#{mission.id}_#{index}_#{mission.visits_number}"],
            lapses: [current_lapse]
          )
        }
      elsif mission.maximum_lapse
        (2..mission.visits_number).each{ |index|
          current_lapse = mission.maximum_lapse.to_i
          vrp.relations << Models::Relation.create(
            type: :maximum_day_lapse,
            linked_ids: ["#{mission.id}_#{index - 1}_#{mission.visits_number}", "#{mission.id}_#{index}_#{mission.visits_number}"],
            lapses: [current_lapse]
          )
        }
      end
    end

    def generate_services(vrp)
      @expanded_services = Hash.new{ |h, k| h[k] = [] }
      vrp.services.collect{ |service|
        # transform service data into periodic data
        (service.activity ? [service.activity] : service.activities).each{ |activity|
          activity.timewindows = generate_timewindows(activity.timewindows)
        }

        # generate one service per visit
        # TODO : create visit in model
        @periods << service.visits_number

        visits = (0..service.visits_number - 1).collect{ |visit_index|
          next if service.unavailable_visit_indices.include?(visit_index)

          new_service = duplicate_safe(
            service,
            id: "#{service.id}_#{visit_index + 1}_#{service.visits_number}",
            visits_number: 1,
            first_possible_days: [service.first_possible_days[visit_index]],
            last_possible_days: [service.last_possible_days[visit_index]]
          )
          new_service.skills += ["#{visit_index + 1}_f_#{service.visits_number}"] if !service.minimum_lapse && !service.maximum_lapse && service.visits_number > 1

          @expanded_services[service.id] << new_service

          new_service
        }.compact

        generate_relations_between_visits(vrp, service)

        visits
      }.flatten
    end

    def build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations)
      new_vehicle = duplicate_safe(
        vehicle,
        id: "#{vehicle.id}_#{vehicle_day_index}",
        global_day_index: vehicle_day_index,
        skills: associate_skills(vehicle, vehicle_day_index),
        rests: generate_rests(vehicle, vehicle_day_index, rests_durations),
        sequence_timewindows: [],
      )
      @equivalent_vehicles[vehicle.id] << new_vehicle.id
      vrp.rests += new_vehicle.rests
      vrp.services.select{ |service| service.sticky_vehicles.any?{ |sticky_vehicle| sticky_vehicle == vehicle } }.each{ |service|
        service.sticky_vehicles.insert(-1, new_vehicle)
      }
      new_vehicle
    end

    def generate_vehicles(vrp)
      rests_durations = Array.new(vrp.vehicles.size, 0)
      new_vehicles = vrp.vehicles.collect{ |vehicle|
        @equivalent_vehicles[vehicle.id] = []
        @equivalent_vehicles[vehicle.original_id] = []
        vehicles = (vrp.schedule_range_indices[:start]..vrp.schedule_range_indices[:end]).collect{ |vehicle_day_index|
          next if vehicle.unavailable_days.include?(vehicle_day_index)

          timewindows = [vehicle.timewindow || vehicle.sequence_timewindows].flatten
          if timewindows.empty?
            new_vehicle = build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations)
            new_vehicle
          else
            timewindows.select{ |timewindow| timewindow.day_index.nil? || timewindow.day_index == vehicle_day_index % 7 }.collect{ |associated_timewindow|
              new_vehicle = build_vehicle(vrp, vehicle, vehicle_day_index, rests_durations)
              new_vehicle.timewindow = Models::Timewindow.create(start: associated_timewindow.start || 0, end: associated_timewindow.end || 86400)
              if @have_day_index
                new_vehicle.timewindow.start += vehicle_day_index * 86400
                new_vehicle.timewindow.end += vehicle_day_index * 86400
              end
              new_vehicle
            }.compact
          end
        }.compact

        if vehicle.overall_duration
          new_relation = Models::Relation.create(
            type: :vehicle_group_duration,
            linked_vehicle_ids: @equivalent_vehicles[vehicle.original_id],
            lapses: [vehicle.overall_duration + rests_durations[index]]
          )
          vrp.relations << new_relation
        end

        vehicles
      }.flatten

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
      result = vroom.solve(vrp){ |_avancement, _total|
        progress += 1
      }
      travel_time = 0
      first = true
      result[:routes][0][:activities].each{ |a|
        first ? first = false : travel_time += (a[:detail][:setup_duration] ? a[:travel_time] + a[:detail][:duration] + a[:detail][:setup_duration] : a[:travel_time] + a[:detail][:duration])
      }

      time_back_to_depot = 0
      if !route[:vehicle][:end_point_id].nil?
        this_service_index = vrp.services.find{ |s| s.id == service.id }[:activity][:point][:matrix_index]
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
      vrp.relations.select{ |r| r.type == :vehicle_group_duration }.each{ |r|
        r.linked_vehicle_ids.each{ |v|
          residual_time_for_vehicle[v] = {
            idx: idx,
            last_computed_time: 0
          }
        }
        residual_time.push(r.lapses.first)
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
          !service.unavailable_days.include?(route[:vehicle].global_day_index) &&
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
      vehicle.rests.collect{ |rest|
        next unless rest.timewindows.empty? || rest.timewindows.any?{ |timewindow| timewindow.day_index.nil? || timewindow.day_index == day_index % 7 }

        # rest is compatible with this vehicle day
        new_rest = Marshal.load(Marshal.dump(rest))
        new_rest.id = "#{new_rest.id}_#{day_index + 1}"
        rests_durations[-1] += new_rest.duration
        new_rest.timewindows = generate_timewindows(rest.timewindows)
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

    def compute_possible_days(vrp)
      # for each of this service's visits, computes first and last possible day to be assigned
      vrp.services.each{ |service|
        day = @schedule_start
        nb_services_seen = 0

        # first possible day
        while day <= @schedule_end && nb_services_seen < service.visits_number
          if service.unavailable_days.include?(day) || vrp.vehicles.none?{ |v| v.available_at(day) }
            day += 1
          else
            service.first_possible_days += [day]
            nb_services_seen += 1
            day += service.minimum_lapse || 1
          end
        end

        # last possible day
        day = @schedule_end
        nb_services_seen = 0
        while day >= @schedule_start && nb_services_seen < service.visits_number
          if service.unavailable_days.include?(day) || vrp.vehicles.none?{ |v| v.available_at(day) }
            day -= 1
          else
            service.last_possible_days += [day]
            nb_services_seen += 1
            day -= service.minimum_lapse || 1
          end
        end
        service.last_possible_days.reverse!
      }
    end

    def save_vehicle_linking_relations(vrp)
      vehicle_linking_relations, vrp.relations = vrp.relations.partition{ |r|
        [:vehicle_group_duration, :vehicle_group_duration_on_weeks, :vehicle_group_duration_on_months,
         :vehicle_trips].include?(r.type)
      }
      vehicle_linking_relations
    end

    def cut_linking_vehicle_relation_by_period(relation, periods, relation_type)
      additional_relations = []
      vehicles_in_relation =
        relation[:linked_vehicle_ids].flat_map{ |v| @equivalent_vehicles[v] }

      while periods.any?
        days_in_period = periods.slice!(0, relation.periodicity).flatten
        relation_vehicles = vehicles_in_relation.select{ |id| days_in_period.include?(id.split('_').last.to_i) }
        next unless relation_vehicles.any?

        additional_relations << Models::Relation.create(
          linked_vehicle_ids: relation_vehicles,
          lapses: relation.lapses,
          type: relation_type
        )
      end

      additional_relations
    end

    def collect_weeks_in_schedule
      current_day = (@schedule_start + 1..@schedule_start + 7).find{ |d| d % 7 == 0 } # next monday
      schedule_week_indices = [(@schedule_start..current_day - 1).to_a]
      while current_day + 6 <= @schedule_end
        schedule_week_indices << (current_day..current_day + 6).to_a
        current_day += 7
      end
      schedule_week_indices << (current_day..@schedule_end).to_a unless current_day > @schedule_end

      schedule_week_indices
    end

    def generate_relations_on_periodic_vehicles(vrp, vehicle_linking_relations)
      vrp.relations.concat(vehicle_linking_relations.flat_map{ |relation|
        case relation[:type]
        when :vehicle_group_duration
          Models::Relation.create(
            type: :vehicle_group_duration,
            linked_vehicle_ids: relation[:linked_vehicle_ids].flat_map{ |v| @equivalent_vehicles[v] },
            lapses: relation.lapses
          )
        when :vehicle_group_duration_on_weeks
          schedule_week_indices = collect_weeks_in_schedule
          cut_linking_vehicle_relation_by_period(relation, schedule_week_indices, :vehicle_group_duration)
        when :vehicle_group_duration_on_months
          cut_linking_vehicle_relation_by_period(relation, vrp.schedule_months_indices, :vehicle_group_duration)
        when :vehicle_trips
          # we want want vehicle_trip relation per day :
          all_days = (@schedule_start..@schedule_end).to_a
          cut_linking_vehicle_relation_by_period(relation, all_days, :vehicle_trips)
        end
      })
    end

    private

    def get_original_values(original, options)
      # Except the following keys (which do not have a non-id version) skip the id version to crete a shallow copy
      fields_without_a_non_id_method = %i[original_id matrix_id value_matrix_id].freeze
      [original.attributes.keys + options.keys].flatten.each_with_object({}) { |key, data|
        next if (key[-3..-1] == '_id' || key[-4..-1] == '_ids') && fields_without_a_non_id_method.exclude?(key)

        # if a key is supplied in the options manually as nil, this means removing the key
        next if options.key?(key) && options[key].nil?

        data[key] = options[key] || original[key]
      }
    end

    def duplicate_safe(original, options = {})
      # TODO : replace by implementing initialize_copy function for shallow copy + create model for visits
      original.class.create(get_original_values(original, options))
    end
  end
end
