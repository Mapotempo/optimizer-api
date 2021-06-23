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
  # For result output
  class Result
    def self.generate_header(solutions_set)
      scheduling, scheduling_header = generate_scheduling_header(solutions_set)
      unit_ids, quantities_header = generate_quantities_header(solutions_set)
      max_timewindows_size, timewindows_header = generate_timewindows_header(solutions_set)
      unassigned_header =
        if solutions_set.any?{ |solution| solution[:unassigned].size.positive? }
          [I18n.t('export_file.comment')]
        else
          []
        end

      header = scheduling_header +
               basic_header +
               quantities_header +
               timewindows_header +
               unassigned_header +
               complementary_header(solutions_set.any?{ |solution| solution[:routes].any?{ |route| route[:day] } })

      [header, unit_ids, max_timewindows_size, scheduling, !unassigned_header.empty?]
    end

    def self.generate_scheduling_header(solutions_set)
      if solutions_set.any?{ |solution|
           solution[:routes].any?{ |route| route[:original_vehicle_id] != route[:vehicle_id] }
         }
        [true, [I18n.t('export_file.plan.name'), I18n.t('export_file.plan.ref')]]
      else
        [false, []]
      end
    end

    def self.basic_header
      [I18n.t('export_file.route.id'),
       I18n.t('export_file.stop.reference'),
       I18n.t('export_file.stop.point_id'),
       I18n.t('export_file.stop.lat'),
       I18n.t('export_file.stop.lon'),
       I18n.t('export_file.stop.type'),
       I18n.t('export_file.stop.wait_time'),
       I18n.t('export_file.stop.start_time'),
       I18n.t('export_file.stop.end_time'),
       I18n.t('export_file.stop.setup'),
       I18n.t('export_file.stop.duration'),
       I18n.t('export_file.stop.additional_value'),
       I18n.t('export_file.stop.skills'),
       I18n.t('export_file.tags'),
       I18n.t('export_file.route.total_travel_time'),
       I18n.t('export_file.route.total_travel_distance'),
       I18n.t('export_file.route.total_wait_time')]
    end

    def self.generate_quantities_header(solutions_set)
      unit_ids, quantities_header = [], []

      solutions_set.collect{ |solution|
        solution[:routes].each{ |route|
          route[:activities].each{ |activity|
            next if activity[:detail].nil?

            (activity[:detail][:quantities] || []).each{ |quantity|
              unit_ids << quantity[:unit]
              quantities_header << I18n.t('export_file.stop.quantity', unit: (quantity[:label] || quantity[:unit]))
            }
          }
        }
      }

      [unit_ids.uniq, quantities_header.uniq]
    end

    def self.generate_timewindows_header(solutions_set)
      max_timewindows_size = solutions_set.collect{ |solution|
        solution[:routes].collect{ |route|
          route[:activities].collect{ |activity|
            if activity[:detail]
              (activity[:detail][:timewindows] || []).collect{ |tw| [tw[:start], tw[:end]] }.uniq.size
            end
          }
        } + solution[:unassigned].collect{ |activity|
          if activity[:detail]
            (activity[:detail][:timewindows] || []).collect{ |tw| [tw[:start], tw[:end]] }.uniq.size
          end
        }
      }.flatten.compact.max

      timewindows_header = (0..max_timewindows_size.to_i - 1).collect{ |index|
        tw_index = index + (I18n.locale == :legacy ? 0 : 1)
        [I18n.t('export_file.stop.tw_start', index: tw_index), I18n.t('export_file.stop.tw_end', index: tw_index)]
      }.flatten

      [max_timewindows_size, timewindows_header]
    end

    def self.complementary_header(any_day_index)
      [
        I18n.t('export_file.stop.name'),
        I18n.t('export_file.route.original_id'),
        any_day_index ? I18n.t('export_file.route.day') : nil,
        any_day_index ? I18n.t('export_file.stop.visit_index') : nil
      ]
    end

    def self.complementary_data(route, activity)
      [
        activity[:original_service_id] || activity[:original_shipment_id] || activity[:original_rest_id],
        route && route[:original_vehicle_id],
        route && route[:day],
        activity[:visit_index]
      ]
    end

    def self.activity_line(activity, route, name, unit_ids, max_timewindows_size, scheduling, reason)
      days_info = scheduling ? [activity[:day_week_num], activity[:day_week]] : []
      common = build_csv_activity(name, route, activity)
      timewindows = build_csv_timewindows(activity, max_timewindows_size)
      quantities = unit_ids.collect{ |unit_id|
        quantity = activity[:detail][:quantities]&.find{ |qty| qty[:unit] == unit_id }
        quantity[:value] if quantity
      }
      (days_info + common + quantities + timewindows + reason + complementary_data(route, activity))
    end

    def self.find_type_and_complete_id(activity)
      if activity[:service_id]
        [I18n.t('export_file.stop.type_visit'), activity[:service_id]]
      elsif activity[:pickup_shipment_id]
        [I18n.t('export_file.stop.type_visit'), "#{activity[:pickup_shipment_id]}_pickup"]
      elsif activity[:delivery_shipment_id]
        [I18n.t('export_file.stop.type_visit'), "#{activity[:delivery_shipment_id]}_delivery"]
      elsif activity[:shipment_id]
        [I18n.t('export_file.stop.type_visit'), "#{activity[:shipment_id]}_#{activity[:type]}"]
      elsif activity[:rest_id]
        [I18n.t('export_file.stop.type_rest'), activity[:rest_id]]
      else
        [I18n.t('export_file.stop.type_store'), activity[:point_id]]
      end
    end

    def self.build_csv_activity(name, route, activity)
      type, complete_id = find_type_and_complete_id(activity)
      [
        route && route[:vehicle_id],
        complete_id,
        activity[:point_id],
        activity[:detail][:lat],
        activity[:detail][:lon],
        type,
        formatted_duration(activity[:waiting_time]),
        formatted_duration(activity[:begin_time]),
        formatted_duration(activity[:end_time]),
        formatted_duration(activity[:detail][:setup_duration] || 0),
        formatted_duration(activity[:detail][:duration] || 0),
        activity[:detail][:additional_value] || 0,
        activity[:detail][:skills].to_a.empty? ? nil : activity[:detail][:skills].to_a.flatten.join(','),
        name,
        route && formatted_duration(route[:total_travel_time]),
        route && route[:total_distance],
        route && formatted_duration(route[:total_waiting_time]),
      ].flatten
    end

    def self.build_csv_timewindows(activity, max_timewindows_size)
      tws = activity[:detail][:timewindows]&.collect{ |tw| { start: tw[:start], end: tw[:end] } }.to_a.uniq

      (0..max_timewindows_size - 1).collect{ |index|
        if index < tws.size
          timewindow = tws.sort_by{ |tw| tw[:start] || 0 }[index]

          [timewindow[:start] && formatted_duration(timewindow[:start]),
           timewindow[:end] && formatted_duration(timewindow[:end])]
        else
          [nil, nil]
        end
      }.flatten
    end

    def self.formatted_duration(duration)
      return unless duration

      h = (duration / 3600).to_i
      m = (duration / 60).to_i % 60
      s = duration.to_i % 60
      [h, m, s].map { |t| t.to_s.rjust(2, '0') }.join(':')
    end

    def self.build_csv(solutions)
      return unless solutions

      I18n.locale = :legacy if solutions.any?{ |s| s[:use_deprecated_csv_headers] }
      header, unit_ids, max_timewindows_size, scheduling, any_unassigned = generate_header(solutions)

      CSV.generate{ |output_csv|
        output_csv << header
        solutions.collect{ |solution|
          solution[:routes].each{ |route|
            route[:activities].each{ |activity|
              reason = any_unassigned ? [nil] : []
              output_csv << activity_line(
                activity, route, solution[:name], unit_ids, max_timewindows_size, scheduling, reason)
            }
          }
          solution[:unassigned].each{ |activity|
            output_csv << activity_line(
              activity, nil, solution[:name], unit_ids, max_timewindows_size, scheduling, [activity[:reason]])
          }
        }
      }
    end
  end

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
      return nil if solution.nil? || solution[:result].nil? || solution[:result].empty?

      @colors = ['#DD0000', '#FFBB00', '#CC1882', '#00CC00', '#558800', '#009EFF', '#9000EE',
                 '#0077A3', '#000000', '#003880', '#BEE562']

      expected_geometry = solution[:configuration].to_h[:geometry].to_a.map!(&:to_sym) # TODO : investigate how it is possible that no configuration is returned
      return nil unless expected_geometry.any?

      expected_geometry.map!(&:to_sym)
      solution[:result].collect{ |result|
        geojson = {}

        geojson[:partitions] = generate_partitions_geometry(result) if expected_geometry.include?(:partitions)
        geojson[:points] = generate_points_geometry(result)
        # TODO : re-activate this function call when we find a good way to return polylines in result
        # geojson[:polylines] = generate_polylines_geometry(result) if expected_geometry.include?(:polylines)
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
        partitions[:vehicle] = draw_cluster(elements, :vehicle)
      end

      return partitions unless has_work_day_partition

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

    def self.compute_color(elements, entity, index)
      if entity == :vehicle
        @colors[index % @colors.size]
      elsif entity == :work_day
        day = elements.first[:internal_skills].find{ |skill| skill.start_with?('work_day_partition_') }.split('_').last
        index = OptimizerWrapper::WEEKDAYS.find_index(day.to_sym)
        @colors[index]
      else
        @colors[index % 7]
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

      {
        type: 'Feature',
        properties: {
          color: compute_color(elements, entity, cluster_index),
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

      result[:routes].each{ |r|
        color = compute_color([], nil, r[:day] || 0)
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

      result[:routes].each{ |route|
        next unless route[:geometry]

        color = compute_color([], nil, route[:day])
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
