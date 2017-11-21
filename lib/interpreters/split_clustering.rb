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

require 'ai4r'
include Ai4r::Data
include Ai4r::Clusterers

module Interpreters
  class SplitClustering

    def initialize(vrp)
      @initial_vrp_duration = vrp.resolution_duration/vrp.vehicles.size if vrp.resolution_duration
      @initial_vrp_time_out = vrp.resolution_initial_time_out/vrp.vehicles.size if vrp.resolution_initial_time_out
      @all_vehicles = vrp.vehicles
      @vehicle_index = 0
      @initial_visits = vrp.services.size
      @homogeneous = homogeneous_vehicles(vrp.vehicles)
    end

    def homogeneous_point(a, b)
      return a.nil? && b.nil? || !a.nil? && !b.nil? && a.location.nil? && b.location.nil? && a.matrix_index == b.matrix_index ||
        !a.nil? && !b.nil? && a.location && b.location && a.location.lat == b.location.lat && a.location.lon == b.location.lon
    end

    def homogeneous_sequence_timewindows(a, b)
      a.all?{ |current_tw| b.find{ |tw| current_tw && tw && current_tw.start == tw.start && current_tw.end == tw.end }}
    end

    def homogeneous_capacities(a, b)
      a.all?{ |current_ct| a && b.find{ |ct| current_ct && ct && current_ct.unit_id == ct.unit_id && current_ct.limit == ct.limit }}
    end

    def homogeneous_vehicles(vehicles)
        vehicles.all? { |vehicle|
          homogeneous_point(vehicle.start_point, vehicles.first.start_point) &&
          homogeneous_point(vehicle.end_point, vehicles.first.end_point) &&
          vehicle.duration == vehicles.first.duration &&
          vehicle.router_mode == vehicles.first.router_mode &&
          vehicle.router_dimension == vehicles.first.router_dimension &&
          vehicle.speed_multiplier_area == vehicles.first.speed_multiplier_area &&
          vehicle.cost_fixed == vehicles.first.cost_fixed &&
          vehicle.cost_distance_multiplier == vehicles.first.cost_distance_multiplier &&
          vehicle.cost_time_multiplier == vehicles.first.cost_time_multiplier &&
          vehicle.cost_waiting_time_multiplier == vehicles.first.cost_waiting_time_multiplier &&
          vehicle.cost_value_multiplier == vehicles.first.cost_value_multiplier &&
          vehicle.cost_late_multiplier == vehicles.first.cost_late_multiplier &&
          vehicle.cost_setup_time_multiplier == vehicles.first.cost_setup_time_multiplier &&
          (vehicle.timewindow.nil? && vehicles.first.timewindow.nil? && vehicle.sequence_timewindows.empty? && vehicles.first.sequence_timewindows.empty? ||
            vehicle.timewindow && vehicles.first.timewindow && vehicle.timewindow.start == vehicles.first.timewindow.start &&
            vehicle.timewindow.end == vehicles.first.timewindow.end) ||
          homogeneous_sequence_timewindows(vehicle.sequence_timewindows, vehicles.first.sequence_timewindows) &&
          homogeneous_capacities(vehicle.capacities, vehicles.first.capacities)
        }
      end

    def split_clusters(services_vrps, job = nil, &block)
      all_vrps = services_vrps.collect{ |services_vrp|
        vrp = services_vrp[:vrp]

        if @homogeneous && vrp.preprocessing_max_split_size && vrp.shipments.size == 0 && @initial_visits > vrp.preprocessing_max_split_size
          if vrp.services.size > vrp.preprocessing_max_split_size && @vehicle_index < @all_vehicles.size
            points = vrp.services.collect.with_index{ |service, index|
              service.activity.point.matrix_index = index
              [service.activity.point.location.lat, service.activity.point.location.lon]
            }

            result_cluster = clustering(vrp, 2)

            sub_first = build_partial_vrp(vrp, result_cluster[0])

            sub_second = build_partial_vrp(vrp, result_cluster[1])

            deeper_search = [{
              service: services_vrp[:service],
              vrp: sub_first
            }, {
              service: services_vrp[:service],
              vrp: sub_second
            }]
            split_clusters(deeper_search, job)
          else
            sub_vrp = Marshal::load(Marshal.dump(vrp))
            sub_vrp.id = Random.new
            unassigned_size = 0
            estimated_sub_size = [((vrp.services.size.to_f / (@initial_visits)).to_f * @all_vehicles.size).to_i, 1].max
            sub_vrp.vehicles = @all_vehicles[@vehicle_index..@vehicle_index + estimated_sub_size - 1].collect{ |vehicle|
              vehicle.matrix_id = nil
              vehicle
            }
            previous_unassigned_size = 0
            loop_index = 0
            begin
              previous_unassigned_size = unassigned_size
              sub_vrp.resolution_initial_time_out = 1000
              sub_vrp.resolution_duration = @initial_vrp_duration * sub_vrp.vehicles.size if @initial_vrp_duration
              result = OptimizerWrapper.solve([{
                service: services_vrp[:service],
                vrp: sub_vrp
              }], job)
              unassigned_size = result && result[:unassigned] && result[:unassigned].size || 0
              if unassigned_size != 0 && previous_unassigned_size != unassigned_size
                loop_index += 1
                sub_vrp.vehicles = @all_vehicles[@vehicle_index..@vehicle_index + estimated_sub_size + loop_index - 1].collect{ |vehicle|
                  vehicle.matrix_id = nil
                  vehicle
                }
              elsif unassigned_size == 0
                to_reduce = result && result[:routes].select{ |route| route[:activities].none?{ |activity|
                  activity[:service_id] || activity[:pickup_shipment_id] || activity[:delivery_shipment_id]
                }}.size || 0
                sub_vrp.vehicles = @all_vehicles[@vehicle_index..@vehicle_index + estimated_sub_size + loop_index - to_reduce - 1]
              end
            end while previous_unassigned_size != unassigned_size && @vehicle_index + loop_index < @all_vehicles.size
            @vehicle_index += sub_vrp.vehicles.size
            sub_vrp.resolution_initial_time_out = @initial_vrp_time_out * sub_vrp.vehicles.size if @initial_vrp_time_out
            {
              service: services_vrp[:service],
              vrp: sub_vrp
            }
          end
        else
          {
            service: services_vrp[:service],
            vrp: vrp
          }
        end
      }.flatten
    rescue => e
      puts e
      puts e.backtrace
      raise
    end

    def clustering(vrp, n)
      vector = vrp.services.collect{ |service|
        [service.id, service.activity.point.location.lat, service.activity.point.location.lon]
      }
      data_set = DataSet.new(data_items: vector.size.times.collect{ |i| [i] })
      c = KMeans.new
      c.set_parameters(max_iterations: 100)
      c.centroid_function = lambda do |data_sets|
        data_sets.collect{ |data_set|
          data_set.data_items.min_by{ |i|
            data_set.data_items.sum{ |j|
              c.distance_function.call(i, j)**2
            }
          }
        }
      end

      c.distance_function = lambda do |a, b|
        a = a[0]
        b = b[0]
        Math.sqrt((vector[a][1] - vector[b][1])**2 + (vector[a][2] - vector[b][2])**2)
      end

      clusterer = c.build(data_set, n)

      result = clusterer.clusters.collect { |cluster|
        cluster.data_items.collect{ |i|
          vector[i[0]][0]
        }
      }
      puts "Split #{vrp.services.size} into #{result[0].size} & #{result[1].size}"
      result
    end

    def build_partial_vrp(vrp, cluster_services)
      sub_vrp = Marshal::load(Marshal.dump(vrp))
      sub_vrp.id = Random.new
      services = vrp.services.select{ |service| cluster_services.include?(service.id) }.compact
      points_ids = services.map{ |s| s.activity.point.id }.uniq.compact
      sub_vrp.rests = vrp.rests.select{ |r| vehicle.rests.map(&:id).include? r.id }
      sub_vrp.services = services
      points = sub_vrp.services.collect.with_index{ |service, i|
        service.activity.point.matrix_index = i
        [service.activity.point.location.lat, service.activity.point.location.lon]
      }
      sub_vrp.points = (vrp.points.select{ |p| points_ids.include? p.id } + vrp.vehicles.collect{ |vehicle| [vehicle.start_point, vehicle.end_point] }.flatten ).compact.uniq
      sub_vrp
    end
  end
end
