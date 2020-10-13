# Copyright © Mapotempo, 2019
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

require './lib/hull.rb'
module OutputHelper
  # To output clusters generated
  class Clustering
    def self.generate_files(all_service_vrps, two_stages = false, job = nil)
      vrp_name = all_service_vrps.first[:vrp].name
      file_name = ('generated_clusters' + '_' + [vrp_name, job, Time.now.strftime('%H:%M:%S')].compact.join('_')).parameterize

      polygons = []
      csv_lines = [['id', 'lat', 'lon', 'cluster', 'vehicles_ids', 'vehicle_tw_if_only_one']]
      all_service_vrps.each_with_index{ |service_vrp, cluster_index|
        polygons << collect_hulls(service_vrp) # unless service_vrp[:vrp].services.empty? -----> possible to get here if cluster empty ??
        service_vrp[:vrp].services.each{ |service|
          csv_lines << csv_line(service_vrp[:vrp], service, cluster_index, two_stages)
        }
      }

      Api::V01::APIBase.dump_vrp_dir.write(file_name + '_geojson', {
        type: 'FeatureCollection',
        features: polygons.compact
      }.to_json)

      csv_string = CSV.generate do |out_csv|
        csv_lines.each{ |line| out_csv << line }
      end

      Api::V01::APIBase.dump_vrp_dir.write(file_name + '_csv', csv_string)

      log 'Clusters saved: ' + file_name, level: :debug
      file_name
    end

    def self.collect_hulls(service_vrp)
      vector = service_vrp[:vrp].services.collect{ |service|
        [service.activity.point.location.lon, service.activity.point.location.lat]
      }
      hull = Hull.get_hull(vector)
      return nil if hull.nil?

      unit_objects = service_vrp[:vrp].units.collect{ |unit|
        {
          unit_id: unit.id,
          value: service_vrp[:vrp].services.collect{ |service|
            service_quantity = service.quantities.find{ |quantity| quantity.unit_id == unit.id }
            service_quantity&.value || 0
          }.reduce(&:+)
        }
      }
      duration = service_vrp[:vrp][:services].group_by{ |s| s.activity.point_id }.map{ |_point_id, ss|
        first = ss.min_by{ |s| -s.visits_number }
        duration = first.activity.setup_duration * first.visits_number + ss.map{ |s| s.activity.duration * s.visits_number }.sum
      }.sum
      {
        type: 'Feature',
        properties: Hash[unit_objects.collect{ |unit_object| [unit_object[:unit_id].to_sym, unit_object[:value]] } + [[:duration, duration]] + [[:vehicle, (service_vrp[:vrp].vehicles.size == 1) ? service_vrp[:vrp].vehicles.first&.id : nil]]],
        geometry: {
          type: 'Polygon',
          coordinates: [hull + [hull.first]]
        }
      }
    end

    def self.csv_line(vrp, service, cluster_index, two_stages = false)
      [
        service.id,
        service.activity.point.location.lat,
        service.activity.point.location.lon,
        'cluster_' + cluster_index.to_s,
        vrp.vehicles.collect{ |v| v[:id] }.to_s,
        two_stages ? vrp.vehicles.first.timewindow || vrp.vehicles.first.sequence_timewindows : nil
      ]
    end
  end

  # To output data about scheduling heuristic process
  class Scheduling
    def initialize(name, vehicles, job, schedule_end)
      ### csv file ###
      @csv_name = "scheduling_construction#{"_#{name}" if name}#{"_#{job}" if job}".parameterize
      @nb_days = schedule_end

      @scheduling_file = ''
      @scheduling_file << 'customer_id,nb_visits,vehicle_id,'
      (0..@nb_days).each{ |day|
        @scheduling_file << "#{day},"
      }
      @scheduling_file << "\n"
    end

    def initialize_geojson(name, vehicles, services, job)
      ### geojson file ###
      @geojson_name = "scheduling_construction_geojson#{"_#{name}" if name}#{"_#{job}" if job}".parameterize
      @geojson_counter = 0
      @coordinates = {}
      services.each{ |s|
        @coordinates[s.id] = [s.activity.point.location.lon, s.activity.point.location.lat] if s.activity # no need to output if we do not know where
      }
      vehicles.each{ |v|
        @coordinates[v.start_point_id] = [v.start_point.location.lon, v.start_point.location.lat] if v.start_point_id
        @coordinates[v.end_point_id] = [v.end_point.location.lon, v.end_point.location.lat] if v.end_point
      }
    end

    def insert_visits(vehicle_id, days, inserted_id, nb_visits)
      return if days.empty?

      line = "#{inserted_id},#{nb_visits},#{vehicle_id}"
      (0..@nb_days).each{ |day|
        line << if days.include?(day)
          ',X'
        else
          ','
        end
      }
      @scheduling_file << "#{line}\n"
    end

    def compute_route(route_data)
      return unless @geojson_name

      current_route = route_data[:current_route]
      route_data[:geojson] = [{
        type: 'Feature',
        properties: {
          color: route_data[:color],
          name: "start_#{route_data[:vehicle_id]}_#{route_data[:global_day_index]}"
        },
        geometry: {
          type: 'LineString',
          coordinates: [@coordinates[route_data[:start_point_id]], @coordinates[current_route[0][:id]]]
        }
      }] + Array.new(current_route.size - 1){ |index_in_route|
        {
          type: 'Feature',
          properties: {
            name: "#{current_route[index_in_route][:id]}_to_#{current_route[index_in_route + 1][:id]}"
          },
          geometry: {
            type: 'LineString',
            coordinates: [@coordinates[current_route[index_in_route][:id]], @coordinates[current_route[index_in_route + 1][:id]]]
          }
        }
      } + [{
        type: 'Feature',
        properties: {
          color: route_data[:color],
          name: "end_#{route_data[:vehicle_id]}_#{route_data[:global_day_index]}"
        },
        geometry: {
          type: 'LineString',
          coordinates: [@coordinates[current_route.last[:id]], @coordinates[route_data[:end_point_id]]]
        }
      }]
    end

    def output_geojson(name, routes)
      return unless @geojson_name

      geojson = {
        type: 'FeatureCollection',
        features: routes.flat_map{ |_v, d| d.collect{ |_day, data| data[:geojson] } }
      }

      Api::V01::APIBase.dump_vrp_dir.write("#{@geojson_name}_#{@geojson_counter}_" + name, geojson.to_json, mode: 'a')
      @geojson_counter += 1
    end

    def remove_visits(removed_days, all_inserted_days, inserted_id, nb_visits)
      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line << if removed_days.include?(day)
          ',-'
        elsif all_inserted_days.include?(day)
          ',~'
        else
          ','
        end
      }
      @scheduling_file << "#{line}\n"
    end

    def add_single_visit(inserted_day, all_inserted_days, inserted_id, nb_visits)
      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line << if day == inserted_day
          ',X'
        elsif all_inserted_days.include?(day)
          ',~'
        else
          ','
        end
      }
      @scheduling_file << "#{line}\n"
    end

    def add_comment(comment)
      @scheduling_file << "#{comment}\n"
    end

    def close_file
      Api::V01::APIBase.dump_vrp_dir.write(@csv_name, @scheduling_file, mode: 'a')
    end
  end
end
