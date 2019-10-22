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
    def initialize(vrp_name, job)
      @job = job
      @file_name = ('generated_clusters' + ("_#{vrp_name}" if vrp_name).to_s + ("_#{@job}" if @job).to_s + '_' + Time.now.strftime('%H:%M:%S')).parameterize
    end

    def generate_files(all_service_vrps, vehicles = [], two_stages = false)
      csv_lines = if vehicles.first.sequence_timewindows.size > 1
        [['name', 'lat', 'lng', 'tags', 'vehicle_id', 'start depot', 'end depot']]
      else
        [['name', 'lat', 'lng', 'tags', 'vehicle_id', 'tw_start', 'tw_end', 'day', 'start depot', 'end depot']]
      end

      polygons = []
      if !two_stages && !vehicles.empty?
        # clustering for each vehicle and each day
        # TODO : simplify ? iterate over all_service_vrps rather than over vehicle and finding associated service_vrp ?
        vehicles.each_with_index{ |vehicle, v_index|
          all_service_vrps.select{ |service| service[:vrp].vehicles.first.id == vehicle.id }.each_with_index{ |service_vrp, cluster_index|
            polygons << collect_hulls(service_vrp) unless service_vrp[:vrp].services.empty?
            service_vrp[:vrp].services.each{ |service|
              csv_lines << csv_line(service_vrp[:vrp], service, cluster_index, 'v' + v_index.to_s + '_pb')
            }
          }
        }
      else
        # clustering for each vehicle
        all_service_vrps.each_with_index{ |service_vrp, cluster_index|
          polygons << collect_hulls(service_vrp) unless service_vrp[:vrp].services.empty?
          service_vrp[:vrp].services.each{ |service|
            csv_lines << csv_line(service_vrp[:vrp], service, cluster_index)
          }
        }
      end

      Api::V01::APIBase.dump_vrp_dir.write(@file_name + '_geojson', {
        type: 'FeatureCollection',
        features: polygons.compact
      }.to_json)

      csv_string = CSV.generate do |out_csv|
        csv_lines.each{ |line| out_csv << line }
      end

      Api::V01::APIBase.dump_vrp_dir.write(@file_name + '_csv', csv_string)

      puts 'Clusters saved : ' + @file_name
    end

    private

    def collect_hulls(service_vrp)
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
        properties: Hash[unit_objects.collect{ |unit_object| [unit_object[:unit_id].to_sym, unit_object[:value]] } + [[:duration, duration]]],
        geometry: {
          type: 'Polygon',
          coordinates: [hull + [hull.first]]
        }
      }
    end

    def csv_line(vrp, service, cluster_index, prefix = nil)
      tw_reference = vrp.vehicles.first.timewindow || vrp.vehicles.first.sequence_timewindows.first
      [
        service.id,
        service.activity.point.location.lat,
        service.activity.point.location.lon,
        (prefix || '') + cluster_index.to_s,
        vrp.vehicles.first&.id,
        tw_reference.start,
        tw_reference.end,
        tw_reference.day_index,
        vrp.vehicles.first&.start_point&.id,
        vrp.vehicles.first&.end_point&.id
      ]
    end
  end

  # To output data about scheduling heuristic process
  class Scheduling
    def initialize(name, job, schedule_end)
      @file_name = ("scheduling_construction#{"_#{name}" if vrp.name}#{"_#{job}" if job}" + '_' + Time.now.strftime('%H:%M:%S')).parameterize

      @scheduling_file = ''
      @scheduling_file << 'customer_id,nb_visits,'
      (0..schedule_end).each{ |day|
        @scheduling_file << "#{day},"
      }
      @scheduling_file << "\n"
    end

    def start_new_cluster
      @scheduling_file << "------ new cluster ------\n"
    end

    def output_scheduling_insertion(days, inserted_id, nb_visits, schedule_end)
      line = "#{inserted_id},#{nb_visits}"
      (0..schedule_end).each{ |day|
        line << if days.include?(day)
          ',X'
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
      Api::V01::APIBase.dump_vrp_dir.append(@file_name, @scheduling_file)
    end
  end
end
