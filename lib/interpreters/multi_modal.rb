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

require 'rgeo/geo_json'

module Interpreters
  class MultiModal
    def initialize(vrp, selected_service)
      @original_vrp = Marshal.load(Marshal.dump(vrp))
      @selected_service = selected_service
      @sub_service_ids = []
      @associated_table = {}
      @convert_table = {}
    end

    def generate_isolines
      @original_vrp.subtours.collect{ |tour|
        tour.transmodal_stops.collect{ |stop|
          isoline = JSON.parse(OptimizerWrapper.router.isoline(OptimizerWrapper.config[:router][:url], tour.router_mode, (tour.time_bounds ? :time : :distance), stop.location.lat, stop.location.lon, (tour.time_bounds || tour.distance_bounds)))
          next unless isoline

          {
            id: tour[:id],
            stop_id: stop.id,
            polygon: isoline['features'].first['geometry']
          }
        }
      }.flatten
    end

    def select_services_from_isolines(isolines)
      isolines.each{ |isoline|
        current_geom = RGeo::GeoJSON.decode(isoline[:polygon].to_json, json_parser: :json)
        isoline[:inside_points] = @original_vrp.points.select{ |current_point|
          current_geom.contains?(RGeo::Cartesian.factory.point(current_point.location.lon, current_point.location.lat))
        }
        isoline[:inside_points].each{ |current_point|
          if !@associated_table.nil? && @associated_table.has_key?(current_point.id)
            @associated_table[current_point.id] += [isoline[:stop_id]]
            @original_vrp.points.find{ |local_point| local_point.id == current_point.id }[:associated_stops] += [isoline[:stop_id]]
          else
            @associated_table[current_point.id] = [isoline[:stop_id]]
            @original_vrp.points.find{ |local_point| local_point.id == current_point.id }[:associated_stops] = [isoline[:stop_id]]
          end
        }
      }
    end

    def propagate_associated_stops
      @original_vrp.services.each{ |service|
        service.activity.point.associated_stops = @original_vrp.points.find{ |point| point.id == service.activity.point_id }[:associated_stops]
      }
    end

    def generate_skills_patterns(isolines)
      patterns = isolines.collect{ |isoline| [isoline[:id]] }
      isolines.each{ |isoline|
        isolines.each{ |iso_second|
          next if iso_second[:id] == isoline[:id]

          next if (isoline[:inside_points] & iso_second[:inside_points]).empty?

          pattern_first = patterns.find{ |pattern| pattern.include? isoline[:id] }
          pattern_second = patterns.find{ |pattern| pattern.include? iso_second[:id] }

          next if (pattern_first & pattern_second).size == pattern_first.size

          patterns.delete(pattern_first)
          pattern_first |= pattern_second
          patterns << pattern_first
          patterns.delete(pattern_second)
        }
      }
      patterns.collect{ |pattern|
        pattern.collect{ |iso_id|
          isolines.find{ |isoline| isoline[:id] == iso_id }[:stop_id]
        }
      }
    end

    def generate_subproblems(patterns)
      problem_size = @original_vrp.services.size

      patterns.collect{ |pattern|
        sub_vrp = Marshal.load(Marshal.dump(@original_vrp))
        sub_vrp.id = pattern
        sub_vrp.relations = @original_vrp.relations
        sub_vrp.points = []
        sub_vrp.services.select!{ |service|
          (pattern & @associated_table[service.activity.point.id]).size == @associated_table[service.activity.point.id].size if @associated_table.has_key?(service.activity.point.id)
        }
        sub_vrp.points += pattern.collect{ |transmodal_id|
          Marshal.load(Marshal.dump(@original_vrp.points.select{ |point| point.id == transmodal_id }))
        }.flatten
        quantities = {}
        sub_vrp.units.each{ |unit|
          quantities[unit.id] = 0
        }
        sub_vrp.services.each{ |service|
          service.quantities.each{ |quantity|
            quantities[quantity.unit_id] += quantity.value
          }
        }

        sub_vrp.configuration = {
          preprocessing: {
            prefer_short_segment: true
          },
          resolution: {
            duration: @original_vrp.resolution_duration ? @original_vrp.resolution_duration / problem_size * sub_vrp.services.size : nil,
            minimum_duration: @original_vrp.resolution_minimum_duration ? @original_vrp.resolution_minimum_duration / problem_size * sub_vrp.services.size : (@original_vrp.resolution_initial_time_out ? @original_vrp.resolution_initial_time_out / problem_size * sub_vrp.services.size : nil)
          }.delete_if{ |_k, v| v.nil? }
        }

        sub_vrp.vehicles = []
        sub_vrp.subtours = []

        vehicle_skills = @original_vrp.vehicles.flat_map{ |vehicle|
          vehicle.skills.collect{ |alternative| alternative }
        }.compact.uniq

        max_capacities = {}
        sub_vrp.units.each{ |unit|
          max_capacities[unit.id] = 0
        }
        @original_vrp.subtours.select{ |sub_tour| !sub_tour[:transmodal_stops].empty? && !pattern.empty? && !(sub_tour[:transmodal_stops].collect{ |stop| stop.id } & pattern).empty? }.each{ |sub_tour|
          duplicate_vehicles = sub_tour.capacities.collect{ |capacity| (capacity.limit > 0) ? (quantities[capacity.unit.id].to_f / capacity.limit).ceil : 1 }.max || 1
          (sub_tour[:transmodal_stops].collect{ |stop| stop.id } & pattern).each{ |transmodal_id|
            transmodal_point = sub_vrp.points.find{ |point| point.id == transmodal_id }
            sub_vrp.vehicles += (1..duplicate_vehicles).collect{ |index|
              if vehicle_skills && !vehicle_skills.empty?
                vehicle_skills.collect{ |alternative|
                  Models::Vehicle.new(
                    id: "subtour_#{alternative.join('-')}_#{transmodal_id}_#{index}",
                    router_mode: sub_tour.router_mode,
                    router_dimension: sub_tour.router_dimension,
                    speed_multiplier: sub_tour.speed_multiplier,
                    start_point: transmodal_point,
                    end_point: transmodal_point,
                    skills: [sub_vrp[:points].collect{ |point| point[:associated_stops].include?(transmodal_id) ? point[:associated_stops].join('_') : nil }.compact.uniq + alternative],
                    capacities: sub_tour.capacities,
                    duration: sub_tour.duration
                  )
                }
              else
                Models::Vehicle.new(
                  id: "subtour_#{transmodal_id}_#{index}",
                  router_mode: sub_tour.router_mode,
                  router_dimension: sub_tour.router_dimension,
                  speed_multiplier: sub_tour.speed_multiplier,
                  start_point: transmodal_point,
                  end_point: transmodal_point,
                  skills: [sub_vrp[:points].collect{ |point| point[:associated_stops].include?(transmodal_id) ? point[:associated_stops].join('_') : nil }.compact.uniq],
                  capacities: sub_tour.capacities,
                  duration: sub_tour.duration
                )
              end
            }.flatten
          }
          sub_tour.capacities.each{ |capacity|
            max_capacities[capacity.unit.id] = [max_capacities[capacity.unit.id], capacity.limit].max
          }
        }

        sub_vrp.services.collect!{ |service|
          sub_vrp.points << service.activity.point
          service[:initial_id] = service.id
          @sub_service_ids << service.id
          service.skills += [service.activity.point.associated_stops.join('_')] if !service.activity.point.associated_stops.empty?
          round = service.quantities.select{ |quantity| max_capacities[quantity.unit.id]&.positive? }.collect{ |quantity| ((quantity.value || 0) / max_capacities[quantity.unit.id]) }.max || 1
          services = (1..round.ceil).collect{ |index|
            duplicated_service = Marshal.load(Marshal.dump(service))
            duplicated_service.id = "#{duplicated_service.id}_#{index}"
            duplicated_service.quantities.select{ |quantity| max_capacities[quantity.unit.id]&.positive? }.each{ |quantity|
              if round.ceil == 1 || index != round.ceil
                quantity.value /= [round, 1].max
              else
                quantity.value -= (index - 1) * quantity.value / round
              end
            }
            duplicated_service
          }
          services
        }.flatten!
        sub_vrp.points.uniq!
        sub_vrp
      }.compact.delete_if{ |sub_vrp| sub_vrp.services.empty? }
    end

    def solve_subproblems(subvrps)
      subvrps.collect{ |sub_vrp|
        vrp_service = {
          service: @selected_service,
          vrp: sub_vrp
        }
        log "Solve #{sub_vrp.id} sub problem"
        result = OptimizerWrapper.solve([vrp_service])
        result[:routes].each{ |route|
          @convert_table[route[:vehicle_id]] = route[:activities]
          route[:activities].each{ |activity|
            if activity[:service_id]
              activity[:service_id] = sub_vrp.services.find{ |service| service.id == activity[:service_id] }[:initial_id]
            end
          }
        }
        result
      }
    end

    def override_original_vrp(subresults)
      replacement_services = subresults.collect{ |subresult|
        subresult[:routes].collect{ |route|
          next unless route[:activities].size > 2

          service = Models::Service.new(
            id: route[:vehicle_id],
            activity: {
              point: @original_vrp.points.find{ |point| point.id == route[:activities].first[:point_id] },
              duration: (route[:activities][-2][:departure_time] + route[:activities].last[:travel_time]) - (route[:activities][1][:begin_time] - route[:activities][1][:travel_time])
              # Timewindows ?
            },
            skills: route[:activities][1..-2].collect{ |activity|
              @original_vrp.services.find{ |original_service| original_service.id == activity[:service_id] }.skills
            }.flatten.compact.uniq,
            quantities: route[:activities][-2][:detail][:quantities].collect{ |quantity|
              {
                unit: @original_vrp.units.find{ |unit| unit.id == quantity[:unit] },
                value: quantity[:current_load]
              }
            }
          )
          service
        }
      }.flatten.compact
      new_vrp = Marshal.load(Marshal.dump(@original_vrp))
      new_vrp.services.delete_if{ |service| @sub_service_ids.include?(service.id) } if @sub_service_ids
      new_vrp.services += replacement_services
      new_vrp.subtours = []

      vrp_service = {
        service: @selected_service,
        vrp: new_vrp
      }
      OptimizerWrapper.solve([vrp_service])
    end

    def rebuild_entire_route(_subresults, result)
      result[:routes] = result[:routes].each{ |route|
        last_id = nil
        route[:activities] = route[:activities].collect{ |activity|
          sub_activities = [activity]
          if activity[:service_id] && @convert_table && @convert_table[activity[:service_id]]
            sub_activities = if @convert_table[activity[:service_id]].first[:point_id] == last_id
                               @convert_table[activity[:service_id]][1..-1]
                             else
                               @convert_table[activity[:service_id]]
                             end
            last_id = @convert_table[activity[:service_id]].last[:point_id]
            activity
          end
          sub_activities
        }.flatten
      }
      result
    end

    def multimodal_routes
      if @original_vrp.points.none?{ |point| point.location.nil? }
        isolines = generate_isolines
        select_services_from_isolines(isolines)
        propagate_associated_stops
        skills_patterns = generate_skills_patterns(isolines)
        subvrps = generate_subproblems(skills_patterns)
        subresults = solve_subproblems(subvrps)
        result = override_original_vrp(subresults)
        rebuild_entire_route(subresults, result)
      end
    end
  end
end
