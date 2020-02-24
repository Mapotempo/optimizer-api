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

require 'json'
require 'tempfile'

module Wrappers
  class Vroom < Wrapper
    def initialize(hash = {})
      super(hash)
      @exec_vroom = hash[:exec_vroom] || '../vroom/bin/vroom'
    end

    def solver_constraints
      super + [
        :assert_vehicles_objective,
        :assert_vehicles_only_one,
        :assert_vehicles_start_or_end,
        :assert_vehicles_no_end_time_or_late_multiplier,
        :assert_services_no_capacities,
        :assert_services_no_skills,
        :assert_services_no_timewindows,
        :assert_services_no_priority,
        :assert_no_shipments,
        :assert_matrices_only_one,
        :assert_correctness_provided_matrix_indices,
        :assert_correctness_matrices_vehicles_and_points_definition,
        :assert_one_vehicle_only_or_no_sticky_vehicle,
        :assert_no_relations,
        :assert_vehicles_no_duration_limit,
        :assert_no_value_matrix,
        :assert_no_routes,
        :assert_points_same_definition,
        :assert_at_least_one_mission,
        :assert_no_distance_limitation,
        :assert_no_subtours,
        :assert_no_planning_heuristic,
        :assert_no_evaluation,
        :assert_no_first_solution_strategy,
        :assert_solver,
        :assert_no_partitions,
      ]
    end

    def solve_synchronous?(_vrp)
      true
    end

    def solve(vrp, job = nil, _thread_proc = nil)
      if vrp.points.empty? || vrp.services.empty?
        return {
          cost: 0,
          solvers: ['vroom'],
          elapsed: 0, # ms
          routes: [],
          unassigned: []
        }
      end

      points = Hash[vrp.points.collect{ |point| [point.id, point] }]

      vehicle = vrp.vehicles.first
      vehicle_have_start = !vehicle.start_point_id.nil?
      vehicle_have_end = !vehicle.end_point_id.nil?

      tic = Time.now
      result = run_vroom(vrp.vehicles, vrp.services, points, vrp.matrices, [:time, :distance], vrp.preprocessing_prefer_short_segment, job)
      elapsed_time = (Time.now - tic) * 1000 # ms

      return if !result

      tour = result['routes'][0]['steps'].collect{ |step| step['job'] }.compact
      log tour.inspect

      cost = (result['summary']['cost']) + vehicle.cost_fixed
      previous = vehicle_have_start ? vehicle.start_point.matrix_index : nil
      activities = ([vehicle_have_start ? {
        point_id: vehicle.start_point.id,
        detail: vehicle.start_point.location ? {
          lat: vehicle.start_point.location.lat,
          lon: vehicle.start_point.location.lon
        } : nil
      }.delete_if{ |_k, v| !v } : nil] +
      tour.collect{ |i|
        point_index = vrp.services[i].activity.point[:matrix_index]
        point = vrp.points.select{ |point| point[:id] == vrp.services[i].activity.point[:id] }[0]
        service = vrp.services[i]
        current_activity = {
          service_id: service.id,
          point_id: point.id,
          travel_time: ((previous && point_index && vrp.matrices[0][:time]) ? vrp.matrices[0][:time][previous][point_index] : 0),
          travel_distance: ((previous && point_index && vrp.matrices[0][:distance]) ? vrp.matrices[0][:distance][previous][point_index] : 0),
          detail: build_detail(service, service.activity, point, nil, vehicle)
#          travel_distance 0,
#          travel_start_time 0,
#          waiting_duration 0,
#          arrival_time 0,
#          duration 0,
#          pickup_shipments_id [:id0:],
#          delivery_shipments_id [:id0:]
        }
        previous = point_index
        current_activity
      }.compact +
      [vehicle_have_end ? {
        point_id: vehicle.end_point.id,
        detail: vehicle.end_point.location ? {
          lat: vehicle.end_point.location.lat,
          lon: vehicle.end_point.location.lon
        } : nil
      }.delete_if{ |_k, v| !v } : nil]).compact

      rests = vehicle.rests
      if vehicle.timewindow&.start
        rests.sort_by!{ |rest| rest.timewindows[0].end ? -rest.timewindows[0].end : -2**31 }.each{ |rest|
          time = vehicle.timewindow.start + vrp.services[tour[0]].activity.duration
          i = pos_rest = 0
          if vehicle_have_start
            time += vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.time[vehicle.start_point.matrix_index][vrp.services[tour[0]].activity.point.matrix_index]
            pos_rest += 1
          end
          if !rest.timewindows[0].end || time < rest.timewindows[0].end
            pos_rest += 1
            while i < tour.size - 1 && (!rest.timewindows[0].end || (time += vrp.matrices.find{ |matrix| matrix.id == vehicle.matrix_id }.time[vrp.services[tour[i]].activity.point.matrix_index][vrp.services[tour[i + 1]].activity.point.matrix_index] + vrp.services[tour[i + 1]].activity.duration) < rest.timewindows[0].end)
              i += 1
            end
            pos_rest += i
          end
          activities.insert(pos_rest, rest_id: rest.id)
        }
      else
        rests.each{ |rest| activities.insert(vehicle_have_end ? -2 : -1, rest_id: rest.id) }
      end

      {
        cost: cost,
        solvers: ['vroom'],
        elapsed: elapsed_time, # ms
#        total_travel_distance: 0,
#        total_travel_time: 0,
#        total_waiting_time: 0,
#        start_time: 0,
#        end_time: 0,
        routes: [{
          vehicle_id: vehicle.id,
          activities: activities
        }],
        unassigned: []
      }
    end

    private

    def build_detail(_job, activity, point, _day_index, vehicle)
      {
        lat: point&.location&.lat,
        lon: point&.location&.lon,
        duration: activity.duration,
        router_mode: vehicle ? vehicle.router_mode : nil,
        speed_multiplier: vehicle ? vehicle.speed_multiplier : nil
      }.delete_if{ |_k, v| v.nil? }
    end

    def run_vroom(vehicles, services, points, matrices, dimensions, prefer_short, job)
      input = Tempfile.new('optimize-vroom-input', @tmp_dir)
      problem = { vehicles: [], jobs: [], matrix: [] }
      vehicle = vehicles.first
      problem[:vehicles] << {
        id: 0,
        start_index: vehicle.start_point_id ? points[vehicle.start_point_id].matrix_index : nil,
        end_index: vehicle.end_point_id ? points[vehicle.end_point_id].matrix_index : nil
      }.delete_if{ |_k, v| v.nil? }
      problem[:jobs] = services.collect.with_index{ |service, index|
        [{
          id: index,
          location_index: points[service.activity.point_id].matrix_index
        }]
      }.flatten

      matrix_indices = (problem[:jobs].collect{ |jb| jb[:location_index] } + problem[:vehicles].collect{ |vec| [vec[:start_index], vec[:end_index]].uniq.compact }.flatten).uniq.sort
      matrix = matrices.find{ |current_matrix| current_matrix.id == vehicle.matrix_id }
      size_matrix = matrix_indices.size

      # Index relabeling
      problem[:jobs].each{ |jb|
        jb[:location_index] = matrix_indices.find_index{ |ind| ind == jb[:location_index] }
      }
      problem[:vehicles].each{ |vec|
        vec[:start_index] = matrix_indices.find_index{ |ind| ind == vec[:start_index] } if vec[:start_index]
        vec[:end_index] = matrix_indices.find_index{ |ind| ind == vec[:end_index] } if vec[:end_index]
        if vec[:end_index].nil? && vec[:start_index].nil?
          vec[:start_index] = size_matrix # Add an auxialiary node if there is no start or end depot for the vehicle
        end
      }

      agglomerate_matrix = vehicle.matrix_blend(matrix, matrix_indices, dimensions, cost_time_multiplier: vehicle.cost_time_multiplier, cost_distance_multiplier: vehicle.cost_distance_multiplier)
      if prefer_short
        coeff = 20.0 / 100.0
        (0..size_matrix - 1).each{ |i|
          (0..size_matrix - 1).each{ |j|
            agglomerate_matrix[i][j] = (agglomerate_matrix[i][j] + coeff * Math.sqrt(agglomerate_matrix[i][j])).round
          }
        }
      else
        (0..size_matrix - 1).each{ |i|
          (0..size_matrix - 1).each{ |j|
            agglomerate_matrix[i][j] = agglomerate_matrix[i][j].round
          }
        }
      end

      if vehicle.start_point_id.nil? && vehicle.end_point_id.nil?
        # If there is no start or end depot for the vehicle
        # set the distance of the auxiliary node to all other nodes as zero
        agglomerate_matrix << Array.new(size_matrix, 0)
        agglomerate_matrix.each{ |row| row << 0 }
      end

      problem[:matrix] = agglomerate_matrix
      input.write(problem.to_json)
      input.close

      output = Tempfile.new('optimize-vroom-output', @tmp_dir)
      output.close

      cmd = "#{@exec_vroom} -i '#{input.path}' -o '#{output.path}'"
      log cmd
      system(cmd)

      unless $CHILD_STATUS.nil?
        if $CHILD_STATUS.exitstatus.zero?
          JSON.parse(File.read(output.path))
        end
      end
    ensure
      input&.unlink
      output&.unlink
    end
  end
end
