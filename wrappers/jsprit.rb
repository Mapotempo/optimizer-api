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

require 'nokogiri'
require 'open3'
module Wrappers
  class Jsprit < Wrapper
    def initialize(hash = {})
      super(hash)
      @exec_jsprit = hash[:exec_jsprit] || 'java -jar ../optimizer-jsprit/target/optimizer-jsprit-0.0.1-SNAPSHOT-jar-with-dependencies.jar'

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [
        :assert_end_optimization,
        :assert_vehicles_objective,
        :assert_vehicles_no_force_start,
        :assert_vehicles_no_late_multiplier,
        :assert_vehicles_no_overload_multiplier,
        :assert_services_no_late_multiplier,
        :assert_services_no_priority,
        :assert_one_sticky_at_most,
        :assert_no_relations,
        :assert_vehicles_no_duration_limit,
        :assert_no_value_matrix,
        :assert_correctness_matrices_vehicles_and_points_definition,
        :assert_only_empty_or_fill_quantities,
        :assert_points_same_definition,
        :assert_no_subtours,
        :assert_no_evaluation,
        :assert_no_first_solution_strategy,
        :assert_solver,
        :assert_no_overall_duration,
        :assert_no_direct_shipments,
      ]
    end

    def solve(vrp, job, thread_proc = nil, &block)
      @job = job
      result = run_jsprit(vrp, @threads, thread_proc, &block)
      if result&.is_a?(Hash)
        result
      else
        m = /Exception: (.+)\n/.match(result) if result
        raise RuntimeError, (m && m[1]) || 'Unexpected exception'
      end
    end

    def kill
      @semaphore.synchronize {
        Process.kill('KILL', @thread.pid)
        @killed = true
      }
    end

    private

    def assert_end_optimization(vrp)
      vrp.resolution_duration || vrp.resolution_iterations || vrp.resolution_iterations_without_improvment
    end

    def assert_jsprit_start_or_end(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        vehicle.start_point.nil? && vehicle.end_point.nil?
      }.nil?
    end

    def run_jsprit(vrp, threads, thread_proc = nil, &block)
      fleet = Hash[vrp.vehicles.collect{ |vehicle| [vehicle.id, vehicle] }]
      builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.problem(xmlns: 'http://www.w3schools.com', ' xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xsi:schemaLocation' => 'http://www.w3schools.com vrp_xml_schema.xsd') {
          xml.problemType {
            xml.fleetSize 'FINITE'
          }
          xml.vehicles {
            vrp.vehicles.each do |vehicle|
              xml.vehicle {
                xml.id_ vehicle.id
                xml.typeId vehicle.id
                if vehicle.start_point
                  xml.startLocation {
                    xml.index vehicle.start_point.matrix_index
                  }
                end
                if vehicle.end_point
                  if vehicle.start_point != vehicle.end_point
                    xml.endLocation {
                      xml.index vehicle.end_point.matrix_index
                    }
                  else
                    xml.returnToDepot true
                  end
                end
                xml.timeSchedule {
                  xml.start vehicle.timewindow&.start || 0
                  xml.end vehicle.timewindow&.end || 2**31
                }
                if !vehicle.rests.empty?
                  vehicle.rests.each do |rest|
                    xml.breaks {
                      xml.timeWindows {
                        rest.timewindows.each do |timewindow|
                          xml.timeWindow {
                            xml.start timewindow.start || 0
                            xml.end timewindow.end || 2**31
                          }
                        end
                      }
                      xml.duration rest.duration
                      xml.id rest.id
                    }
                  end
                end
                xml.alternativeSkills {
                  sticky = "__internal_sticky_vehicle_#{vehicle.id}"
                  if !vehicle.skills.empty?
                    vehicle.skills.each do |skills|
                      xml.skillList(([sticky] + skills).join(',')) if !skills.empty?
                    end
                  else
                    xml.skillList sticky
                  end
                }
                initial = false
                vehicle.capacities.each do |capacity|
                  if capacity[:initial]
                    initial = true
                  end
                end
                if !vehicle.capacities.empty? && initial
                  xml.method_missing('initial-capacity') {
                    vehicle.capacities.each_with_index do |capacity, index|
                      if capacity[:initial]
                        xml.dimension (capacity[:initial] * 1000).to_i, index: index
                      end
                    end
                  }
                end
                (xml.duration vehicle.duration) if vehicle.duration
              }
            end
          }
          xml.vehicleTypes {
            vrp.vehicles.each do |vehicle|
              xml.type {
                xml.id_ vehicle.id
                if !vehicle.capacities.empty?
                  xml.method_missing('capacity-dimensions') {
                    # Jsprit accepts only integers
                    vehicle.capacities.each_with_index do |capacity, index|
                      if capacity[:limit]
                        xml.dimension (capacity[:limit] * 1000).to_i, index: index
                      end
                    end
                  }
                else
                  xml.method_missing('capacity-dimensions') {
                    xml.dimension 0, index: 0
                  }
                end
                xml.costs {
                  (xml.fixed vehicle.cost_fixed)
                  (xml.distance vehicle.cost_distance_multiplier)
                  (xml.time vehicle.cost_time_multiplier)
                  (xml.setup vehicle.cost_setup_time_multiplier)
                }
              }
            end
          }
          if !vrp.services.empty?
            xml.services {
              vrp.services.each do |service|
                xml.service(id: service.id, type: service.type) {
                  xml.location {
                    xml.index service.activity.point.matrix_index
                  }
                  if !service.activity.timewindows.empty?
                    xml.timeWindows {
                      service.activity.timewindows.each do |activity_timewindow|
                        xml.timeWindow {
                          xml.start activity_timewindow.start || 0
                          xml.end activity_timewindow.end || 2**31
                        }
                      end
                    }
                  end
                  (xml.setupDuration service.activity.setup_duration) if service.activity.setup_duration&.positive?
                  (xml.duration service.activity.duration) if service.activity.duration&.positive?
                  if !service.sticky_vehicles.empty? || !service.skills.empty?
                    xml.requiredSkills((((!service.sticky_vehicles.empty?) ? ["__internal_sticky_vehicle_#{service.sticky_vehicles[0].id}"] : []) + service.skills).join(',')) # rubocop: disable Style/RedundantParentheses
                  end

                  if !service.quantities.empty?
                    xml.method_missing('capacity-dimensions') {
                      # Jsprit accepts only integers
                      service.quantities.each_with_index do |quantity, index|
                        xml.dimension (quantity[:value] ? quantity[:value] * 1000 : 0).to_i, index: index
                      end
                    }
                  else
                    xml.method_missing('capacity-dimensions') {
                      # Jsprit accepts only integers
                      xml.dimension 0, index: 0
                    }
                  end
                }
              end
            }
          end
          if !vrp.shipments.empty?
            xml.shipments {
              vrp.shipments.each do |shipment|
                xml.shipment(id: shipment.id) {
                  xml.pickup {
                    xml.location {
                      xml.index shipment.pickup.point.matrix_index
                    }
                    if !shipment.pickup.timewindows.empty?
                      xml.timeWindows {
                        shipment.pickup.timewindows.each do |activity_timewindow|
                          xml.timeWindow {
                            xml.start activity_timewindow.start || 0
                            xml.end activity_timewindow.end || 2**31
                          }
                        end
                      }
                    end
                    (xml.setupDuration shipment.pickup.setup_duration) if shipment.pickup.setup_duration&.positive?
                    (xml.duration shipment.pickup.duration) if shipment.pickup.duration&.positive?
                  }
                  xml.delivery {
                     xml.location {
                      xml.index shipment.delivery.point.matrix_index
                     }
                     if !shipment.delivery.timewindows.empty?
                       xml.timeWindows {
                         shipment.delivery.timewindows.each do |activity_timewindow|
                           xml.timeWindow {
                             xml.start activity_timewindow.start || 0
                             xml.end activity_timewindow.end || 2**31
                           }
                         end
                       }
                     end
                     (xml.setupDuration shipment.delivery.setup_duration) if shipment.delivery.setup_duration&.positive?
                     (xml.duration shipment.delivery.duration) if shipment.delivery.duration&.positive?
                  }
                  if !shipment.sticky_vehicles.empty? || !shipment.skills.empty?
                    xml.requiredSkills((((!shipment.sticky_vehicles.empty?) ? ["__internal_sticky_vehicle_#{service.sticky_vehicles[0].id}"] : []) + shipment.skills).join(',')) # rubocop: disable Style/RedundantParentheses
                  end

                  if !shipment.quantities.empty?
                    xml.method_missing('capacity-dimensions') {
                      # Jsprit accepts only integers
                      shipment.quantities.each_with_index do |quantity, index|
                        xml.dimension (quantity[:value] * 1000).to_i, index: index
                      end
                    }
                  else
                    xml.method_missing('capacity-dimensions') {
                      # Jsprit accepts only integers
                      xml.dimension 0, index: 0
                    }
                  end
                }
              end
            }
          end
        }
      end

      input_problem = Tempfile.new('optimize-jsprit-input_problem', @tmp_dir)
      input_problem.write(builder.to_xml)
      input_problem.close

      input_algorithm = Tempfile.new('optimize-jsprit-input_algorithm', @tmp_dir)
      input_algorithm.write(algorithm_config(vrp.resolution_iterations))
      input_algorithm.close

      if vrp.matrices[0].time
        input_time_matrix = Tempfile.new('optimize-jsprit-input_time_matrix', @tmp_dir)
        input_time_matrix.write(vrp.matrices[0].time.collect{ |a| a.join(' ') }.join("\n"))
        input_time_matrix.close
      end

      if vrp.matrices[0].distance
        input_distance_matrix = Tempfile.new('optimize-jsprit-input_distance_matrix', @tmp_dir)
        input_distance_matrix.write(vrp.matrices[0].distance.collect{ |a| a.join(' ') }.join("\n"))
        input_distance_matrix.close
      end

      output = Tempfile.new(['optimize-jsprit-output', '.xml'], @tmp_dir)
      output.close

      cmd = ["#{@exec_jsprit} ",
             "--algorithm '#{input_algorithm.path}'",
             input_time_matrix ? "--time_matrix '#{input_time_matrix.path}'" : '',
             input_distance_matrix ? "--distance_matrix '#{input_distance_matrix.path}'" : '',
             vrp.resolution_duration ? "--ms '#{vrp.resolution_duration}'" : '',
             vrp.preprocessing_prefer_short_segment ? '--nearby' : '',
             vrp.resolution_iterations_without_improvment ? "--no_improvment_iterations '#{vrp.resolution_iterations_without_improvment}'" : '',
             (vrp.resolution_stable_iterations && resolution_stable_coefficient) ? "--stable_iterations '#{vrp.resolution_stable_iterations}' --stable_coef '#{vrp.resolution_stable_coefficient}'" : '',
             vrp.resolution_vehicle_limit ? "--vehicle_limit #{vrp.resolution_vehicle_limit}" : '',
             "--threads '#{threads}'",
             "--instance '#{input_problem.path}' --solution '#{output.path}'"].join(' ')
      log cmd
      _stdin, stdout_and_stderr, @thread = @semaphore.synchronize {
        Open3.popen2e(cmd) if !@killed
      }
      return if !@thread

      pipe = @semaphore.synchronize {
        IO.popen("ps -ef | grep #{@thread.pid}")
      }

      childs = pipe.readlines.map do |line|
        parts = line.split(/\s+/)
        parts[1].to_i if parts[2] == @thread.pid.to_s
      end.compact || []
      childs << @thread.pid

      thread_proc&.call(childs)

      out = nil
      iterations = 0
      iterations_start = 0
      cost = nil
      fresh_output = nil
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        log line
        out = out ? out + "\n" + line : line
        iterations_start += 1 if /\- iterations start/ =~ line
        if iterations_start == 1
          r = /- iterations ([0-9]+)/.match(line)
          r && (iterations = Integer(r[1]))
          r = /- iterations end at ([0-9]+) iterations/.match(line)
          r && (iterations = Integer(r[1]))
          r = /Iteration : ([0-9]+) .*/.match(line)
          r && (iterations = Integer(r[1]))
          r = / Cost : ([0-9.eE]+)/.match(line)
          r && (cost = Float(r[1]))
          r && (fresh_output = true)
        end
        block&.call(self, iterations, vrp.resolution_iterations, cost, fresh_output && parse_output(output.path, iterations, fleet, vrp))
        fresh_output = nil
      }

      if @thread.value == 0
        parse_output(output.path, iterations, fleet, vrp)
      else
        if @thread.value == 9
          out = 'Job killed'
          log out # Keep trace in worker
          out = parse_output(output.path, iterations, fleet, vrp) if cost
        end
        out
      end
    ensure
      input_problem&.unlink
      input_algorithm&.unlink
      input_time_matrix&.unlink
      input_distance_matrix&.unlink
      output&.unlink
    end

    def parse_output(path, iterations, fleet, vrp)
      doc = Nokogiri::XML(File.open(path))
      doc.remove_namespaces!
      solution = doc.xpath('/problem/solutions/solution').last
      if solution
        {
          cost: Float(solution.at_xpath('cost').content),
          costs: Models::Costs.new({}), # TODO: fulfill with solution costs
          iterations: iterations,
          routes: fleet.collect{ |id, vehicle|
            route_index = solution.xpath('routes/route').find_index{ |route| route.at_xpath('vehicleId').content == id }

            if route_index
              route = solution.xpath('routes/route')[route_index]
              previous_index = fleet[route.at_xpath('vehicleId').content].start_point ? fleet[route.at_xpath('vehicleId').content].start_point.matrix_index : nil
              {
                vehicle_id: route.at_xpath('vehicleId').content,
                start_time: Float(route.at_xpath('start').content),
                end_time: Float(route.at_xpath('end').content),
                activities: ((fleet[route.at_xpath('vehicleId').content].start_point ? [{
                  point_id: fleet[route.at_xpath('vehicleId').content].start_point.id,
                  detail: vehicle.start_point.location ? {
                    lat: vehicle.start_point.location.lat,
                    lon: vehicle.start_point.location.lon
                  } : nil
                }.delete_if{ |_k, v| !v }] : []) +
                route.xpath('act').collect{ |act|
                  job = nil
                  activity = nil
                  case act['type']
                  when 'delivery', 'service', 'pickup'
                    job = vrp.services.find{ |service| service[:id] == act.at_xpath('serviceId').content }
                    activity = job.activity
                  when 'pickupShipment'
                    job = vrp.shipments.find{ |shipment| shipment[:id] == act.at_xpath('shipmentId').content }
                    activity = job.pickup
                  when 'deliverShipment'
                    job = vrp.shipments.find{ |shipment| shipment[:id] == act.at_xpath('shipmentId').content }
                    activity = job.delivery
                  when 'break'
                    job = vrp.rests.find{ |rest| rest[:id] == act.at_xpath('breakId').content }
                    activity = job
                  end
                  point = (act['type'] == 'break') ? nil : activity.point
                  point_index = (act['type'] == 'break') ? previous_index : activity.point[:matrix_index]
                  duration = activity[:duration]

                  current_activity = {
  #                  activity: act.attr('type').to_sym,
                    pickup_shipment_id: (a = act.at_xpath('shipmentId')) && a && act['type'] == 'pickupShipment' && a.content,
                    delivery_shipment_id: (a = act.at_xpath('shipmentId')) && a && act['type'] == 'deliverShipment' && a.content,
                    service_id: (a = act.at_xpath('serviceId')) && a && a.content,
                    point_id: point ? point.id : nil,
                    rest_id: (a = act.at_xpath('breakId')) && a && a.content,
                    travel_time: ((previous_index && point_index && vrp.matrices[0].time) ? vrp.matrices[0].time[previous_index][point_index] : 0),
                    travel_distance: ((previous_index && point_index && vrp.matrices[0].distance) ? vrp.matrices[0].distance[previous_index][point_index] : 0),
                    begin_time: (a = act.at_xpath('endTime')) && a && Float(a.content) - duration,
                    departure_time: (a = act.at_xpath('endTime')) && a && Float(a.content),
                    detail: build_detail(job, activity, (act['type'] == 'break') ? nil : point, nil, nil)
                  }.delete_if { |_k, v| !v }
                  previous_index = point_index
                  current_activity
                } + (fleet[route.at_xpath('vehicleId').content].end_point ? [{
                  point_id: fleet[route.at_xpath('vehicleId').content].end_point.id,
                  detail: vehicle.end_point.location ? {
                    lat: vehicle.end_point.location.lat,
                    lon: vehicle.end_point.location.lon
                  } : nil
                }.delete_if{ |_k, v| !v }] : [])).compact
              }
            else
              {
                vehicle_id: vehicle.id,
                activities:
                  ([vehicle.start_point && {
                    point_id: vehicle.start_point.id,
                    detail: vehicle.start_point.location ? {
                      lat: vehicle.start_point.location.lat,
                      lon: vehicle.start_point.location.lon
                    } : nil
                  }.delete_if{ |_k, v| !v }] +
                  (vehicle.rests.empty? ? [nil] : [{
                    rest_id: vehicle.rests[0].id,
                    detail: build_detail(rest, rest, nil, nil, nil)
                  }]) +
                  [vehicle.end_point && {
                    point_id: vehicle.end_point.id,
                    detail: vehicle.end_point.location ? {
                      lat: vehicle.end_point.location.lat,
                      lon: vehicle.end_point.location.lon
                    } : nil
                  }.delete_if{ |_k, v| !v }]).compact
              }
            end
          },
          unassigned: solution.xpath('unassignedJobs/job').collect{ |job|
            {
              ((vrp.services.find{ |s| s.id == job.attr('id') }) ? :service_id : (vrp.shipments.find{ |s| s.id == job.attr('id') }) ? :shipment_id : nil) => job.attr('id')
            }
          }
        }
      end
    end

    def algorithm_config(max_iterations)
%{<?xml version="1.0" ?>
<!--
 Copyright © Mapotempo, 2016

 This file is part of Mapotempo.

 Mapotempo is free software. You can redistribute it and/or
 modify since you respect the terms of the GNU Affero General
 Public License as published by the Free Software Foundation,
 either version 3 of the License, or (at your option) any later version.

 Mapotempo is distributed in the hope that it will be useful, but WITHOUT
 ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.

 You should have received a copy of the GNU Affero General Public License
 along with Mapotempo. If not, see:
 <http://www.gnu.org/licenses/agpl.html>
-->
<algorithm xmlns="http://www.w3schools.com" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.w3schools.com algorithm_schema.xsd">

    <maxIterations>#{max_iterations || 3600000}</maxIterations>

    <construction>
        <insertion name="regretInsertion"/>
    </construction>
    <strategy>
        <memory>10</memory>
        <searchStrategies>
            <searchStrategy name="randomRuinLarge">
                <selector name="selectBest"/>
                <acceptor name="acceptNewRemoveWorst">
                    <alpha>0.02</alpha>
                    <warmup>10</warmup>
                </acceptor>
                <modules>
                    <module name="ruin_and_recreate">
                        <ruin name="randomRuin">
                                <share>0.5</share>
                            </ruin>
                        <insertion name="regretInsertion"/>
                    </module>
                </modules>
                <probability>0.3</probability>
            </searchStrategy>
            <searchStrategy name="LargeRadialRuinAndRecreate">
                <selector name="selectBest"/>
                <acceptor name="acceptNewRemoveWorst">
                    <alpha>0.02</alpha>
                    <warmup>10</warmup>
                </acceptor>
                <modules>
                    <module name="ruin_and_recreate">
                        <ruin name="radialRuin">
                            <share>0.3</share>
                        </ruin>
                        <insertion name="bestInsertion" id="1"/>
                    </module>
                </modules>
                <probability>0.2</probability>
            </searchStrategy>
            <searchStrategy name="randomRuinSmall">
                <selector name="selectBest"/>
                <acceptor name="acceptNewRemoveWorst">
                    <alpha>0.02</alpha>
                    <warmup>10</warmup>
                </acceptor>
                <modules>
                    <module name="ruin_and_recreate">
                        <ruin name="randomRuin">
                            <share>0.1</share>
                        </ruin>
                        <insertion name="regretInsertion"/>
                    </module>
                </modules>
                <probability>0.3</probability>
            </searchStrategy>
            <searchStrategy name="SmallradialRuinAndRecreate">
                <selector name="selectBest"/>
                <acceptor name="acceptNewRemoveWorst">
                    <alpha>0.02</alpha>
                    <warmup>10</warmup>
                    </acceptor>
                    <modules>
                        <module name="ruin_and_recreate">
                            <ruin name="radialRuin">
                                <share>0.05</share>
                            </ruin>
                            <insertion name="bestInsertion" id="1"/>
                        </module>
                    </modules>
                    <probability>0.2</probability>
            </searchStrategy>
        </searchStrategies>
    </strategy>
</algorithm>
}
    end
  end
end
