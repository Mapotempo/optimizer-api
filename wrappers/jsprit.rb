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


module Wrappers
  class Jsprit < Wrapper
    def initialize(cache, hash = {})
      super(cache, hash)
      @exec_jsprit = hash[:exec_jsprit] || 'java -jar ../mapotempo-optimizer-jsprit/target/mapotempo-jsprit-0.0.1-SNAPSHOT-jar-with-dependencies.jar'
    end

    def solve?(vrp)
      assert_units_only_one(vrp) &&
      assert_vehicles_quantities_only_one(vrp) &&
      assert_vehicles_timewindows_only_one(vrp) &&
      assert_services_no_skills(vrp) &&
      assert_services_no_late_multiplier(vrp) &&
      assert_services_no_exclusion_cost(vrp) &&
      assert_services_quantities_only_one(vrp) &&
      assert_no_shipments(vrp) &&
      assert_jsprit_start_or_end(vrp)
    end

    def solve(vrp, &block)
      result = run_jsprit(vrp.matrix_time, vrp.matrix_distance, vrp.vehicles, vrp.services, vrp.shipments)
      if result
        vehicles = Hash[vrp.vehicles.collect{ |vehicle| [vehicle.id, vehicle] }]
        result[:routes].each{ |route|
          vehicle = vehicles[route[:vehicle_id]]
          if !vehicle.start_point.nil?
            route[:activities].insert 0, {
              point_id: vehicle.start_point.id
            }
          end
          if !vehicle.end_point.nil?
            route[:activities] << {
              point_id: vehicle.end_point.id
            }
          end
        }
        result
      end
    end

    private

    def assert_jsprit_start_or_end(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        vehicle.start_point.nil? && vehicle.end_point.nil?
      }.nil?
    end

    def run_jsprit(matrix_time, matrix_distance, vehicles, services, shipments)
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
                      xml.start timewindow.start
                      xml.end timewindow.end
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
                            xml.start timewindow.start.nil? ? 0 : timewindow.start
                            xml.end timewindow.end.nil? ? 2**31 : timewindow.end
                          }
                        end
                      }
                      xml.duration rest.duration
                    }
                  end
                end
              }
            end
          }
          xml.vehicleTypes {
            vehicles.each do |vehicle|
              xml.type {
                xml.id_ vehicle.id
                xml.method_missing('capacity-dimensions') {
                  (!vehicle.quantities.empty? ? vehicle.quantities[0].values : [2**30]).each_with_index do |value, index|
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
                          xml.start activity_timewindow.start.nil? ? 0 : activity_timewindow.start
                          xml.end activity_timewindow.end.nil? ? 2**31 : activity_timewindow.end
                        }
                      end
                    }
                  end
                  (xml.setupDuration service.activity.setup_duration) if service.activity.setup_duration > 0
                  (xml.duration service.activity.duration) if service.activity.duration > 0
                  xml.method_missing('capacity-dimensions') {
                    (!service.quantities.empty? ? service.quantities[0].values : [1]).each_with_index do |value, index|
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
                xml.shipment {
                  xml.pickup {
                    xml.location {
                      xml.index shipment.pickup_activity.point.matrix_index
                    }
                    xml.timeWindows {
                      shipment.pickup_activity.timewindows.each do |activity_timewindow|
                        xml.timeWindow {
                          xml.start activity_timewindow.start
                          xml.end activity_timewindow.end
                        }
                      end
                    }
                    (xml.setupDuration shipment.pickup_activity.duration) if shipment.pickup_activity.setup_duration > 0
                    (xml.duration shipment.pickup_activity.duration) if shipment.pickup_activity.duration > 0
                  }
                  xml.delivery {
                     xml.location {
                      xml.index shipment.delivery_point.matrix_index
                    }
                    xml.timeWindows {
                      shipment.delivery_activity.timewindows.each do |activity_timewindow|
                        xml.timewindow {
                          xml.start activity_timewindow.start
                          xml.end activity_timewindow.end
                        }
                      end
                    }
                    (xml.setupDuration shipment.delivery_activity.setup_duration) if shipment.delivery_activity.setup_duration > 0
                    (xml.duration shipment.delivery_activity.duration) if shipment.delivery_activity.duration > 0
                  }
                  xml.method_missing('capacity-dimensions') {
                    (!service.quantities.empty? ? service.quantities[0].values : [1]).each_with_index do |value, index|
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

      cmd = "#{@exec_jsprit} " + (input_time_matrix ? "--time_matrix '#{input_time_matrix.path}'" : '') + " " + (input_distance_matrix ? "--distance_matrix '#{input_distance_matrix.path}'" : '') + " --instance '#{input_problem.path}' --solution '#{output.path}'"
      puts cmd
      out = system(cmd)

      if $?.exitstatus == 0
        doc = Nokogiri::XML(File.open(output.path))
        doc.remove_namespaces!
        solution = doc.at_xpath('/problem/solutions/solution')
        if solution
          {
            cost: solution.at_xpath('cost').content,
            routes: solution.xpath('routes/route').collect{ |route| {
              vehicle_id: route.at_xpath('vehicleId').content,
              start_time: Float(route.at_xpath('start').content),
              end_time: Float(route.at_xpath('end').content),
              activities: route.xpath('act').collect{ |act| {
                service_id: act.at_xpath('serviceId').content,
#                activity: act.attr('type').to_sym,
                arrival_time: Float(act.at_xpath('arrTime').content),
                departure_time: Float(act.at_xpath('endTime').content),
              }}
            }},
            unassigned: solution.xpath('unassignedJobs/job').collect{ |job| {
              service_id: job.attr('id')
            }}
          }
        end
      else
        out
      end
    ensure
      input_problem && input_problem.unlink
      input_time_matrix && input_time_matrix.unlink
      input_distance_matrix && input_distance_matrix.unlink
      output && output.unlink
    end
  end
end
