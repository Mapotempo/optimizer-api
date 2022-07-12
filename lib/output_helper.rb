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

module OutputHelper
  # For result output
  class Result
    def self.generate_header(solutions_set)
      periodic, periodic_header = generate_periodic_header(solutions_set)
      unit_ids, quantities_header = generate_quantities_header(solutions_set)
      max_timewindows_size, timewindows_header = generate_timewindows_header(solutions_set)
      unassigned_header =
        if solutions_set.any?{ |solution| solution[:unassigned].size.positive? }
          [I18n.t('export_file.comment')]
        else
          []
        end

      header = periodic_header +
               basic_header +
               quantities_header +
               timewindows_header +
               unassigned_header +
               complementary_header(solutions_set.any?{ |solution| solution[:routes].any?{ |route| route[:day] } })

      [header, unit_ids, max_timewindows_size, periodic, !unassigned_header.empty?]
    end

    def self.generate_periodic_header(solutions_set)
      if solutions_set.any?{ |solution|
           solution[:routes].any?{ |route|
             route[:original_vehicle_id] != route[:vehicle_id]
           }
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
       I18n.t('export_file.stop.setup_time'),
       I18n.t('export_file.stop.start_time'),
       I18n.t('export_file.stop.end_time'),
       I18n.t('export_file.stop.setup'),
       I18n.t('export_file.stop.duration'),
       I18n.t('export_file.stop.additional_value'),
       I18n.t('export_file.stop.skills'),
       I18n.t('export_file.tags'),
       I18n.t('export_file.stop.travel_time'),
       I18n.t('export_file.route.total_travel_time'),
       I18n.t('export_file.stop.travel_distance'),
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

    def self.activity_line(activity, route, name, unit_ids, max_timewindows_size, periodic, reason)
      days_info = periodic ? [activity[:day_week_num], activity[:day_week]] : []
      common = build_csv_activity(name, route, activity)
      timewindows = build_csv_timewindows(activity, max_timewindows_size)
      quantities =
        unit_ids.collect{ |unit_id|
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
        formatted_duration(activity[:setup_time]),
        formatted_duration(activity[:begin_time]),
        formatted_duration(activity[:end_time]),
        formatted_duration(activity[:detail][:setup_duration] || 0),
        formatted_duration(activity[:detail][:duration] || 0),
        activity[:detail][:additional_value] || 0,
        activity[:detail][:skills].to_a.empty? ? nil : activity[:detail][:skills].to_a.flatten.join(','),
        name,
        formatted_duration(activity[:travel_time]),
        route && formatted_duration(route[:total_travel_time]),
        activity[:travel_distance],
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

      I18n.locale = :legacy if solutions.any?{ |s| s[:configuration][:deprecated_headers] }
      header, unit_ids, max_timewindows_size, periodic, any_unassigned = generate_header(solutions)

      CSV.generate{ |output_csv|
        output_csv << header
        solutions.collect{ |solution|
          solution[:routes].each{ |route|
            route[:activities].each{ |activity|
              reason = any_unassigned ? [nil] : []
              output_csv << activity_line(
                activity, route, solution[:name], unit_ids, max_timewindows_size, periodic, reason
              )
            }
          }
          solution[:unassigned].each{ |activity|
            output_csv << activity_line(
              activity, nil, solution[:name], unit_ids, max_timewindows_size, periodic, [activity[:reason]]
            )
          }
        }
      }
    end
  end

  # To output clusters generated
  class Clustering
    def self.generate_files(all_service_vrps, two_stages = false, job = nil)
      vrp_name = all_service_vrps.first[:vrp].name
      file_name = ('generated_clusters' + '_' + [vrp_name, job,
                                                 Time.now.strftime('%H:%M:%S')].compact.join('_')).parameterize

      polygons = []
      csv_lines = [['id', 'lat', 'lon', 'cluster', 'vehicles_ids', 'vehicle_tw_if_only_one']]
      all_service_vrps.each_with_index{ |service_vrp, cluster_index|
        # unless service_vrp[:vrp].services.empty? -----> possible to get here if cluster empty ??
        polygons << collect_hulls(service_vrp)
        service_vrp[:vrp].services.each{ |service|
          csv_lines << csv_line(service_vrp[:vrp], service, cluster_index, two_stages)
        }
      }

      Api::V01::APIBase.dump_vrp_dir.write(file_name + '_geojson', {
        type: 'FeatureCollection',
        features: polygons.compact
      }.to_json)

      csv_string =
        CSV.generate do |out_csv|
          csv_lines.each{ |line| out_csv << line }
        end

      Api::V01::APIBase.dump_vrp_dir.write(file_name + '_csv', csv_string)

      log 'Clusters saved: ' + file_name, level: :debug
      file_name
    end

    def self.collect_hulls(service_vrp)
      vector =
        service_vrp[:vrp].services.collect{ |service|
          [service.activity.point.location.lon, service.activity.point.location.lat]
        }
      hull = Hull.get_hull(vector)
      return nil if hull.nil?

      unit_objects =
        service_vrp[:vrp].units.collect{ |unit|
          {
            unit_id: unit.id,
            value: service_vrp[:vrp].services.collect{ |service|
              service_quantity = service.quantities.find{ |quantity| quantity.unit_id == unit.id }
              service_quantity&.value || 0
            }.reduce(&:+)
          }
        }
      duration =
        service_vrp[:vrp][:services].group_by{ |s| s.activity.point_id }.sum{ |_point_id, ss|
          first = ss.min_by{ |s| -s.visits_number }
          first.activity.setup_duration * first.visits_number + ss.sum{ |s| s.activity.duration * s.visits_number }
        }
      {
        type: 'Feature',
        properties: Hash[
          unit_objects.collect{ |unit_object| [unit_object[:unit_id].to_sym, unit_object[:value]] } +
          [[:duration, duration]] +
          [[:vehicle, service_vrp[:vrp].vehicles.size == 1 ? service_vrp[:vrp].vehicles.first&.id : nil]]
        ],
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
    def self.generate_geometry(result_object)
      return nil if result_object.nil? || result_object[:result].nil? || result_object[:result].empty?

      @colors = ['#DD0000', '#FFBB00', '#CC1882', '#00CC00', '#558800', '#009EFF', '#9000EE',
                 '#0077A3', '#000000', '#003880', '#BEE562']
      return nil if result_object[:result].none?{ |solution|
        solution[:configuration] && solution[:configuration][:geometry]&.any?
      }

      result_object[:result].collect{ |solution|
        expected_geometry = solution[:configuration][:geometry].to_a.map!(&:to_sym)
        next unless expected_geometry.any?

        geojson = {}
        # if there is vehicle partition, the geojson object colors will be based on vehicle indices
        vehicle_color_indices = solution[:routes]&.map&.with_index{ |route, index|
          [route[:original_vehicle_id], index]
        }&.to_h
        if expected_geometry.include?(:partitions)
          geojson[:partitions] = generate_partitions_geometry(solution, vehicle_color_indices)
        end
        geojson[:points] = generate_points_geometry(solution, vehicle_color_indices)
        if expected_geometry.include?(:polylines) && OptimizerWrapper.config[:restitution][:allow_polylines]
          geojson[:polylines] = generate_polylines_geometry(solution, vehicle_color_indices)
        end
        geojson
      }
    end

    class << self
      private

      def generate_partitions_geometry(result, vehicle_color_indices)
        activities =
          result[:routes].flat_map{ |r|
            r[:activities].select{ |a| a[:type] != 'depot' && a[:type] != 'rest' }
          }
        elements = activities + result[:unassigned]
        all_skills = elements.flat_map{ |a| a[:detail][:internal_skills] }.uniq

        has_vehicle_partition = all_skills.any?{ |skill| skill.to_s.start_with?('vehicle_partition_') }
        has_work_day_partition = all_skills.any?{ |skill| skill.to_s.start_with?('work_day_partition_') }
        return unless has_vehicle_partition || has_work_day_partition

        partitions = {}
        partitions[:vehicle] = draw_cluster(elements, vehicle_color_indices, :vehicle) if has_vehicle_partition
        partitions[:work_day] = draw_cluster(elements, vehicle_color_indices, :work_day) if has_work_day_partition
        partitions
      end

      def draw_cluster(elements, vehicle_color_indices, entity)
        polygons =
          elements.group_by{ |element|
            entity == :vehicle ?
            [element[:detail][:internal_skills].find{ |sk| sk.to_s.start_with?('vehicle_partition_') }] :
            [element[:detail][:internal_skills].find{ |sk| sk.to_s.start_with?('work_day_partition_') },
             element[:detail][:skills].find{ |sk| sk.start_with?('cluster ') }]
          }.collect.with_index{ |data, cluster_index|
            cluster_name, partition_items = data
            skills_properties = compute_skills_properties(data)
            color_index =
              skills_properties[:vehicle] ? vehicle_color_indices[skills_properties[:vehicle]] : cluster_index
            collect_basic_hulls(partition_items.collect{ |item| item[:detail] }, entity, color_index,
                                cluster_name, skills_properties)
          }

        {
          type: 'FeatureCollection',
          features: polygons.compact
        }
      end

      def compute_skills_properties(data)
        items = data.last
        skills = items.flat_map{ |item| item[:detail][:internal_skills] }.uniq
        vehicle_skills = skills.select{ |sk| sk.to_s.start_with?('vehicle_partition_') }
        work_day_skills = skills.select{ |sk| sk.to_s.start_with?('work_day_partition_') }

        sk_property = {}
        sk_property[:vehicle] = vehicle_skills.first.to_s.gsub('vehicle_partition_', '') if vehicle_skills.size == 1
        sk_property[:work_day] = work_day_skills.first.to_s.gsub('work_day_partition_', '') if work_day_skills.size == 1
        sk_property
      end

      def compute_color(_elements, _entity, index)
        @colors[index % @colors.size]
      end

      def collect_basic_hulls(elements, entity, cluster_index, cluster_name, skills_properties)
        vector = elements.map{ |detail|
          [detail[:lon], detail[:lat]]
        }.uniq
        hull = Hull.get_hull(vector)
        return nil if hull.nil?

        quantities =
          elements.flat_map{ |e| e[:quantities] }.group_by{ |qty| qty[:unit] }.collect{ |unit_id, qties|
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
            name: cluster_name.join('_'),
          }.merge(
            Hash[quantities.collect{ |qty| [qty[:unit_id].to_sym, qty[:value]] }]
          ).merge(Hash[:duration, duration]).merge(skills_properties),
          geometry: {
            type: 'Polygon',
            coordinates: [hull + [hull.first]]
          }
        }
      end

      def generate_points_geometry(result, vehicle_color_indices)
        return nil unless (result[:unassigned].empty? || result[:unassigned].any?{ |un| un[:detail][:lat] }) &&
                          (result[:routes].all?{ |r| r[:activities].empty? } ||
                           result[:routes].any?{ |r| r[:activities].any?{ |a| a[:detail] && a[:detail][:lat] } })

        points = []

        mission_types = [:service, :pickup, :delivery]

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
          color = compute_color([], nil, vehicle_color_indices[r[:original_vehicle_id]] || r[:day] || 0)
          r[:activities].each{ |a|
            next unless mission_types.include?(a[:type].to_sym)

            skills_properties = compute_skills_properties([nil, [a]])
            points << {
              type: 'Feature',
              properties: {
                color: color,
                name: a[:service_id] || a[:pickup_id] || a[:shipment_id],
                day: r[:day]
              }.merge(skills_properties),
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

      def generate_polylines_geometry(result, vehicle_color_indices)
        polylines = []

        result[:routes].each_with_index{ |route, route_index|
          next unless route[:geometry]

          color = route[:original_vehicle_id] &&
                  compute_color([], nil, vehicle_color_indices[route[:original_vehicle_id]]) ||
                  route[:day] &&
                  compute_color([], nil, route[:day]) ||
                  compute_color([], :vehicle, route_index)
          week_day = route[:day] && { work_day: OptimizerWrapper::WEEKDAYS[route[:day] % 7] } || {}
          polylines << {
            type: 'Feature',
            properties: {
              color: color,
              name: "#{route[:original_vehicle_id]}#{route[:day] ? '' : ", day #{route[:day]} route"}",
              vehicle: route[:original_vehicle_id],
              day: route[:day]
            }.merge(week_day),
            geometry: {
              type: 'LineString',
              coordinates: route[:geometry].flatten(1)
            }
          }
        }

        {
          type: 'FeatureCollection',
          features: polylines
        }
      end
    end
  end

  # To output data about periodic heuristic process
  class PeriodicHeuristic
    def initialize(name, vehicle_names, job, schedule_end)
      @file_name = "periodic_construction#{"_#{name}" if name}#{"_#{job}" if job}".parameterize
      @nb_days = schedule_end

      @periodic_file = ''
      @periodic_file << 'customer_id,nb_visits,'
      (0..@nb_days).each{ |day|
        @periodic_file << "#{day},"
      }
      @periodic_file << "\n"

      @periodic_file << "CLUSTER WITH VEHICLES #{vehicle_names} ------\n"
    end

    def insert_visits(days, inserted_id, nb_visits)
      return if days.empty?

      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line += days.include?(day) ? ',X' : ','
      }
      @periodic_file << "#{line}\n"
    end

    def remove_visits(removed_days, all_inserted_days, inserted_id, nb_visits)
      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line <<
          if removed_days.include?(day)
            ',-'
          elsif all_inserted_days.include?(day)
            ',~'
          else
            ','
          end
      }
      @periodic_file << "#{line}\n"
    end

    def add_single_visit(inserted_day, all_inserted_days, inserted_id, nb_visits)
      line = "#{inserted_id},#{nb_visits}"
      (0..@nb_days).each{ |day|
        line <<
          if day == inserted_day
            ',X'
          elsif all_inserted_days.include?(day)
            ',~'
          else
            ','
          end
      }
      @periodic_file << "#{line}\n"
    end

    def add_comment(comment)
      @periodic_file << "#{comment}\n"
    end

    def close_file
      Api::V01::APIBase.dump_vrp_dir.write(@file_name, @periodic_file, mode: 'a')
    end
  end
end
