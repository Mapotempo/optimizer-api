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

  class Result
    def self.generate_geometry(solution)
      return nil unless solution.to_h[:result]

      @colors = ['#DD0000', '#FFBB00', '#CC1882', '#00CC00', '#558800', '#009EFF', '#9000EE',
                 '#0077A3', '#000000', '#003880', '#BEE562']
      @cluster_colors = {}

      expected_geometry = solution[:configuration].to_h[:geometry].to_a.map!(&:to_sym) # TODO : investigate how it is possible that no configuration is returned

      expected_geometry.map!(&:to_sym)
      [solution[:result]].flatten(1).collect{ |result|
        geojson = {}
        @vehicle_partitioned = false
        @work_day_partitioned = false

        geojson[:partitions] = generate_partitions_geometry(result) if expected_geometry.include?(:partitions)
        geojson[:points] = generate_points_geometry(result)
        geojson[:polylines] = generate_polylines_geometry(result) if expected_geometry.include?(:polylines)
        geojson
      }
    end

    private

    def self.generate_partitions_geometry(result)
      activities = result[:routes].flat_map{ |r|
        r[:activities].select{ |a| a[:type] != 'depot' && a[:type] != 'rest' }
      }
      elements = activities + result[:unassigned]
      all_skills = elements.flat_map{ |a| a[:detail][:internal_skills] }.uniq

      has_vehicle_partition = all_skills.any?{ |skill| skill.to_s.start_with?('vehicle_partition_') }
      has_work_day_partition = all_skills.any?{ |skill| skill.to_s.start_with?('work_day_partition_') }
      return unless has_vehicle_partition || has_work_day_partition

      partitions = {}
      if has_vehicle_partition
        @vehicle_partitioned = true
        partitions[:vehicle] = draw_cluster(elements, :vehicle)
      end

      return partitions unless has_work_day_partition

      @work_day_partitioned = true
      partitions[:work_day] = draw_cluster(elements, :work_day)

      partitions
    end

    def self.draw_cluster(elements, entity)
      polygons = elements.group_by{ |element|
        entity == :vehicle ?
        [element[:detail][:internal_skills].find{ |sk| sk.to_s.start_with?('vehicle_partition_') }] :
        [element[:detail][:internal_skills].find{ |sk| sk.to_s.start_with?('work_day_partition_') },
         element[:detail][:skills].find{ |sk| sk.start_with?('cluster ') }]
      }.collect.with_index{ |data, cluster_index|
        cluster_skill, partition_items = data
        collect_basic_hulls(partition_items.collect{ |item| item[:detail] }, entity, cluster_index, cluster_skill)
      }

      {
        type: 'FeatureCollection',
        features: polygons.compact
      }
    end

    def self.compute_color(elements, entity, cluster_index)
      if entity == :vehicle
        @colors[cluster_index % @colors.size]
      else
        day = elements.first[:internal_skills].find{ |skill| skill.start_with?('work_day_partition_') }.split('_').last
        index = OptimizerWrapper::WEEKDAYS.find_index(day.to_sym)
        @colors[index]
      end
    end

    def self.find_color(vehicle_id, day, index)
      if @work_day_partitioned
        @cluster_colors["work_day_partition_#{OptimizerWrapper::WEEKDAYS[day % 7]}"]
      elsif @vehicle_partitioned
        @cluster_colors["vehicle_partition_#{vehicle_id}"]
      else
        @colors[index % @colors.size]
      end
    end

    def self.collect_basic_hulls(elements, entity, cluster_index, cluster_skill)
      vector = elements.map{ |detail|
        [detail[:lon], detail[:lat]]
      }.uniq
      hull = Hull.get_hull(vector)
      return nil if hull.nil?

      quantities = elements.flat_map{ |e| e[:quantities] }.group_by{ |qty| qty[:unit] }.collect{ |unit_id, qties|
        {
          unit_id: unit_id,
          value: qties.sum{ |qty| qty[:value] || 0 }
        }
      }
      duration = elements.sum{ |e| e[:duration] + e[:setup_duration] }

      @cluster_colors[cluster_skill.first] = compute_color(elements, entity, cluster_index)
      {
        type: 'Feature',
        properties: {
          color: @cluster_colors[cluster_skill.first],
          name: cluster_skill.join('_'),
        }.merge(
          Hash[quantities.collect{ |qty| [qty[:unit_id].to_sym, qty[:value]] }]
        ).merge(Hash[:duration, duration]),
        geometry: {
          type: 'Polygon',
          coordinates: [hull + [hull.first]]
        }
      }
    end

    def self.generate_points_geometry(result)
      return nil unless (result[:unassigned].empty? || result[:unassigned].any?{ |un| un[:detail][:lat] }) &&
                        (result[:routes].all?{ |r| r[:activities].empty? } ||
                         result[:routes].any?{ |r| r[:activities].any?{ |a| a[:detail] && a[:detail][:lat] } })

      points = []

      result[:unassigned].each{ |unassigned|
        points << {
          type: 'Feature',
          properties: {
            color: '#B5B5B5',
            name: unassigned[:service_id] || unassigned[:shipment_id],
          },
          geometry: {
            type: 'Point',
            coordinates: [unassigned[:detail][:lon], unassigned[:detail][:lat]]
          }
        }
      }

      result[:routes].each_with_index{ |r, index|
        color = find_color(r[:original_vehicle_id], r[:day], index)
        r[:activities].each{ |a|
          next unless ['service', 'pickup', 'delivery'].include?(a[:type])

          points << {
            type: 'Feature',
            properties: {
              color: color,
              name: a[:service_id] || a[:pickup_id] || a[:shipment_id],
              vehicle: r[:original_vehicle_id],
              day: r[:day]
            },
            geometry: {
              type: 'Point',
              coordinates: [a[:detail][:lon], a[:detail][:lat]]
            }
          }
        }
      }

      {
        type: 'FeatureCollection',
        features: points
      }
    end

    def self.generate_polylines_geometry(result)
      polylines = []

      result[:routes].each_with_index{ |route, route_index|
        next unless route[:geometry]

        color = find_color(route[:original_vehicle_id], route[:day], route_index)
        polylines << {
          type: 'Feature',
          properties: {
            color: color,
            name: "#{route[:original_vehicle_id]}, day #{route[:day]} route",
            vehicle: route[:original_vehicle_id],
            day: route[:day]
          },
          geometry: {
            type: 'LineString',
            coordinates: route[:geometry][0]
          }
        }
      }

      {
        type: 'FeatureCollection',
        features: polylines
      }
    end
  end

  # To output data about scheduling heuristic process
  class Scheduling
    def initialize(name, vehicle_names, job, schedule_end)
      @file_name = "scheduling_construction#{"_#{name}" if name}#{"_#{job}" if job}".parameterize
      @nb_days = schedule_end

      @scheduling_file = ''
      @scheduling_file << 'customer_id,nb_visits,'
      (0..@nb_days).each{ |day|
        @scheduling_file << "#{day},"
      }
      @scheduling_file << "\n"

      @scheduling_file << "CLUSTER WITH VEHICLES #{vehicle_names} ------\n"
    end

    def insert_visits(days, inserted_id, nb_visits)
      return if days.empty?

      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line << if days.include?(day)
          ',X'
        else
          ','
        end
      }
      @scheduling_file << "#{line}\n"
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
      Api::V01::APIBase.dump_vrp_dir.write(@file_name, @scheduling_file, mode: 'a')
    end
  end
end
