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
require 'thread'


module Wrappers
  class Jsprit < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_jsprit = hash[:exec_jsprit] || 'java -jar ../optimizer-jsprit/target/mapotempo-jsprit-0.0.1-SNAPSHOT-jar-with-dependencies.jar'

      @semaphore = Mutex.new
    end

    def solver_constraints
      super + [
        :assert_vehicles_at_least_one,
        :assert_units_only_one,
        :assert_vehicles_quantities_only_one,
        :assert_vehicles_timewindows_only_one,
        :assert_services_no_late_multiplier,
        :assert_services_no_exclusion_cost,
        :assert_services_quantities_only_one,
        :assert_vehicles_same_router_params
      ]
    end

    def solve(vrp, &block)
      result = run_jsprit(vrp.matrix_time, vrp.matrix_distance, vrp.vehicles, vrp.services, vrp.shipments, vrp.resolution_duration, vrp.resolution_iterations, vrp.resolution_iterations_without_improvment, vrp.resolution_stable_iterations, vrp.resolution_stable_coefficient, vrp.preprocessing_prefer_short_segment, @threads, &block)
      if result && result.is_a?(Hash)
        vehicles = Hash[vrp.vehicles.collect{ |vehicle| [vehicle.id, vehicle] }]
        result[:routes].each{ |route|
          vehicle = vehicles[route[:vehicle_id]]
          # always return activities for start and end
          if !vehicle.start_point.nil?
            start_point = vehicle.start_point
          else
            first_activity = route[:activities].find{ |a| a[:service_id] || a[:pickup_shipment_id] || a[:delivery_shipment_id] }
            start_point = first_activity[:service_id] ?
              vrp.services.find{ |s| s.id == first_activity[:service_id] }.activity.point :
              first_activity[:pickup_shipment_id] ?
              vrp.shipments.find{ |s| s.id == first_activity[:pickup_shipment_id] }.pickup.point :
              first_activity[:delivery_shipment_id] ?
              vrp.shipments.find{ |s| s.id == first_activity[:delivery_shipment_id] }.delivery.point :
              nil
          end
          route[:activities].insert 0, {
            point_id: start_point.id
          }
          if !vehicle.end_point.nil?
            end_point = vehicle.end_point
          else
            last_activity = route[:activities].reverse.find{ |a| a[:service_id] || a[:pickup_shipment_id] || a[:delivery_shipment_id] }
            end_point = last_activity[:service_id] ?
              vrp.services.find{ |s| s.id == last_activity[:service_id] }.activity.point :
              last_activity[:pickup_shipment_id] ?
              vrp.shipments.find{ |s| s.id == last_activity[:pickup_shipment_id] }.pickup.point :
              last_activity[:delivery_shipment_id] ?
              vrp.shipments.find{ |s| s.id == last_activity[:delivery_shipment_id] }.delivery.point :
              nil
          end
          route[:activities] << {
            point_id: end_point.id
          }
        }
        result
      else
        m = /Exception: (.+)\n/.match(result) if result
        raise RuntimeError.new((m && m[1]) || 'Unexpected exception')
      end
    end

    def kill
      @semaphore.synchronize {
        Process.kill("KILL", @thread.pid)
        @killed = true
      }
    end

    private

    def assert_jsprit_start_or_end(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        vehicle.start_point.nil? && vehicle.end_point.nil?
      }.nil?
    end

    def run_jsprit(matrix_time, matrix_distance, vehicles, services, shipments, resolution_duration, resolution_iterations, resolution_iterations_without_improvment, resolution_stable_iterations, resolution_stable_coefficient, nearby, threads, &block)
      builder = Nokogiri::XML::Builder.new(encoding: 'UTF-8') do |xml|
        xml.problem(xmlns: 'http://www.w3schools.com', ' xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance', 'xsi:schemaLocation' => 'http://www.w3schools.com vrp_xml_schema.xsd') {
          xml.problemType {
            xml.fleetSize 'FINITE'
          }
          xml.vehicles {
            vehicles.each do |vehicle|
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
                if vehicle.timewindows.size > 0
                  vehicle.timewindows.each do |timewindow|
                    xml.timeSchedule {
                      xml.start timewindow.start || 0
                      xml.end timewindow.end || 2**31
                    }
                  end
                else
                  xml.timeSchedule {
                    xml.start 0
                    xml.end 2**31
                  }
                end
                if vehicle.rests.size > 0
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
                    }
                  end
                end
                if vehicle.skills.size > 0
                  xml.alternativeSkills {
                    vehicle.skills.each do |skills|
                      xml.skillList skills.join(",") if skills.size > 0
                    end
                  }
                end
                (xml.duration vehicle.duration) if vehicle.duration
              }
            end
          }
          xml.vehicleTypes {
            vehicles.each do |vehicle|
              xml.type {
                xml.id_ vehicle.id
                xml.method_missing('capacity-dimensions') {
                  (!vehicle.quantities.empty? ? vehicle.quantities[0][:values] : [2**30]).each_with_index do |value, index|
                    xml.dimension value, index: index
                  end
                }
                xml.costs {
                  (xml.fixed vehicle.cost_fixed)
                  (xml.distance vehicle.cost_distance_multiplier)
                  (xml.time vehicle.cost_time_multiplier)
                  (xml.setup vehicle.cost_setup_time_multiplier)
                }
              }
            end
          }
          if services.size > 0
            xml.services {
              services.each do |service|
                xml.service(id: service.id, type: 'service') {
                  xml.location {
                    xml.index service.activity.point.matrix_index
                  }
                  if service.activity.timewindows.size > 0
                    xml.timeWindows {
                      service.activity.timewindows.each do |activity_timewindow|
                        xml.timeWindow {
                          xml.start activity_timewindow.start || 0
                          xml.end activity_timewindow.end || 2**31
                        }
                      end
                    }
                  end
                  (xml.setupDuration service.activity.setup_duration) if service.activity.setup_duration > 0
                  (xml.duration service.activity.duration) if service.activity.duration > 0
                  (xml.requiredSkills service.skills.join(",")) if service.skills.size > 0
                  xml.method_missing('capacity-dimensions') {
                    (!service.quantities.empty? ? service.quantities[0][:values] : [1]).each_with_index do |value, index|
                      xml.dimension value, index: index
                    end
                  }
                }
              end
            }
          end
          if shipments.size > 0
            xml.shipments {
              shipments.each do |shipment|
                xml.shipment(id: shipment.id) {
                  xml.pickup {
                    xml.location {
                      xml.index shipment.pickup.point.matrix_index
                    }
                    if shipment.pickup.timewindows.size > 0
                      xml.timeWindows {
                        shipment.pickup.timewindows.each do |activity_timewindow|
                          xml.timeWindow {
                            xml.start activity_timewindow.start || 0
                            xml.end activity_timewindow.end || 2**31
                          }
                        end
                      }
                    end
                    (xml.setupDuration shipment.pickup.setup_duration) if shipment.pickup.setup_duration > 0
                    (xml.duration shipment.pickup.duration) if shipment.pickup.duration > 0
                  }
                  xml.delivery {
                     xml.location {
                      xml.index shipment.delivery.point.matrix_index
                    }
                    if shipment.delivery.timewindows.size > 0
                      xml.timeWindows {
                        shipment.delivery.timewindows.each do |activity_timewindow|
                          xml.timeWindow {
                            xml.start activity_timewindow.start || 0
                            xml.end activity_timewindow.end || 2**31
                          }
                        end
                      }
                    end
                    (xml.setupDuration shipment.delivery.setup_duration) if shipment.delivery.setup_duration > 0
                    (xml.duration shipment.delivery.duration) if shipment.delivery.duration > 0
                  }
                  (xml.requiredSkills shipment.skills.join(",")) if shipment.skills.size > 0
                  xml.method_missing('capacity-dimensions') {
                    (!shipment.quantities.empty? ? shipment.quantities[0][:values] : [1]).each_with_index do |value, index|
                      xml.dimension value, index: index
                    end
                  }
                }
              end
            }
          end
        }
      end

      input_problem = Tempfile.new('optimize-jsprit-input_problem', tmpdir=@tmp_dir)
      input_problem.write(builder.to_xml)
      input_problem.close

      input_algorithm = Tempfile.new('optimize-jsprit-input_algorithm', tmpdir=@tmp_dir)
      input_algorithm.write(algorithm_config(resolution_iterations))
      input_algorithm.close

      if matrix_time
        input_time_matrix = Tempfile.new('optimize-jsprit-input_time_matrix', tmpdir=@tmp_dir)
        input_time_matrix.write(matrix_time.collect{ |a| a.join(" ") }.join("\n"))
        input_time_matrix.close
      end

      if matrix_distance
        input_distance_matrix = Tempfile.new('optimize-jsprit-input_distance_matrix', tmpdir=@tmp_dir)
        input_distance_matrix.write(matrix_distance.collect{ |a| a.join(" ") }.join("\n"))
        input_distance_matrix.close
      end

      output = Tempfile.new(['optimize-jsprit-output', '.xml'], tmpdir=@tmp_dir)
      output.close


      cmd = ["#{@exec_jsprit} ",
        "--algorithm '#{input_algorithm.path}'",
        input_time_matrix ? "--time_matrix '#{input_time_matrix.path}'" : '',
        input_distance_matrix ? "--distance_matrix '#{input_distance_matrix.path}'" : '',
        resolution_duration ? "--ms '#{resolution_duration}'" : '',
        nearby ? "--nearby" : '',
        resolution_iterations_without_improvment ? "--no_improvment_iterations '#{resolution_iterations_without_improvment}'" : '',
        resolution_stable_iterations && resolution_stable_coefficient ? "--stable_iterations '#{resolution_stable_iterations}' --stable_coef '#{resolution_stable_coefficient}'" : '',
        "--threads '#{threads}'",
        "--instance '#{input_problem.path}' --solution '#{output.path}'"].join(' ')
      puts cmd
      stdin, stdout_and_stderr, @thread = @semaphore.synchronize {
        Open3.popen2e(cmd) if !@killed
      }
      return if !@thread

      out = nil
      iterations = 0
      iterations_start = 0
      cost = nil
      fresh_output = nil
      # read of stdout_and_stderr stops at the end of process
      stdout_and_stderr.each_line { |line|
        puts (@job ? @job + ' - ' : '') + line
        out = out ? out + "\n" + line : line
        iterations_start += 1 if /\- iterations start/.match(line)
        if iterations_start == 2
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
        block.call(self, iterations, resolution_iterations, cost, fresh_output && parse_output(output.path, iterations, services, shipments)) if block
        fresh_output = nil
      }

      if @thread.value == 0
        parse_output(output.path, iterations, services, shipments)
      else
        out
      end
    ensure
      input_problem && input_problem.unlink
      input_algorithm && input_algorithm.unlink
      input_time_matrix && input_time_matrix.unlink
      input_distance_matrix && input_distance_matrix.unlink
      output && output.unlink
    end

    def parse_output(path, iterations, services, shipments)
      doc = Nokogiri::XML(File.open(path))
      doc.remove_namespaces!
      solution = doc.xpath('/problem/solutions/solution').last
      if solution
        {
          cost: Float(solution.at_xpath('cost').content),
          iterations: iterations,
          routes: solution.xpath('routes/route').collect{ |route|
            {
              vehicle_id: route.at_xpath('vehicleId').content,
              start_time: Float(route.at_xpath('start').content),
              end_time: Float(route.at_xpath('end').content),
              activities: route.xpath('act').collect{ |act|
                {
#                  activity: act.attr('type').to_sym,
                  pickup_shipment_id: (a = act.at_xpath('shipmentId')) && a && act['type'] == 'pickupShipment' && a.content,
                  delivery_shipment_id: (a = act.at_xpath('shipmentId')) && a && act['type'] == 'deliverShipment' && a.content,
                  service_id: (a = act.at_xpath('serviceId')) && a && a.content,
                  rest_id: (a = act.at_xpath('restId')) && a && a.content,
                  arrival_time: (a = act.at_xpath('arrTime')) && a && Float(a.content),
                  departure_time: (a = act.at_xpath('endTime')) && a && Float(a.content),
                  ready_time: (a = act.at_xpath('readyTime')) && a && Float(a.content),
                }.delete_if { |k, v| !v }
              }
            }
          },
          unassigned: solution.xpath('unassignedJobs/job').collect{ |job| {
            (services.find{ |s| s.id == job.attr('id')} ? :service_id : shipments.find{ |s| s.id == job.attr('id')} ? :shipment_id : nil) => job.attr('id')
          }}
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
        <memory>3</memory>
        <searchStrategies>
            <searchStrategy name="randomRuinLarge">
                <selector name="selectBest"/>
                <acceptor name="schrimpfAcceptance">
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
                <acceptor name="schrimpfAcceptance">
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
                <acceptor name="schrimpfAcceptance">
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
                <acceptor name="schrimpfAcceptance">
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
