# Copyright © Mapotempo, 2018
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

require './lib/interpreters/split_clustering.rb'
require './lib/clusterers/balanced_kmeans.rb'
require './lib/tsp_helper.rb'

module Interpreters
  class Assemble

    def self.build_incompatibility_set(vrp)
      skills = vrp.vehicles.collect{ |vehicle| vehicle[:skills] }
      skills.each{ |skill_1|
        skills.each{ |skill_2|
          if skill_1 != skill_2 && !(skill_1 & skill_2).empty?
            skill_first = skill_1
            skill_second = skill_2
            next if (skill_first & skill_second).size == skill_first.size
            skills.delete(skill_first)
            skill_first |= skill_second
            skills << skill_first
            skills.delete(skill_second)
          end
        }
      }
      skills
    end

    def self.kmeans(services_vrps, cut_symbol = :duration)
      all_vrps = services_vrps.collect{ |service_vrp|
        vrp = service_vrp[:vrp]
        nb_clusters = vrp.vehicles.size

        # Split using balanced kmeans
        if vrp.services.all?{ |service| service[:activity] }
          unit_symbols = vrp.units.collect{ |unit| unit.id.to_sym } << :duration

          cumulated_metrics = {}

          unit_symbols.map{ |unit| cumulated_metrics[unit] = 0 }

          data_items = []

          vrp.points.each{ |point|
            unit_quantities = {}
            unit_symbols.each{ |unit| unit_quantities[unit] = 0 }
            related_services = vrp.services.select{ |service| service[:activity][:point_id] == point[:id] }
            related_services.each{ |service|
              unit_quantities[:duration] += service[:activity][:duration]
              cumulated_metrics[:duration] += service[:activity][:duration]
            }

            next if related_services.empty?
            related_services.each{ |related_service|
              if related_service[:sticky_vehicle_ids] && related_service[:skills] && !related_service[:skills].empty?
                data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, related_service[:sticky_vehicle_ids], related_service[:skills]]
              elsif related_service[:sticky_vehicle_ids] && related_service[:skills] && related_service[:skills].empty?
                  data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, related_service[:sticky_vehicle_ids], nil]
              elsif related_service[:skills] && !related_service[:skills].empty? && !related_service[:sticky_vehicle_ids]
                data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, related_service[:skills]]
              else
                data_items << [point.location.lat, point.location.lon, point.id, unit_quantities, nil, nil]
              end
            }
          }

          start_timer = Time.now
          # Consider only one sticky vehicle
          centroid_indices = []
          if data_items.any?{ |data| data[4] }
            vrp.vehicles.each{ |vehicle|
              data = data_items.find{ |data|
                data[4] && data[4].include?(vehicle[:id])
              }
              centroid_indices << data_items.index(data)
            }
          else
            centroid_indices = vrp[:preprocessing_kmeans_centroids] if vrp[:preprocessing_kmeans_centroids] # really ?
          end

          clusters = SplitClustering::kmeans_process(centroid_indices, 500, 50, nb_clusters, data_items, unit_symbols, cut_symbol, cumulated_metrics[cut_symbol] / nb_clusters, vrp, build_incompatibility_set(vrp))
          end_timer = Time.now

          vehicle_list = []
          vrp.vehicles.each{ |vehicle|
            tw = Marshal::load(Marshal.dump(vehicle[:timewindow]))
            new_vehicle = Marshal::load(Marshal.dump(vehicle))
            new_vehicle[:timewindow] = tw
            vehicle_list << new_vehicle
          }
          sub_problem = SplitClustering::create_sub_pbs(service_vrp, vrp, clusters)
          clusters.each_with_index{ |cluster, index|
            data_sticky = cluster.data_items.collect{ |data| data[4] }.compact
            data_skills = cluster.data_items.collect{ |data| data[5] }.compact
            sub_problem[index][:vrp][:vehicles] = if !data_sticky.empty?
              [vehicle_list.find{ |vehicle| vehicle[:id] == data_sticky.flatten.first }].compact
            elsif data_sticky.empty? && !data_skills.empty? && vehicle_list.any?{ |vehicle| vehicle[:skills] && !vehicle[:skills].first.empty? }
              [vehicle_list.find{ |vehicle| vehicle[:skills] && !vehicle[:skills].first.empty? && ([data_skills.flatten.first] & (vehicle[:skills].first)).size > 0 }]
            else
              [vehicle_list.last] # TODO : function that return the best vehicle for this cluster
            end
            vehicle_list -= sub_problem[index][:vrp][:vehicles]
          }

          sub_problem
        else
          puts "split hierarchical not available when services have activities"
          [vrp]
        end
      }.flatten
    end

    def self.assemble_heuristic(true_services_vrps, block = nil)
      services_vrps = Marshal.load(Marshal.dump(true_services_vrps))

      all_vrps = kmeans(services_vrps)
      all_vrps.each{ |service_vrp|
        service_vrp[:vrp].resolution_duration = service_vrp[:vrp].resolution_duration / all_vrps.size
        service_vrp[:vrp].resolution_minimum_duration = service_vrp[:vrp].resolution_minimum_duration / all_vrps.size if service_vrp[:vrp].resolution_minimum_duration
        service_vrp[:vrp].restitution_allow_empty_result = true
        service_vrp[:vrp].preprocessing_first_solution_strategy = ['local_cheapest_insertion']
        service_vrp[:vrp].vehicles.each{ |vehicle| vehicle[:free_approach] = true }
      }

      results = all_vrps.collect.with_index{ |service_vrp, indice|
        block.call(:ortools, indice + 1, nil, "process #{indice + 1}/#{all_vrps.size} - " + 'run optimization', nil, nil, nil) if block
        OptimizerWrapper.solve([service_vrp])
      }

      services_vrps = services_vrps.collect{ |service_vrp|
        routes = results.collect{ |result|
          result[:routes].collect{ |route|
            {
              vehicle: {
                id: route[:vehicle_id]
              },
              mission_ids: route[:activities].select{ |activity| activity[:service_id] || activity[:rest_id] }.collect{ |activity|
                activity[:service_id] || activity[:rest_id]
              }
            }
          } if result
        }.flatten.compact
        service_vrp[:vrp].routes = routes
        service_vrp[:vrp].resolution_duration = service_vrp[:vrp].resolution_duration / all_vrps.size
        service_vrp[:vrp].resolution_minimum_duration = service_vrp[:vrp].resolution_minimum_duration / all_vrps.size if service_vrp[:vrp].resolution_minimum_duration
        service_vrp[:vrp].preprocessing_first_solution_strategy = ['local_cheapest_insertion']

        service_vrp
      }.flatten

      services_vrps
    end

    def self.assemble_candidate(services_vrps)
      services_vrps.any?{ |service_vrp|
        service_vrp[:vrp].vehicles.size > 1 &&
        (service_vrp[:vrp].vehicles.all?(&:force_start) || service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle[:shift_preference] == 'force_start' }) &&
        service_vrp[:vrp].vehicles.all?{ |vehicle| vehicle.cost_late_multiplier.nil? || vehicle.cost_late_multiplier == 0 } &&
        service_vrp[:vrp].services.all?{ |service| service.activity.late_multiplier.nil? || service.activity.late_multiplier == 0 } &&
        service_vrp[:vrp].services.any?{ |service| service.activity.timewindows && !service.activity.timewindows.empty? }
      }
    end

  end
end
