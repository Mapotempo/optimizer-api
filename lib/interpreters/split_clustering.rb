# Copyright © Mapotempo, 2017
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

require './lib/clusterers/average_tree_linkage.rb'
require './lib/clusterers/complete_linkage_max_distance.rb'
require './lib/helper.rb'
require './lib/interpreters/periodic_visits.rb'

module Interpreters
  class SplitClustering
    # Relations that link multiple services to be on the same route
    LINKING_RELATIONS = %i[
      order
      same_route
      sequence
      shipment
      same_vehicle
    ].freeze
    # Relations that force multiple services/vehicles to stay in the same VRP
    FORCING_RELATIONS = %i[
      maximum_day_lapse
      maximum_duration_lapse
      meetup
      minimum_day_lapse
      minimum_duration_lapse
      vehicle_trips
    ].freeze

    # TODO: private method
    def self.split_clusters(service_vrp, job = nil, &block)
      vrp = service_vrp[:vrp]

      if vrp.configuration.preprocessing.partitions&.any?
        splited_service_vrps = generate_split_vrps(service_vrp, job, block)
        OutputHelper::Clustering.generate_files(splited_service_vrps, vrp.configuration.preprocessing.partitions.size == 2, job) if OptimizerWrapper.config[:debug][:output_clusters] && service_vrp.size < splited_service_vrps.size

        split_solutions = splited_service_vrps.each_with_index.map{ |split_service_vrp, i|
          cluster_ref = i + 1
          solution = OptimizerWrapper.define_process(split_service_vrp, job) { |wrapper, avancement, total, message, cost, time, solution|
            msg = "split partition process #{cluster_ref}/#{splited_service_vrps.size} - #{message}" unless message.nil?
            block&.call(wrapper, avancement, total, msg, cost, time, solution)
          }

          # add associated cluster as skill
          next if solution.nil?

          solution.routes.each{ |route|
            route.stops.each do |stop|
              next unless stop.service_id

              stop.skills = stop.skills.to_a + ["cluster #{cluster_ref}"]
            end
          }
          solution.unassigned.each do |stop|
            next if stop.service_id.nil?

            stop.skills = stop.skills.to_a + ["cluster #{cluster_ref}"]
          end
          solution
        }

        # merge expanded vehicles, services and relations
        vrp.vehicles = splited_service_vrps.flat_map{ |sv| sv[:vrp].vehicles }
        vrp.services = splited_service_vrps.flat_map{ |sv| sv[:vrp].services }
        vrp.relations = splited_service_vrps.flat_map{ |sv| sv[:vrp].relations }

        return split_solutions.reduce(&:+)
      elsif split_solve_candidate?(service_vrp)
        return split_solve(service_vrp, &block)
      else
        service_vrp[:dicho_level] ||= 0
        return nil
      end
    end

    def self.generate_split_vrps(service_vrp, _job = nil, block = nil)
      log '--> generate_split_vrps (clustering by partition)'
      vrp = service_vrp[:vrp]
      return unless vrp.configuration.preprocessing.partitions&.any?

      allowed_metric = %i[duration visits]
      allowed_metric += vrp.units.map{ |unit| unit.id.to_sym }

      current_service_vrps = [service_vrp]
      partitions = vrp.configuration.preprocessing.partitions
      vrp.configuration.preprocessing.partitions = []
      partitions.each_with_index{ |partition, partition_index|
        cut_symbol = allowed_metric.include?(partition[:metric]) ? partition[:metric] : :duration
        case partition[:technique]
        when 'balanced_kmeans'
          generated_service_vrps = current_service_vrps.collect.with_index{ |s_v, s_v_i|
            block&.call(nil, nil, nil, "clustering phase #{partition_index + 1}/#{partitions.size} - step #{s_v_i + 1}/#{current_service_vrps.size}", nil, nil, nil)

            # TODO : global variable to know if work_day entity
            s_v[:vrp].vehicles = list_vehicles(s_v[:vrp].configuration.schedule&.range_indices,
                                               s_v[:vrp].vehicles, partition[:entity])
            options = { cut_symbol: cut_symbol, entity: partition[:entity], centroids: partition[:centroids]}
            options[:restarts] = partition[:restarts] if partition[:restarts]
            split_balanced_kmeans(s_v, s_v[:vrp].vehicles.size, options, &block)
          }
          current_service_vrps = generated_service_vrps.flatten
        when 'hierarchical_tree'
          generated_service_vrps = current_service_vrps.collect{ |s_v|
            current_vrp = s_v[:vrp]
            current_vrp.vehicles = list_vehicles(s_v[:vrp].configuration.schedule&.range_indices,
                                                 [current_vrp.vehicles.first], partition[:entity])
            split_hierarchical(s_v, current_vrp, current_vrp.vehicles.size,
                               cut_symbol: cut_symbol, entity: partition[:entity])
          }
          current_service_vrps = generated_service_vrps.flatten
        else
          raise OptimizerWrapper::UnsupportedProblemError, "Unknown partition method #{partition[:technique]}"
        end
      }
      current_service_vrps
    end

    def self.split_solve_candidate?(service_vrp)
      vrp = service_vrp[:vrp]
      if service_vrp[:split_level].nil?
        empties_or_fills = vrp.services.select{ |s| s.quantities.any?(&:fill) || s.quantities.any?(&:empty) }

        !vrp.schedule? &&
          vrp.configuration.preprocessing.max_split_size &&
          vrp.vehicles.size > 1 &&
          (vrp.configuration.resolution.vehicle_limit.nil? || vrp.configuration.resolution.vehicle_limit > 1) &&
          (vrp.services.size - empties_or_fills.size) > vrp.configuration.preprocessing.max_split_size
      else
        ss_data = service_vrp[:split_solve_data]
        return false if ss_data[:cannot_split_further]

        # filter the vehicles that are forced to be on the same side
        current_vehicle_ids = ss_data[:current_vehicles].map(&:id)
        ss_data[:representative_vrp].relations.each{ |rel|
          raise 'There should be only :same_route relations inside the representative_vrp.' if rel.type != :same_route

          current_vehicle_ids << rel.linked_ids.join if current_vehicle_ids.reject!{ |id| rel.linked_ids.include?(id) }
        }

        current_vehicle_ids.size > 1 && (ss_data[:current_vehicle_limit] || Helper.fixnum_max) > 1 &&
          ss_data[:current_vehicles].sum{ |vehicle|
            ss_data[:service_vehicle_assignments][vehicle.id].size
          } > vrp.configuration.preprocessing.max_split_size
      end
    end

    # TODO: Following are ways to improve split_solve performance (2, 3, 4 cpu time) (5 solution quality)
    # TODO: 2- decrease iteration-complexity by "relaxing" the convergence limits (movement, balance-violation) of k-means for max_split?
    # TODO: 3- decrease point-complexity by "grouping" by lat/lon more aggressively for this split
    # TODO: 4- decrease vehicle-complexity by improving balanced_vrp_clustering
    #          - by not re-calculating the item-vehicle compatibility every iteration and
    #          - by considering only a subset of compatible vehicles
    # TODO: 5- improve best cluster metric so that it considers depot distance and cluster size;
    #          otherwise, metric can "penalize" better splits
    def self.split_solve(service_vrp, job = nil, &block)
      log '--> split_solve (clustering by max_split)'
      vrp = service_vrp[:vrp]
      log "available_vehicle_ids: #{vrp.vehicles.size} - #{vrp.vehicles.collect(&:id)}", level: :debug

      # Initialize by first split_by_vehicle and keep the assignment info (don't generate the sub-VRPs yet)
      empties_or_fills = vrp.services.select{ |s| s.quantities.any?(&:fill) || s.quantities.any?(&:empty) }
      vrp.services -= empties_or_fills
      split_by_vehicle = split_balanced_kmeans(service_vrp, vrp.vehicles.size, cut_symbol: :duration, restarts: 2, build_sub_vrps: false)

      # ss_data
      service_vrp[:split_level] = 0
      service_vrp[:split_solve_data] = {
        current_vehicles: vrp.vehicles.map(&:itself), # new array but original objects
        current_vehicle_limit: vrp.configuration.resolution.vehicle_limit,
        vehicle_has_complete_matrix: vrp.vehicles.map{ |v| [v.id, !v.matrix_id.blank?] }.to_h,
        transferred_empties_or_fills: empties_or_fills.map(&:itself), # new array but original objects
        transferred_vehicles: [],
        transferred_vehicle_limit: vrp.configuration.resolution.vehicle_limit && 0,
        transferred_time_limit: 0.0,
        service_vehicle_assignments: vrp.vehicles.map.with_index{ |v, i| [v.id, split_by_vehicle[i]] }.to_h,
        original_vrp: vrp,
        representative_vrp: nil,
      }
      transfer_empty_vehicles, service_vrp[:split_solve_data][:current_vehicles] =
        service_vrp[:split_solve_data][:current_vehicles].partition{ |vehicle|
          service_vrp[:split_solve_data][:service_vehicle_assignments][vehicle.id].empty?
        }
      service_vrp[:split_solve_data][:transferred_vehicles].concat(transfer_empty_vehicles)
      transfer_empty_vehicles.each{ |v| service_vrp[:split_solve_data][:service_vehicle_assignments].delete(v.id) }
      service_vrp[:split_solve_data][:representative_vrp] = create_representative_vrp(service_vrp[:split_solve_data])

      # Then split the services into left-and-right groups by
      # using the service_vehicle_assignments information
      # (don't generate any sub-VRP yet)
      split_solve_core(service_vrp, job, &block) # self-recursive method
    ensure
      service_vrp[:vrp] = service_vrp[:split_solve_data][:original_vrp] if service_vrp[:split_solve_data]
      service_vrp[:vrp]&.services&.concat empties_or_fills
      log '<-- split_solve (clustering by max_split)'
    end

    # self-recursive method
    def self.split_solve_core(service_vrp, job = nil, &block)
      split_level = service_vrp[:split_level]
      ss_data = service_vrp[:split_solve_data]

      if split_solve_candidate?(service_vrp) # if it still needs splitting
        enum_current_vehicles = ss_data[:current_vehicles].select # Enumerator to keep a local copy of current_vehicles
        current_vehicle_limit = ss_data[:current_vehicle_limit]

        # SPLIT current_vehicles list (by-vehicle-centroids) to create two "sides"
        sides = split_balanced_kmeans(
          { vrp: create_representative_sub_vrp(ss_data) }, 2,
          cut_symbol: :duration, restarts: 3, build_sub_vrps: false, basic_split: true, group_points: false
        ).sort_by!{ |side|
          [side.size, side.sum(&:visits_number)] # [number_of_vehicles, number_of_visits]
        }.reverse!.collect!{ |side|
          enum_current_vehicles.select{ |v| side.any?{ |s| s.id == "0_representative_vrp_s_#{v.id}" } }
        }

        unless sides.size == 2 && sides.none?(&:empty?)
          # this might happen under certain cases (skills etc can force all points to be on one side)
          # and not necessarily a problem but it should happen very rarely (in real instances)
          # it might also happen because the vehicles are in a linking relation (like vehicle_trips)
          # which forces them to be stay on one side.
          log 'There should be exactly two clusters in split_solve_core!', level: :warn
          ss_data[:cannot_split_further] = true
        end

        # TODO: In some case one side might be significantly smaller than the other side.
        # This is not necessarily a bad thing but we might want to re-groupe such "tiny" VRPs
        # to prevent inefficient use of vehicles.

        split_service_counts = sides.collect{ |current_vehicles|
          current_vehicles.sum{ |v| ss_data[:service_vehicle_assignments][v.id].size }
        }
        log "--> split_solve_core level: #{split_level} | split services #{split_service_counts.sum}->#{split_service_counts}, vehicles #{enum_current_vehicles.size}->#{sides.collect(&:size)}"

        # RECURSIVELY CALL split_solve_core AND MERGE SOLUTIONS
        solutions = sides.collect.with_index{ |side, index|
          service_vrp[:split_level] = split_level + 1

          ss_data[:current_vehicles] = side

          v_limit = current_vehicle_limit.to_f * side.size / enum_current_vehicles.size
          # Warning: round does not work if there is an even "half" split
          ss_data[:current_vehicle_limit] = current_vehicle_limit && (index.zero? ? v_limit.ceil : v_limit.floor)

          split_solve_core(service_vrp, job = nil, &block)
        }
        ss_data[:cannot_split_further] = false
        log "<-- split_solve_core level: #{split_level}"

        solutions.reduce(&:+)
      else # Stopping condition -- the problem is small enough
        # Finally generate the sub-vrp without hard-copy and solve it
        solution = split_solve_sub_vrp(service_vrp, job, &block)
        transfer_unused_resources(ss_data, service_vrp[:vrp], solution)
        solution
      end
    end

    def self.split_solve_sub_vrp(service_vrp, job = nil, &block)
      ss_data = service_vrp[:split_solve_data]
      split_level = service_vrp[:split_level] # local split_level var is needed to show the level value correctly
      service_cnt = "#{ss_data[:current_vehicles].sum{ |v| ss_data[:service_vehicle_assignments][v.id].size }} services"
      vehicle_cnt = "#{ss_data[:current_vehicles].size}+#{ss_data[:transferred_vehicles].size} vehicles"
      log "--> split_solve_sub_vrp lv: #{split_level} | solving #{service_cnt} with #{vehicle_cnt}"

      service_vrp[:vrp] = create_sub_vrp(ss_data)

      solution = OptimizerWrapper.define_process(service_vrp, job, &block)
      solution.parse(service_vrp[:vrp])
    ensure
      log "<-- split_solve_sub_vrp lv: #{split_level}"
    end

    def self.create_sub_vrp(split_solve_data)
      ss_data = split_solve_data
      o_vrp = ss_data[:original_vrp]

      sub_vrp = ::Models::Vrp.create({}, delete: false)

      # Select the vehicles and services belonging to this sub-problem from the service_vehicle_assignments
      # transfer a vehicle with a forcing linked relation only if all of its linked vehicles can be transferred as well
      sub_vrp.vehicles = ss_data[:current_vehicles] + transfer_unused_vehicles(ss_data)
      sub_vrp.services = ss_data[:current_vehicles].flat_map{ |v| ss_data[:service_vehicle_assignments][v.id] }
      sub_vrp.services.concat ss_data[:transferred_empties_or_fills]

      # only necessary points -- because compute_matrix doesn't check the difference
      sub_vrp.points = sub_vrp.services.map{ |s| s.activity.point } |
                       sub_vrp.vehicles.flat_map{ |v| [v.start_point, v.end_point].compact }

      # only necessary relations
      sub_vrp.relations = select_existing_relations(o_vrp.relations, sub_vrp)

      # only the non-empty initial routes of current vehicles
      sub_vrp.routes = o_vrp.routes.select{ |route|
        route.vehicle && route.mission_ids.any? && sub_vrp.vehicles.any?{ |v| v.id == route.vehicle.id }
      }

      # it is okay if these stay as original
      sub_vrp.matrices = o_vrp.matrices
      sub_vrp.units = o_vrp.units
      sub_vrp.rests = o_vrp.rests
      sub_vrp.zones = o_vrp.zones
      sub_vrp.subtours = o_vrp.subtours

      sub_vrp.configuration = Oj.load(Oj.dump(o_vrp.configuration)) # time and other limits are correct below
      # split the limits
      sub_vrp.configuration.resolution.vehicle_limit = ss_data[:current_vehicle_limit] + ss_data[:transferred_vehicle_limit] if ss_data[:current_vehicle_limit]
      ratio = sub_vrp.services.size.to_f / o_vrp.services.size
      sub_vrp.configuration.resolution.duration = (o_vrp.configuration.resolution.duration * ratio + ss_data[:transferred_time_limit]).ceil if o_vrp.configuration.resolution.duration
      sub_vrp.configuration.resolution.minimum_duration = o_vrp.configuration.resolution.minimum_duration&.*(ratio)&.ceil
      sub_vrp.configuration.resolution.iterations_without_improvment = o_vrp.configuration.resolution.iterations_without_improvment&.*(ratio)&.ceil

      sub_vrp.name = "#{o_vrp.name}_#{ss_data[:current_level]}_#{Digest::MD5.hexdigest(sub_vrp.vehicles.map(&:id).join)}"

      sub_vrp
    end

    def self.create_representative_vrp(split_solve_data)
      # This VRP represent the original VRP with only `m` number of points by reducing the services belonging to the
      # same vehicle-zone to a single point (with average lat/lon and total duration/visits). Where `m` is the
      # number of non-empty vehicle-zones generated by the very first split_by_vehicle.

      points = []
      services = []
      relations = []
      visit_counts = []
      split_solve_data[:service_vehicle_assignments].each{ |vehicle_id, vehicle_services|
        average_lat = vehicle_services.sum{ |s| s.activity.point.location.lat } / vehicle_services.size.to_f
        average_lon = vehicle_services.sum{ |s| s.activity.point.location.lon } / vehicle_services.size.to_f
        points << { id: "0_representative_vrp_p_#{vehicle_id}", location: { lat: average_lat, lon: average_lon }}
        visit_counts << vehicle_services.size
        services << {
          id: "0_representative_vrp_s_#{vehicle_id}", # vehicle_id used to find the original service-vehicle assignment
          visits_number: 1,
          activity: {
            point_id: "0_representative_vrp_p_#{vehicle_id}",
            duration: vehicle_services.sum{ |s| s.activity.duration.to_f } / Math.sqrt(vehicle_services.size)
          }
        }

        # If there are many points in the sub-representative-vrp. We can represent each group with multiple
        # points, carefully selected to represent the extremes of the group and "relate" these points
        # with :same_route so that they will stay on the same "side" in the 2-split. So that the vehicles
        # with close points can stay on the same side.
        next if vehicle_services.size < 5

        vehicle_service_coordinates = vehicle_services.collect{ |s| [s.activity.point.location.lat, s.activity.point.location.lon] }
        extreme_points = Helper.approximate_quadrilateral_polygon(vehicle_service_coordinates).uniq
        linked_ids = ["0_representative_vrp_s_#{vehicle_id}"]
        extreme_points.each_with_index{ |lat_lon, index|
          points << { id: "#{index + 1}_representative_vrp_p_#{vehicle_id}", location: { lat: lat_lon[0], lon: lat_lon[1] }}
          visit_counts << 1
          services << {
            id: "#{index + 1}_representative_vrp_s_#{vehicle_id}", # vehicle_id used to find the original service-vehicle assignment
            visits_number: 1,
            activity: {
              point_id: "#{index + 1}_representative_vrp_p_#{vehicle_id}",
              duration: 1
            }
          }
          linked_ids << "#{index + 1}_representative_vrp_s_#{vehicle_id}"
        }

        relations << { type: :same_route, linked_ids: linked_ids }
      }

      # go through the original relations and force the services and vehicles to stay in the same sub-vrp if necessary
      split_solve_data[:original_vrp].relations.select{ |r| FORCING_RELATIONS.include?(r.type) }.each{ |relation|
        if relation.linked_vehicle_ids.any? && relation.linked_services.none?
          linked_ids = []
          relation.linked_vehicle_ids.map{ |v_id|
            s_id = "0_representative_vrp_s_#{v_id}"
            linked_ids << s_id if services.any?{ |s| s[:id] == s_id }
          }

          relations << { type: :same_route, linked_ids: linked_ids } if linked_ids.size > 1
        elsif relation.linked_vehicle_ids.none? && relation.linked_services.any?
          linked_ids = []
          relation.linked_services.each{ |linked_service|
            split_solve_data[:service_vehicle_assignments].any?{ |v_id, v_services|
              linked_ids << "0_representative_vrp_s_#{v_id}" if v_services.include?(linked_service)
            }
          }
          linked_ids.uniq!
          relations << { type: :same_route, linked_ids: linked_ids } if linked_ids.size > 1
        else
          # This shouldn't be possible
          raise 'Unknown relation case in create_representative_vrp. If there is a new relation, update this function'
        end
      }

      # TODO: The following two "fake" vehicles can have carefully selected start and end points!
      #       So that if there are multiple zone/cities or multiple depots, the split will be
      #       more intelligent. For that we need go over the list of uniq depots and select two
      #       depots from the list that "split" the depots into two groups and minimize the total
      #       distance between the selected depots. Then these two depots can be used as the
      #       depots for these two "fake" vehicles.
      representative_vrp = ::Models::Vrp.create({
        name: 'representative_vrp',
        points: points,
        vehicles: Array.new(2){ |i| { id: "v#{i}", router_mode: 'car' } },
        services: services,
        relations: relations
      }, delete: false)

      # To make sure that each point reflects the "weight" of all the points merged under this point
      # Due to the fact that visits_number is available only with scheduling, we set the visits_number
      # after the vrp is created.
      visit_counts.each_with_index{ |visit, index| representative_vrp[:services][index].visits_number = visit }

      representative_vrp
    end

    def self.create_representative_sub_vrp(split_solve_data)
      # This is the sub vrp representing the original vrp with "reduced" services
      # (see create_representative_vrp function above for more explanation)
      representative_vrp = split_solve_data[:representative_vrp]
      r_sub_vrp = ::Models::Vrp.create({ name: 'representative_sub_vrp' }, delete: false)
      r_sub_vrp.vehicles = representative_vrp.vehicles # 2-fake-vehicles
      r_sub_vrp.services = representative_vrp.services.select{ |representative_service|
        # the service which represent the services of vehicle `v`, has its id include `v.id`
        split_solve_data[:current_vehicles].any?{ |v| representative_service.id.end_with?("_representative_vrp_s_#{v.id}") }
      }
      r_sub_vrp.points = r_sub_vrp.services.map{ |s| s.activity.point }
      r_sub_vrp.relations = representative_vrp.relations.select{ |relation|
        r_sub_vrp.services.any?{ |s| s.id == relation.linked_ids[0] }
      }
      r_sub_vrp
    end

    def self.transfer_unused_vehicles(split_solve_data)
      # transfers an unused vehicle to the current sub-problem if and only if
      # all forcing relations can be respected (vehicle_trips, meetup etc.)
      ss_data = split_solve_data
      o_vrp = ss_data[:original_vrp]

      unused_vehicle_ids = ss_data[:transferred_vehicles].map(&:id)
      current_and_unused_vehicle_ids = ss_data[:current_vehicles].map(&:id) + unused_vehicle_ids

      related_forcing_relations = o_vrp.relations.select{ |r|
        FORCING_RELATIONS.include?(r.type) && (r.linked_vehicle_ids.to_a & unused_vehicle_ids).any?
      }

      # FIXME: this operation can be done faster by exploiting the fact that some unused vehicles might share a relation
      selected_vehicles_to_use = []
      ss_data[:transferred_vehicles].each{ |transferred_vehicle|
        can_have_all_its_linked_vehicles_if_transferred = related_forcing_relations.all?{ |relation|
          relation.linked_vehicle_ids.exclude?(transferred_vehicle.id) ||
            (relation.linked_vehicle_ids - current_and_unused_vehicle_ids).empty?
        }

        selected_vehicles_to_use << transferred_vehicle if can_have_all_its_linked_vehicles_if_transferred
      }

      selected_vehicles_to_use
    end

    def self.select_existing_relations(relations, vrp)
      relations.select{ |relation|
        next if relation.linked_vehicle_ids.empty? && relation.linked_ids.empty?

        (
          relation.linked_vehicle_ids.empty? ||
            relation.linked_vehicle_ids.any?{ |id| vrp.vehicles.any?{ |v| v.id == id } }
        ) && (
          relation.linked_ids.empty? ||
            relation.linked_ids.any?{ |id| vrp.services.any?{ |s| s.id == id } }
        )
      }
    end

    def self.transfer_unused_resources(split_solve_data, vrp, solution)
      # remove used empties_or_fills
      split_solve_data[:transferred_empties_or_fills].delete_if{ |service|
        solution.unassigned.none?{ |a| a.service_id == service.id }
      }

      remove_empty_routes(solution)
      # empty poorly populated routes only if necessary
      if solution.unassigned.empty? &&
         solution.routes.size == vrp.vehicles.size &&
         (vrp.configuration.resolution.vehicle_limit.nil? || solution.routes.size == vrp.configuration.resolution.vehicle_limit)
        remove_poorly_populated_routes(vrp, solution, 0.1)
      end

      used_vehicle_ids = solution.routes.map{ |r| r.vehicle.id }
      forcing_vehicle_relations = split_solve_data[:original_vrp].relations.select{ |r|
        FORCING_RELATIONS.include?(r.type) && r.linked_vehicle_ids&.any?
      }

      split_solve_data[:transferred_vehicles].delete_if{ |vehicle|
        # mark used (delete from transferred_vehicles) if used or there is a used linked vehicle from a forcing relation
        next true if used_vehicle_ids.include?(vehicle.id)

        related_relations = forcing_vehicle_relations.select{ |r| r.linked_vehicle_ids.include?(vehicle.id) }
        (used_vehicle_ids & related_relations.flat_map(&:linked_vehicle_ids)).any?
      }

      split_solve_data[:transferred_vehicles].concat(split_solve_data[:current_vehicles].select{ |vehicle|
        # mark unused (add to transferred_vehicles) if not used and there is no used linked vehicle from a forcing relation
        next false if used_vehicle_ids.include?(vehicle.id)

        related_relations = forcing_vehicle_relations.select{ |r| r.linked_vehicle_ids.include?(vehicle.id) }
        (used_vehicle_ids & related_relations.flat_map(&:linked_vehicle_ids)).empty?
      })

      split_solve_data[:transferred_vehicles].each{ |v|
        v.matrix_id = nil unless split_solve_data[:vehicle_has_complete_matrix][v.id]
      }

      # transfer unused resources
      if split_solve_data[:transferred_vehicle_limit]
        split_solve_data[:transferred_vehicle_limit] = vrp.configuration.resolution.vehicle_limit - solution.routes.size
      end
      split_solve_data[:transferred_time_limit] = [vrp.configuration.resolution.duration.to_f - solution.elapsed, 0].max # to_f incase nil
      nil
    end

    def self.remove_poor_routes(vrp, solution)
      return unless solution

      remove_empty_routes(solution)
      remove_poorly_populated_routes(vrp, solution, 0.1) if !Interpreters::Dichotomious.dichotomious_candidate?(vrp: vrp, service: :ortools)
    end

    def self.remove_empty_routes(solution)
      solution.routes.delete_if{ |route| route.stops.none?(&:service_id) }
    end

    def self.remove_poorly_populated_routes(vrp, solution, limit)
      forcing_relation_vehicle_ids = vrp.relations.flat_map{ |relation|
        FORCING_RELATIONS.include?(relation.type) ? relation.linked_vehicle_ids.to_a : []
      }.uniq

      emptied_routes = false
      solution.routes.delete_if{ |route|
        vehicle = vrp.vehicles.find{ |current_vehicle| current_vehicle.id == route.vehicle_id }
        loads = route.stops.last.loads
        load_flag = vehicle.capacities.empty? || vehicle.capacities.all?{ |capacity|
          current_load = loads.find{ |unit_load| unit_load.quantity.unit.id == capacity.unit.id }
          current_load.current / capacity.limit < limit if capacity.limit && current_load && capacity.limit > 0
        }
        vehicle_worktime = vehicle.duration ||
                           vehicle.timewindow&.end && (vehicle.timewindow.end - vehicle.timewindow.start)
        route_duration = route.info.total_time ||
                         (route.stops.last.info.begin_time - route.stops.first.info.begin_time)
        log "route #{route.vehicle.id} time: #{route_duration}/#{vehicle_worktime} percent: " \
            "#{((route_duration / (vehicle_worktime || route_duration).to_f) * 100).to_i}%", level: :info

        # Do not remove a poorly populated routes if it is in a forcing relation
        # TODO: Ideally, we wouldn't remove a poorly populated vehicle only if, any of its linked vehicles is
        # "non-removable" (i.e., either it is well-used or it has a well-used link)
        # Or we would calculate the "overall" stats for all linked vehicles and remove/leave them together
        # NOTE: This might need a recursive logic because different vehicles might be connected via different
        # FORCING_RELATIONS.
        next if forcing_relation_vehicle_ids.include?(route[:vehicle_id])

        time_flag = vehicle_worktime && route_duration < limit * vehicle_worktime

        if load_flag && time_flag
          emptied_routes = true
          %i[total_distance total_time total_travel_time total_value].each{ |key|
            result[key] -= route[key] if route[key]
          }

          number_of_services_in_the_route = route.stops.count(&:service_id)

          log "route #{route.vehicle.id} is emptied: #{number_of_services_in_the_route} " \
              'services are now unassigned.', level: :info

          solution.unassigned += route.stops.select(&:service_id)
          true
        end
      }

      log 'Some routes are emptied due to poor workload -- time or quantity.', level: :warn if emptied_routes
    end

    def self.update_matrix(sub_vrp, matrix_indices)
      sub_vrp.matrices.each{ |matrices|
        [:time, :distance, :value].each{ |dimension|
          matrix = matrices.send(dimension)
          next unless matrix

          matrices.send("#{dimension}=", matrix_indices.map{ |r_index| matrix[r_index].values_at(*matrix_indices) })
        }
      }
    end

    def self.update_matrix_index(vrp)
      vrp.points.each_with_index{ |point, index|
        point.matrix_index = index
      }
    end

    def self.build_partial_service_vrp(service_vrp, partial_service_ids, available_vehicles_indices = nil, entity = nil)
      log '---> build_partial_service_vrp', level: :debug
      Models.delete_all
      tic = Time.now
      vrp = service_vrp[:vrp]
      vrp_hash = JSON.parse(vrp.empty_json, symbolize_names: true)
      sub_vrp = Models::Vrp.create(vrp_hash)
      sub_vehicles = []
      if available_vehicles_indices
        sub_vrp.vehicles = vrp.vehicles.select.with_index{ |_v, v_i| available_vehicles_indices.include?(v_i) }
        sub_vrp.routes = vrp.routes.select{ |r|
          route_week_day = r.day_index ? r.day_index % 7 : nil
          sub_vehicles.any?{ |vehicle|
            vehicle_week_day_availability =
              if vehicle.timewindow
                vehicle.timewindow.day_index || (0..6)
              else
                vehicle.sequence_timewindows.collect{ |tw|
                  tw.day_index || (0..6)
                }.flatten.uniq
              end

            vehicle.id == r.vehicle_id && (route_week_day.nil? || vehicle_week_day_availability.include?(route_week_day))
          }
        }
        sub_vrp
      else
        sub_vrp.vehicles = vrp.vehicles
        sub_vrp.routes = vrp.routes
      end

      matrix_ids = sub_vrp.vehicles.map(&:matrix_id).uniq
      sub_vrp.matrices = vrp.matrices
      sub_vrp.units = vrp.units

      sub_vrp.services = vrp.services.select{ |service| partial_service_ids.include?(service.id) }
      rest_ids = sub_vrp.vehicles.flat_map{ |v| v.rests.map(&:id) }.uniq
      sub_vrp.rests = vrp.rests.select{ |r| rest_ids.include?(r.id) }
      available_vehicle_ids = sub_vrp.vehicles.map(&:id)

      sub_vrp.relations = vrp.relations.select{ |r|
        next if r.type == :same_vehicle && entity == :vehicle

        # Split should respect relations, it is enough to check only the first linked id --  [0..0].all? is to handle empties
        r.linked_ids[0..0].all?{ |sid| partial_service_ids.include?(sid) } &&
          r.linked_vehicle_ids[0..0].all?{ |vid| available_vehicle_ids.include?(vid) }
      }

      split_respects_relations = sub_vrp.relations.all?{ |r|
        non_matching_linked_ids = r.linked_ids - partial_service_ids
        non_matching_linked_vehicle_ids = r.linked_vehicle_ids - available_vehicle_ids

        (non_matching_linked_ids.empty? || non_matching_linked_ids.size == r.linked_ids.size) &&
          (non_matching_linked_vehicle_ids.empty? || non_matching_linked_vehicle_ids.size == r.linked_vehicle_ids.size)
      }
      unless split_respects_relations
        err_msg = 'Split does not respect relations. Some relations will be silently ignored.'
        log err_msg, level: :warn
        raise err_msg if ENV['APP_ENV'] != 'production'
      end

      sub_vrp.points = sub_vrp.services.map{ |s| s.activity.point }.compact |
                       sub_vrp.vehicles.flat_map{ |vehicle| [vehicle.start_point, vehicle.end_point] }.compact
      sub_vrp.points.uniq!
      sub_vrp = add_corresponding_entity_skills(entity, sub_vrp)

      sub_vrp_hash = JSON.parse(sub_vrp.to_json, symbolize_names: true)

      vehicle_ids = sub_vrp_hash[:vehicles]&.map{ |v| v[:id] } || []
      sub_vrp_hash[:services].each{ |service|
        service[:sticky_vehicle_ids]&.delete_if{ |stick| !vehicle_ids.include?(stick) }
      }

      sub_vrp = Models::Vrp.create(sub_vrp_hash, check: false)

      if !sub_vrp.matrices&.empty?
        matrix_indices = sub_vrp.points.map{ |point| point.matrix_index }
        update_matrix_index(sub_vrp)
        update_matrix(sub_vrp, matrix_indices)
      end

      log "<--- build_partial_service_vrp takes #{Time.now - tic}", level: :debug
      {
        vrp: sub_vrp,
        service: service_vrp[:service]
      }
    end

    # TODO: private method, reduce params
    def self.kmeans_process(nb_clusters, data_items, related_item_indices, limits, options = {}, &block)
      biggest_cluster_size = 0
      clusters = []
      restart = 0
      best_limit_score = nil
      c = nil
      score_hash = {}
      while restart < options[:restarts]
        block&.call() # in case job is killed during restarts
        log "Restart #{restart}/#{options[:restarts]}", level: :debug
        c = Ai4r::Clusterers::BalancedVRPClustering.new
        c.max_iterations = options[:max_iterations]
        c.distance_matrix = options[:distance_matrix]
        c.vehicles = options[:clusters_infos]
        c.centroid_indices = options[:centroid_indices] || []
        c.on_empty = 'closest'
        c.logger = OptimizerLogger.logger

        ratio = 0.9 + 0.1 * (options[:restarts] - restart) / options[:restarts].to_f

        # TODO: move the creation of data_set to the gem side GEM should create it if necessary
        options[:seed] = rand(1234567890) # gem does not initialise the seed randomly
        log "BalancedVRPClustering is launched with seed #{options[:seed]}"
        c.build(Ai4r::Data::DataSet.new(data_items: Marshal.load(Marshal.dump(data_items))),
                options[:cut_symbol],
                Oj.load(Oj.dump(related_item_indices)),
                ratio,
                options)

        c.clusters.delete([])
        values = c.clusters.collect{ |cluster| cluster.data_items.collect{ |i| i[3][options[:cut_symbol]] }.sum.to_i }
        limit_score = (0..c.centroids.size - 1).collect{ |cluster_index|
          centroid_coords = [c.centroids[cluster_index][0], c.centroids[cluster_index][1]]
          distance_to_centroid = c.clusters[cluster_index].data_items.collect{ |item| Helper.flying_distance([item[0], item[1]], centroid_coords) }.sum
          ml = limits[:metric_limit].is_a?(Array) ? c.cut_limit[cluster_index][:limit] : limits[:metric_limit][:limit]
          if c.clusters[cluster_index].data_items.size == 1
            2**32
          elsif ml.zero? # Why is it possible?
            distance_to_centroid
          else
            cluster_metric = c.clusters[cluster_index].data_items.collect{ |i| i[3][options[:cut_symbol]] }.sum.to_f
            # TODO: large clusters having great difference with target metric should have a large (bad) score
            # distance_to_centroid * ((cluster_metric - ml).abs / ml)
            balancing_coeff = if options[:entity] == :work_day
                                1.0
                              else
                                0.6
                              end
            (1.0 - balancing_coeff) * distance_to_centroid + balancing_coeff * ((cluster_metric - ml).abs / ml) * distance_to_centroid
          end
        }.sum
        checksum = Digest::MD5.hexdigest Marshal.dump(values)
        if !score_hash.has_key?(checksum)
          log "Restart: #{restart} score: #{limit_score} ratio_metric: #{c.cut_limit} iterations: #{c.iterations}", level: :debug
          log "Balance: #{values.min}   #{values.max}    #{values.min - values.max}    #{(values.sum / values.size).to_i}    #{((values.max - values.min) * 100.0 / values.max).round(2)}%", level: :debug
          score_hash[checksum] = { iterations: c.iterations, limit_score: limit_score, restart: restart, ratio_metric: c.cut_limit, min: values.min, max: values.max, sum: values.sum, size: values.size }
        end
        restart += 1
        empty_clusters_score = c.centroids.size < nb_clusters && (c.centroids.size..nb_clusters - 1).collect{ |cluster_index|
          limits[:metric_limit].is_a?(Array) ? limits[:metric_limit][cluster_index][:limit] : limits[:metric_limit][:limit]
        }.reduce(&:+) || 0
        limit_score += empty_clusters_score
        if best_limit_score.nil? || c.clusters.size > biggest_cluster_size || (c.clusters.size >= biggest_cluster_size && limit_score < best_limit_score)
          best_limit_score = limit_score
          log best_limit_score.to_s + ' -> New best cluster metric (' + c.centroids.collect{ |centroid| centroid[3][options[:cut_symbol]] }.join(', ') + ')'
          biggest_cluster_size = c.clusters.size
          clusters = c.clusters
        end
        c.centroid_indices = [] if c.centroid_indices.size < nb_clusters
      end

      raise 'Incorrect split in kmeans_process' if clusters.size > nb_clusters # it should be never more

      clusters
    end

    def self.split_balanced_kmeans(service_vrp, nb_clusters, options = {}, &block)
      log '--> split_balanced_kmeans', level: :debug

      if options[:entity] && nb_clusters != service_vrp[:vrp].vehicles.size
        raise OptimizerWrapper::ClusteringError.new('Usage of options[:entity] requires that number of clusters (nb_clusters) is equal to number of vehicles in the vrp.')
      end

      raise OptimizerWrapper::ClusteringError.new('nb_clusters should be a positive integer') if nb_clusters <= 0

      defaults = { max_iterations: 300, restarts: 10, cut_symbol: :duration, build_sub_vrps: true, group_points: true }
      options = defaults.merge(options)
      vrp = service_vrp[:vrp]
      # Split using balanced kmeans
      if vrp.services.all?{ |service| service.activity&.point&.location }
        result_items =
          if nb_clusters > 1 && vrp.services.any?
            cumulated_metrics = Hash.new(0)

            if options[:entity] == :work_day || !vrp.matrices.empty?
              vrp.compute_matrix if vrp.matrices.empty?

              options[:distance_matrix] = vrp.matrices[0][:time]
            end

            data_items, cumulated_metrics, grouped_objects, related_item_indices = collect_data_items_metrics(vrp, cumulated_metrics, options)

            limits = { metric_limit: centroid_limits(vrp, nb_clusters, cumulated_metrics, options[:cut_symbol], options[:entity]) } # TODO : remove because this is computed in gem. But it is also needed to compute score here. remove cumulated_metrics at the same time

            if options[:centroids] && options[:centroids].size == nb_clusters && options[:entity] != :work_day
              options[:centroid_indices] = options[:centroids]
            end

            if vrp.vehicles.any?{ |v| v.skills.count{ |skill| skill.is_a?(Array) && !skill.empty? } > 1 }
              raise OptimizerWrapper::UnsupportedProblemError.new(
                'Cannot use balanced kmeans if there are vehicles with alternative skills')
            end

            tic = Time.now

            options[:clusters_infos] = collect_cluster_data(vrp, nb_clusters)

            clusters = kmeans_process(nb_clusters, data_items, related_item_indices, limits, options, &block)

            toc = Time.now

            log "Balanced K-Means (#{toc - tic}sec): split #{data_items.size} data_items into #{clusters.map{ |c| "#{c.data_items.size}(#{c.data_items.map{ |i| i[3][options[:cut_symbol]] || 0 }.inject(0, :+)})" }.join(' & ')}"

            clusters.collect{ |cluster|
              cluster.data_items.flat_map{ |i|
                grouped_objects[i[2]]
              }
            }
          elsif vrp.services.empty?
            # this is normal if there is split independent vrp (by skills or sticky)
            # we pass here so that result is collected correctly for all expanded vehicles
            log 'Split is not possible if there is nothing to split', level: :debug

            Array.new(nb_clusters){ [] } # mimics grouped_objects
          else
            # nb_clusters == 1
            # this is normal if there is one vehicle (or one workday) and partitioning by vehicle (or workday) is active
            log 'Split is not possible if the cluster size is 1', level: :warn

            [vrp.services.dup] # mimics grouped_objects
          end

        log "Balanced K-Means: split #{result_items.sum(&:size)} activities into #{result_items.map(&:size).join(' & ')}"

        if options[:build_sub_vrps]
          result_items.collect.with_index{ |result_item, result_index|
            vehicles_indices = [result_index] if options[:entity] == :work_day || options[:entity] == :vehicle
            # TODO: build_partial_service_vrp can work directly with the list of services instead of ids.
            build_partial_service_vrp(service_vrp, result_item.collect(&:id), vehicles_indices, options[:entity])
          }.compact
        else
          # list of services by vehicle
          result_items
        end
      else
        log 'Split is not available if there are services with no activity, no location', level: :error

        # TODO : remove marshal dump
        # ensure test_instance_800unaffected_clustered and test_instance_800unaffected_clustered_same_point work
        [Marshal.load(Marshal.dump(service_vrp))]
      end
    end

    def self.split_hierarchical(service_vrp, nb_clusters, options = {})
      options[:cut_symbol] = :duration if options[:cut_symbol].nil?
      vrp = service_vrp[:vrp]
      # Split using hierarchical tree method
      if vrp.services.all?{ |service| service[:activity] }
        cumulated_metrics = Hash.new(0)

        data_items, cumulated_metrics, grouped_objects = collect_data_items_metrics(vrp, cumulated_metrics)

        c = Ai4r::Clusterers::AverageTreeLinkage.new
        start_timer = Time.now
        clusterer = c.build(Ai4r::Data::DataSet.new(data_items: data_items))
        end_timer = Time.now

        metric_limit = cumulated_metrics[options[:cut_symbol]] / nb_clusters
        # raise OptimizerWrapper::DiscordantProblemError.new("Unfitting cluster split metric. Maximum value is greater than average") if max_cut_metrics[options[:cut_symbol]] > metric_limit

        graph = Marshal.load(Marshal.dump(clusterer.graph.compact))

        # Tree cut process
        clusters = []
        max_level = graph.values.collect{ |value| value[:level] }.max

        # Top Down cut
        # current_level = max_level
        # while current_level >= 0
        #   graph.select{ |k, v| v[:level] == current_level }.each{ |k, v|
        #     next if v[:unit_metrics][options[:cut_symbol]] > 1.1 * metric_limit && current_level != 0
        #     clusters << tree_leafs_delete(graph, k).flatten.compact
        #   }
        #   current_level -= 1
        # end

        # Bottom Up cut
        (0..max_level).each{ |current_level|
          graph.select{ |_k, v| v[:level] == current_level }.each{ |k, v|
            next if v[:unit_metrics][options[:cut_symbol]] < metric_limit && current_level != max_level

            clusters << tree_leafs(graph, k).flatten.compact
            next if current_level == max_level

            remove_from_upper(graph, graph[k][:parent], options[:cut_symbol], v[:unit_metrics][options[:cut_symbol]])
            if k == graph[v[:parent]][:left]
              graph[v[:parent]][:left] = nil
            else
              graph[v[:parent]][:right] = nil
            end
          }
        }

        clusters.delete([])
        result_items = clusters.delete_if{ |cluster| cluster.data_items.empty? }.collect{ |i|
          grouped_objects[i[2]]
        }.flatten

        log "Hierarchical Tree (#{end_timer - start_timer}sec): split #{data_items.size} into #{clusters.collect{ |cluster| cluster.data_items.size }.join(' & ')}"
        # cluster_vehicles = assign_vehicle_to_clusters([[]] * vrp.vehicles.size, vrp.vehicles, vrp.points, clusters)
        adjust_clusters(clusters, limits, options[:cut_symbol], centroids, data_items) if options[:entity] == :work_day
        result_items.collect.with_index{ |result_item, _result_index|
          build_partial_service_vrp(service_vrp, result_item.collect(&:id)) #, cluster_vehicles && cluster_vehicles[result_index])
        }
      else
        log 'Split hierarchical not available when services have no activity', level: :error
        [service_vrp]
      end
    end

    def self.collect_cluster_data(vrp, nb_clusters)
      # TODO: due to historical dev, this function is in two pieces but
      # it is possbile to do the same task in one step. That is, instead of
      # collecting vehicles then eliminating to have nb_clusters vehicles,
      # we can create one with nb_clusters items directly.

      r_start = vrp.schedule? ? vrp.configuration.schedule.range_indices[:start] : 0
      r_end = vrp.schedule? ? vrp.configuration.schedule.range_indices[:end] : 0

      vehicles = vrp.vehicles.collect.with_index{ |vehicle, v_i|
        total_work_days = vrp.schedule? ? vehicle.total_work_days_in_range(r_start, r_end) : 1
        capacities = {
          duration: vrp.schedule? ? vrp.total_work_times[v_i] : vehicle.work_duration,
          visits: vehicle.capacities.find{ |cap| cap[:unit_id] == :visits } & [:limit] || vrp.visits
        }
        vehicle.capacities.each{ |capacity| capacities[capacity.unit.id.to_sym] = capacity.limit * total_work_days }
        tw = [vehicle.timewindow || vehicle.sequence_timewindows].flatten.compact
        {
          id: [vehicle.id],
          depot: {
            coordinates: [vehicle.start_point&.location&.lat, vehicle.start_point&.location&.lon],
            matrix_index: vehicle.start_point&.matrix_index
          },
          capacities: capacities,
          skills: vehicle.skills.flatten.uniq, # TODO : improve case with alternative skills. Current implementation collects all skill sets into one
          day_skills: compute_day_skills(tw),
          duration: vehicle.total_work_time_in_range(r_start, r_end),
          total_work_days: total_work_days
        }
      }

      if nb_clusters != vehicles.size
        # for max_split and dichotomious cases
        depot_counts = vehicles.collect{ |i| i[:depot] }.count_by{ |i| i }.sort_by{ |_i, cnt| -cnt }.to_h
        depots = depot_counts.keys
        while depots.size < nb_clusters
          depots += [depot_counts.max_by{ |_depot, count| count }[0]]
          depot_counts[depots.last] /= 2
        end
        vehicles = Array.new(nb_clusters){ |simulated_vehicle|
          {
            id: ["generated_vehicle_#{simulated_vehicle}"],
            depot: depots[simulated_vehicle],
            capacities: vehicles[simulated_vehicle][:capacities].collect{ |key, value| [key, value * vehicles.size / nb_clusters.to_f] }.to_h, #TODO: capacities needs a better way like depots...
            skills: [],
            day_skills: ['0_day_skill', '1_day_skill', '2_day_skill', '3_day_skill', '4_day_skill', '5_day_skill', '6_day_skill'],
            duration: 0,
            total_work_days: 1
          }
        }
      end
      vehicles
    end

    def self.provide_work_day_skill(vehicle, day)
      vehicle.skills.each{ |sk_set|
        sk_set << "work_day_partition_#{OptimizerWrapper::WEEKDAYS[day]}".to_sym
      }
    end

    def self.duplicate_vehicle(vehicle, timewindow, schedule)
      available_days = timewindow&.day_index ? [timewindow.day_index] : (0..6).to_a
      available_days.collect{ |day|
        next unless (schedule[:start]..schedule[:end]).any?{ |day_index| day_index % 7 == day }

        tw = timewindow ? Marshal.load(Marshal.dump(timewindow)) : Models::Timewindow.create({})
        tw.day_index = day
        provide_work_day_skill(vehicle, day)
        new_vehicle = Marshal.load(Marshal.dump(vehicle))
        new_vehicle.timewindow = tw
        new_vehicle.sequence_timewindows = nil
        new_vehicle
      }.compact
    end

    def self.list_vehicles(schedule, vehicles, entity)
      # provides one vehicle per cluster when partitioning with work_day entity
      return vehicles unless entity == :work_day

      vehicle_list = []
      vehicles.each{ |vehicle|
        if vehicle.timewindow
          vehicle_list += duplicate_vehicle(vehicle, vehicle.timewindow, schedule)
        elsif vehicle.sequence_timewindows.size.positive?
          vehicle.sequence_timewindows.each{ |timewindow|
            vehicle_list += duplicate_vehicle(vehicle, timewindow, schedule)
          }
        else
          vehicle_list += duplicate_vehicle(vehicle, nil, schedule)
        end
      }
      vehicle_list.each(&:reset_computed_data)
      vehicle_list
    end

    module ClassMethods
      private

      def compute_day_skills(timewindows)
        if timewindows.nil? || timewindows.empty? || timewindows.any?{ |tw| tw[:day_index].nil? }
          [0, 1, 2, 3, 4, 5, 6].collect{ |avail_day|
            "#{avail_day}_day_skill"
          }
        else
          timewindows.collect{ |tw| tw[:day_index] }.uniq.collect{ |avail_day|
            "#{avail_day}_day_skill"
          }
        end
      end

      def compatible_characteristics?(service_chars, vehicle_chars)
        # Incompatile service and vehicle
        # if the vehicle cannot serve the service due to sticky_vehicle_id
        return false if !service_chars[:v_id].empty? && (service_chars[:v_id] & vehicle_chars[:id]).empty?

        # if the service needs a skill that the vehicle doesn't have
        return false if !(service_chars[:skills] - vehicle_chars[:skills]).empty?

        # if service and vehicle have no matching days
        return false if (service_chars[:day_skills] & vehicle_chars[:day_skills]).empty?

        true # if not, they are compatible
      end

      def collect_data_items_metrics(vrp, cumulated_metrics, options)
        data_items = []
        grouped_objects = {}

        vehicle_units = vrp.vehicles.collect{ |v| v.capacities.to_a.collect{ |capacity| capacity.unit.id } }.flatten.uniq

        decimal = if !vrp.matrices.empty? && !vrp.matrices[0][:distance]&.empty? # If there is a matrix, zip_dataitems will be called so no need to group by lat/lon aggresively
                    {
                      digits: 4, # 3: 111.1 meters, 4: 11.11m, 5: 1.111m  accuracy
                      steps: 5   # digits.steps 4.0: 11.11m, 4.1: 5.6m, 4.2: 3.7m, 4.3: 2.8m, 4.4: 2.2m, 4.5: 1.9m,  4.6: 1.6m, 4.7: 1.4m, 4.8: 1.2m, 4.9=5.0: 1.111m
                    }
                  else
                    {
                      digits: 3, # 3: 111.1 meters, 4: 11.11m, 5: 1.111m  accuracy
                      steps: 8   # digits.steps 3.0: 111.1m, 3.1: 56m, 3.2: 37m, 3.3: 28m, 3.4: 22m, 3.5: 19m,  3.6: 16m, 3.7: 14m, 3.8: 12m, 3.9=4.0: 11.11m
                    }
                  end

        # TODO(0): instead of an overall minimum vehicle duration we can only consider the vehicles
        # that can serve the sub_set that is about to be merged in theory.
        # If there is a small vehicle/bike, serving a specific zone and cannot reach far away
        # regions due to its constraints, then it shouldn't affect the grouping decisions.
        # However, this would be costly to check for each service. Instead, we
        # can have `compatible_vehicles = Array[Model::Vehicle &]` inside each service
        # this would:
        #   - simplify the group_by condition (services of the same location can be grouped only if
        #     they have the same set of `compatible_vehicles`)
        #   - this way we need to check the capacity of the compatible_vehicles only (which means
        #     we can group more)
        #   - the same set can be used
        #       to simplify infeasibility detection (detect_unfeasible_services, etc) a service with an empty
        #         `compatible_vehicles` set can be added to the unassigned list, similarly a vehicle which does not
        #         appear in any services `compatible_vehicles` set is an unneeded vehicle (which might be infeasible)
        #       to handle the capacity logic in zip_cluster
        #       to decrease the complexity of or-tools model by supplying vehicle_indices
        min_vehicle_capacities = Hash[vehicle_units.collect{ |unit_id|
          [
            unit_id.to_sym,
            vrp.vehicles.map{ |v|
              v.capacities.find{ |c| c.unit.id == unit_id }&.limit
            }.compact.min
          ]
        }]
        min_vehicle_capacities[:duration] = vrp.vehicles.collect{ |vehicle|
          if vehicle.sequence_timewindows.any?
            schedule_start = vrp.configuration.schedule.range_indices[:start]
            schedule_end = vrp.configuration.schedule.range_indices[:end]
            total_work_time_in_range = vehicle.total_work_time_in_range(schedule_start, schedule_end)
            total_work_days_in_range = vehicle.total_work_days_in_range(schedule_start, schedule_end)
            (total_work_time_in_range / total_work_days_in_range).round
          else
            vehicle.work_duration
          end
        }.min

        vrp.services.group_by{ |s|
          location =
            if s.activity
              s.activity.point.location
            elsif s.activities.size.positive?
              raise UnsupportedProblemError, 'Clustering does not support services with multiple activities.'
            end

          # we can group services even if they have are in linking relations if everything else is the same
          linked_relation_details =
            if options[:group_points]
              s.relations.select{ |r| LINKING_RELATIONS.include?(r.type) }.collect{ |relation|
                relation.linked_services.collect{ |service|
                  rs_location = service.activity.point.location
                  [relation.type, rs_location.lat, rs_location.lon]
                }
              }.sort
            end

          {
            lat: location.lat.round_with_steps(decimal[:digits], decimal[:steps]),
            lon: location.lon.round_with_steps(decimal[:digits], decimal[:steps]),
            v_id: s[:sticky_vehicle_ids].to_a |
              [vrp.routes.find{ |r| r.mission_ids.include? s.id }&.vehicle_id].compact, # split respects initial routes
            skills: s.skills.to_a.dup,
            day_skills: compute_day_skills(s.activity&.timewindows),
            do_not_group: options[:group_points] ? nil : s.id, # use the ID to prevent grouping
            linked_relation_details: linked_relation_details,
          }
        }.each_with_index{ |(characteristics, sub_set), sub_set_index|
          sub_set.sort_by!(&:visits_number).reverse!

          merge_index = 0
          while sub_set.any?
            merged_quantities = Hash.new(0) # merged_x are not multiplied with visits_number because we want to respect the individual vehicle limits
            unit_quantities = Hash.new(0)

            merge_set = sub_set.take_while.with_index{ |s, i|
              s_duration = s.activity ? s.activity.duration : (s.pickup ? s.pickup.duration : s.delivery.duration)

              next if i.positive? && (
                s.quantities.any?{ |quantity|
                  unit = quantity.unit_id.to_sym
                  next if min_vehicle_capacities[unit].nil?

                  merged_quantities[unit] + quantity.value >= min_vehicle_capacities[unit]
                } || (merged_quantities[:duration] + s_duration >= min_vehicle_capacities[:duration])
              )

              unit_quantities[:visits] += s.visits_number
              cumulated_metrics[:visits] += s.visits_number
              s_setup_duration = s.activity ? s.activity.setup_duration : (s.pickup ? s.pickup.setup_duration : s.delivery.setup_duration)
              duration = ((i.zero? ? s_setup_duration : 0) + s_duration) * s.visits_number
              merged_quantities[:duration] += (i.zero? ? s_setup_duration : 0) + s_duration
              # TODO: If the services are not merged due another reason (for example pickups are at the same location but
              # the deliveries are not), in the case, we assume the worst case and apply the setup_duration to all.
              # However, because of this, clustering might return unbalanced clusters (because the duration is skewed).
              unit_quantities[:duration] += duration
              cumulated_metrics[:duration] += duration
              s.quantities.each{ |quantity|
                next if !vehicle_units.include? quantity.unit.id

                merged_quantities[quantity.unit_id.to_sym] += quantity.value
                unit_quantities[quantity.unit_id.to_sym] += quantity.value * s.visits_number
                cumulated_metrics[quantity.unit_id.to_sym] += quantity.value * s.visits_number
              }
            }
            sub_set = sub_set.drop(merge_set.size)

            # if there are more items left in sub_set this means we stop due to capacity/duration
            # we set characteristics[:do_not_group] = true so that points of this location cannot
            # be merged further in zip_data_items
            characteristics[:do_not_group] ||= true if sub_set.any?

            point = merge_set[0].activity.point
            characteristics[:merged_quantities] = merged_quantities
            characteristics[:matrix_index] = point[:matrix_index] if !vrp.matrices.empty?
            grouped_objects["#{point.id}_#{sub_set_index}_#{merge_index}"] = merge_set
            # TODO : group sticky and skills (in expected characteristics too)
            characteristics[:duration_from_and_to_depot] = [0, 0] if options[:basic_split]
            data_items << [point.location.lat, point.location.lon, "#{point.id}_#{sub_set_index}_#{merge_index}", unit_quantities, characteristics.dup, nil]
            merge_index += 1
          end
        }

        if options[:group_points] && vrp.matrices.any? && vrp.matrices[0][:distance]&.any?
          zip_dataitems(vrp, data_items, grouped_objects, min_vehicle_capacities)
        end

        add_duration_from_and_to_depot(vrp, data_items) if !options[:basic_split]

        [data_items, cumulated_metrics, grouped_objects, collect_related_item_indices(data_items, grouped_objects)]
      end

      def collect_related_item_indices(data_items, grouped_objects)
        related_item_indices = Hash.new { |h, k| h[k] = [] }

        data_items.each_with_index{ |data_item, index|
          sub_set = grouped_objects[data_item[2]]
          # linking_relations are grouped only if the relations are completely compatible/the same,
          # this means all locations of all relations of this sub_set should have been grouped as
          # well, then we need to check only the relations of a single service from each sub_set but
          # we need to make sure that we are checking the same relations in different sub_set. That
          # is why we do select a single service from each sub_set with max_by logic
          service = sub_set.max_by{ |s| s.relations.max_by{ |r| LINKING_RELATIONS.include?(r.type) ? r.id : 0 }&.id.to_i }
          service.relations.select{ |r| LINKING_RELATIONS.include?(r.type) }.each{ |relation|
            related_item_indices[relation] << index
          }
        }

        related_item_indices.group_by{ |k, _v| k.type }.transform_values!{ |v| v.collect!{ |i| i[1] } }
      end

      def zip_dataitems(vrp, items, grouped_objects, min_vehicle_capacities)
        vehicle_characteristics = generate_expected_characteristics(vrp.vehicles)

        compatible_vehicles = Hash.new{}
        items.each{ |data_item|
          compatible_vehicles[data_item[2]] = vehicle_characteristics.collect.with_index{ |veh_char, veh_ind| veh_ind if compatible_characteristics?(data_item[4], veh_char) }.compact
        }

        max_distance = 50 # meters

        c = Ai4r::Clusterers::CompleteLinkageMaxDistance.new

        c.distance_function = lambda do |data_item_a, data_item_b|
          # If there is no vehicle that can serve both points at the same time, make sure they are not merged
          if data_item_a[4][:do_not_group] ||
             data_item_b[4][:do_not_group] ||
             data_item_a[4][:linked_relation_details] != data_item_b[4][:linked_relation_details] ||
             (compatible_vehicles[data_item_a[2]] & compatible_vehicles[data_item_b[2]]).empty? ||
             min_vehicle_capacities.any?{ |unit, limit|
               next if limit.nil?

               data_item_a[4][:merged_quantities][unit] + data_item_b[4][:merged_quantities][unit] > limit
             }
             # see TODO(0) of collect_data_items_metrics about min_vehicle_capacities

            return max_distance + 1
          end

          [
            vrp.matrices[0][:distance][data_item_a[4][:matrix_index]][data_item_b[4][:matrix_index]],
            vrp.matrices[0][:distance][data_item_b[4][:matrix_index]][data_item_a[4][:matrix_index]]
          ].min
        end

        # Cluster points closer than max_distance to eachother
        clusterer = c.build(Ai4r::Data::DataSet.new(data_items: items), max_distance)

        # Correct items and grouped_objects
        clusterer.clusters.each{ |cluster|
          next unless cluster.data_items.size > 1 # Didn't merge any items

          item0 = items[items.index(cluster.data_items[0])]

          cluster.data_items[1..-1].each{ |d_i|
            # Merge grouped_objects
            grouped_objects[item0[2]].concat(grouped_objects.delete(d_i[2]))

            # Merge items
            index_i = items.index(d_i)
            item_i = items[index_i]

            # Transfer the load (duration, visits, quantity, etc.)
            item_i[3].each{ |key, val|
              next if key == :matrix_index

              item0[3][key] += val
            }

            # Merge the characteristics (sticky, skills, days)
            item0[4][:v_id] &= item_i[4][:v_id]
            item0[4][:day_skills] &= item_i[4][:day_skills]
            item0[4][:skills].concat item_i[4][:skills]
            item0[4][:skills].uniq!

            items.delete_at(index_i)
          }
        }
      end

      def add_duration_from_and_to_depot(vrp, data_items)
        if vrp.matrices.empty? || vrp.vehicles.any?{ |v| v.matrix_id.nil? } || vrp.matrices.any?{ |m| m[:time].nil? || m[:time].empty? }
          vehicle_start_locations = vrp.vehicles.select(&:start_point).collect!{ |v| [v.start_point.location.lat, v.start_point.location.lon] }.uniq
          vehicle_end_locations = vrp.vehicles.select(&:end_point).collect!{ |v| [v.end_point.location.lat, v.end_point.location.lon] }.uniq

          locations = data_items.collect{ |point| [point[0], point[1]] }

          tic = Time.now
          log "matrix computation #{vehicle_start_locations.size}x#{locations.size} + #{locations.size}x#{vehicle_end_locations.size}"
          time_matrix_from_depot = vrp.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], vehicle_start_locations, locations).first if vehicle_start_locations.any?
          time_matrix_to_depot = vrp.router.matrix(OptimizerWrapper.config[:router][:url], :car, [:time], locations, vehicle_end_locations).first if vehicle_end_locations.any?
          log "matrix computed in #{(Time.now - tic).round(2)} seconds"

          v_index = {
            from: vrp.vehicles.collect{ |v| vehicle_start_locations.find_index([v.start_point.location.lat, v.start_point.location.lon]) if v.start_point },
            to: vrp.vehicles.collect{ |v| vehicle_end_locations.find_index([v.end_point.location.lat, v.end_point.location.lon]) if v.end_point }
          }

          data_items.each_with_index{ |point, p_index|
            point[4][:duration_from_and_to_depot] = []

            vrp.vehicles.each_with_index{ |_vehicle, v_i|
              duration_from = time_matrix_from_depot[v_index[:from][v_i]][p_index] if v_index[:from][v_i]
              duration_to = time_matrix_to_depot[p_index][v_index[:to][v_i]] if v_index[:to][v_i]

              point[4][:duration_from_and_to_depot] << (duration_from.to_f + duration_to.to_f) # TODO: investigate why division by vehicle.router_options[:speed_multiplier] detoriarates the performance of periodic
            }
          }
        else
          locations = data_items.collect{ |point| point[4][:matrix_index] }

          data_items.each{ |point| point[4][:duration_from_and_to_depot] = [] }

          vrp.vehicles.each{ |v|
            matrix = vrp.matrices.find{ |m| m.id == v.matrix_id }[:time]
            time_matrix_from_depot = Helper.unsquared_matrix(matrix, [v.start_point.matrix_index], locations) if v.start_point
            time_matrix_to_depot = Helper.unsquared_matrix(matrix, locations, [v.end_point.matrix_index]) if v.end_point

            data_items.each_with_index{ |point, p_index|
              point[4][:duration_from_and_to_depot] << (v.start_point ? time_matrix_from_depot[0][p_index].to_f : 0.0) + (v.end_point ? time_matrix_to_depot[p_index][0].to_f : 0.0)
            }
          }
        end
      end

      def generate_expected_characteristics(vehicles)
        vehicles.collect{ |v|
          tw = [v.timewindow || v.sequence_timewindows].flatten.compact
          {
            id: [v.id],
            skills: v.skills.flatten.uniq, # TODO : improve case with alternative skills. Current implementation collects all skill sets into one
            day_skills: compute_day_skills(tw)
          }
        }
      end

      # Adjust cluster if they are disparate - only called when entity == :work_day
      def adjust_clusters(clusters, limits, cut_symbol, centroids, data_items)
        clusters.each_with_index{ |_cluster, index|
          centroids[index] = data_items[centroids[index]]
        }
        clusters.each_with_index{ |cluster, index|
          count = 0
          cluster.data_items.sort_by!{ |data| Helper.flying_distance(data, centroids[index]) }
          cluster.data_items.each{ |data|
            count += data[3][cut_symbol]
            next if count <= limits || centroids.include?(data)

            c = find_cluster(clusters, cluster, cut_symbol, data, limits)
            next if c.nil?

            cluster.data_items.delete(data)
            c.data_items.insert(c.data_items.size, data)
            count -= data[3][cut_symbol]
          }
        }
      end

      # Find the nearest cluster to add data_to_insert - because the other is full
      def find_cluster(clusters, original_cluster, cut_symbol, data_to_insert, limit)
        c = nil
        dist = 2**32
        clusters.each{ |cluster|
          next if cluster == original_cluster

          cluster.data_items.each{ |data|
            next unless dist > Helper.flying_distance(data, data_to_insert) && cluster.data_items.collect{ |data_item| data_item[3][cut_symbol] }.sum < limit &&
                        cluster.data_items.all?{ |d| data_to_insert[5].nil? || d[5] && (data_to_insert[5] & d[5]).size >= d[5].size }

            dist = Helper.flying_distance(data, data_to_insert)
            c = cluster
          }
        }

        c
      end

      def remove_from_upper(graph, node, symbol, value_to_remove)
        if graph.has_key?(node)
          graph[node][:unit_metrics][symbol] -= value_to_remove
          remove_from_upper(graph, graph[node][:parent], symbol, value_to_remove)
        end
      end

      def tree_leafs(graph, node)
        if node.nil?
          [nil]
        elsif (graph[node][:level]).zero?
          [node]
        else
          [tree_leafs(graph, graph[node][:left]), tree_leafs(graph, graph[node][:right])]
        end
      end

      def tree_leafs_delete(graph, node)
        returned =
          if node.nil?
            []
          elsif (graph[node][:level]).zero?
            [node]
          else
            [tree_leafs(graph, graph[node][:left]), tree_leafs(graph, graph[node][:right])]
          end
        graph.delete(node)
        returned
      end

      def centroid_limits(vrp, nb_clusters, cumulated_metrics, cut_symbol, entity)
        limits = []

        if entity == :vehicle && vrp.schedule? && vrp.configuration.schedule.range_indices
          r_start = vrp.configuration.schedule.range_indices[:start]
          r_end = vrp.configuration.schedule.range_indices[:end]

          total_work_time = vrp.total_work_time.to_f

          vrp.vehicles.each{ |vehicle|
            limits << {
                        limit: cumulated_metrics[cut_symbol].to_f * (vehicle.total_work_time_in_range(r_start, r_end) / total_work_time),
                        total_work_time: vehicle.total_work_time_in_range(r_start, r_end),
                        total_work_days: vehicle.total_work_days_in_range(r_start, r_end)
                      }
          }
        else
          limits = { limit: cumulated_metrics[cut_symbol] / nb_clusters }
        end
        limits
      end

      def add_corresponding_entity_skills(entity, vrp)
        return vrp unless entity

        case entity
        when :vehicle
          vrp.services.each{ |service|
            service.skills.insert(0, "vehicle_partition_#{vrp.vehicles.first.id}".to_sym)
          }
          vrp.vehicles.each{ |v|
            # assumes vehicle.skills is an array of arrays
            v.skills.each{ |set| set << "vehicle_partition_#{vrp.vehicles.first.id}".to_sym }
          }
        when :work_day
          vehicle_id_in_skills = vrp.services.any?{ |s| s.skills.include?(vrp.vehicles.first.id) }
          cluster_day = (vrp.vehicles.first.timewindow || vrp.vehicles.first.sequence_timewindows.first).day_index
          day_skill = OptimizerWrapper::WEEKDAYS[cluster_day]
          vrp.services.each{ |service|
            service.skills.insert(vehicle_id_in_skills ? 1 : 0, "work_day_partition_#{day_skill}".to_sym)
          }
        end

        vrp
      end
    end

    extend ClassMethods
  end
end
