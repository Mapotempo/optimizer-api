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
require 'grape'
require 'grape-swagger'
require 'date'
require 'digest/md5'
require 'csv'
require 'rest_client'
require './api/v01/api_base'
require './api/v01/entities/status'
require './api/v01/entities/vrp_result'
require './api/v01/vrp'
class VRPNoSolutionError < StandardError; end
class VRPUnprocessableError < StandardError; end
module Api
  module V01
    module CSVParser
      def self.call(object, env)
        # TODO use encoding from Content-Type or detect it.
        CSV.parse(object.force_encoding('utf-8'), headers: true).collect{ |row|
          r = row.to_h

          r.keys.each{ |key|
            if key.include?('.')
              part = key.split('.', 2)
              r.deep_merge!({part[0] => {part[1] => r[key]}})
              r.delete(key)
            end
          }

          json = r['json']
          if json # Open the secret short cut
            r.delete('json')
            r.deep_merge!(JSON.parse(json))
          end

          r
        }
      end
    end

    class Buildroute < APIBase
      content_type :json, 'application/json; charset=UTF-8'
      content_type :xml, 'application/xml'
      content_type :csv, 'text/csv;'
      parser :csv, CSVParser
      default_format :json

      namespace :buildroute do
        resource :submit do
          desc 'Submit Buildroute problem', {
              nickname: 'Buildroute',
              succs: VrpResult,
              failure: [
                  {code: 404, message: 'Not Found', model: ::Api::V01::Status}
              ],
              detail: 'Submit vehicle routing problem. If the problem can be quickly solved, the solution is returned in the response. In other case, the response provides a job identifier in a queue: you need to perfom another request to fetch vrp job status and solution.'
          }


          post do
            begin
              orders = params[:orders]
              vehiclesInput = params[:vehicles]
              apikey = params[:api_key]
              points = []

              shipments = []
              services = []
              vehicles = []
              units = [
                  {
                      id: 'unit_1'
                  }
              ]

              #get location coordinate
              orders.collect { |order|
                pickup = nil
                delivery = nil
                pickupRefe = ''
                deliverRef = ''
                pickup_lat = order[:pickup_lat].to_s.to_f || 0
                pickup_lng = order[:pickup_lng].to_s.to_f || 0
                delivery_lat = order[:delivery_lat].to_s.to_f || 0
                delivery_lng = order[:delivery_lng].to_s.to_f || 0

                if (pickup_lat != 0 && pickup_lng != 0)
                  pLon = order[:pickup_lng]
                  id = pickup_lat.to_s + ',' + pickup_lng.to_s
                  pickupRefe = id
                  sPoint = {
                      id: id,
                      location: {
                          lat: pickup_lat,
                          lon: pickup_lng
                      }
                  }
                  points.push(sPoint)
                  pickup = sPoint
                end
                if (delivery_lat != 0 &&  delivery_lng != 0)
                  dLat = delivery_lat
                  puts "delivery lat = #{delivery_lat}"
                  dLon = delivery_lng
                  id = delivery_lat.to_s + ',' + delivery_lng.to_s
                  deliverRef = id
                  sPoint = {
                      id: id,
                      location: {
                          lat: delivery_lat,
                          lon: delivery_lng
                      }
                  }
                  points.push(sPoint)
                  delivery = sPoint
                end

                if (pickup != nil && delivery != nil)
                  shipment = {
                      id: order[:reference],
                      maximum_inroute_duration: nil,
                      pickup: {
                          point_id: pickupRefe,
                          timewindows: [{
                              start: order[:pickup_start].to_s.to_i || 0,
                              end: order[:pickup_end].to_s.to_i || 0
                          }],
                          setup_duration: order[:pickup_setup].to_s.to_d || 0,
                          duration: order[:pickup_duration].to_s.to_d || 0
                      },
                      delivery: {
                          point_id: deliverRef,
                          timewindows: [{
                              start: order[:delivery_start].to_s.to_i,
                              end: order[:delivery_end].to_s.to_i
                          }],
                          setup_duration: order[:delivery_setup].to_s.to_d || 0,
                          duration: order[:delivery_duration].to_s.to_d || 0
                      },
                      quantities: [
                        {
                          unit_id: 'unit_1',
                          value: 10.92
                        }
                      ],
                      skills: ''
                  }
                  shipments.push(shipment)
                elsif (pickup != nil)
                  service = {
                      id: order[:reference],
                      type: 'pickup',
                      activity: {
                          point_id: pickupRefe,
                          timewindows: [{
                              start: order[:pickup_start].to_s.to_i,
                              end: order[:pickup_end].to_s.to_i
                          }],
                          setup_duration: order[:pickup_setup].to_s.to_d || 0,
                          duration: order[:pickup_duration].to_s.to_d || 0
                      },
                      quantities: [
                        {
                          unit_id: 'unit_1',
                          value: 10.92
                        }
                      ],
                      skills: ''
                  }
                  services.push(service)
                elsif (delivery != nil)
                  service = {
                      id: order[:reference],
                      type: 'delivery',
                      activity: {
                          point_id: deliverRef,
                          timewindows: [{
                              start: order[:delivery_start].to_s.to_i,
                              end: order[:delivery_end].to_s.to_i
                          }],
                          setup_duration: order[:delivery_setup].to_s.to_d || 0,
                          duration: order[:delivery_duration].to_s.to_d || 0
                      },
                      quantities: 1,
                      skills: ''
                  }
                  services.push(service)
                 end
              }
              vehiclesInput.collect{ |v|
                startRef = ''
                endRef = ''
                if ((v[:start_lat]) && (v[:start_lng]))
                  sLat = v[:start_lat]
                  sLon = v[:start_lng]
                  id = sLat.to_s + ',' + sLon.to_s
                  startRef = id
                  sPoint = {
                      id: id,
                      location: {
                          lat: sLat,
                          lon: sLon
                      }
                  }
                  points.push(sPoint)
                end
                if ((v[:end_lat]) && (v[:end_lng]))
                  eLat = v[:end_lat]
                  eLon = v[:end_lng]
                  id = eLat.to_s + ',' + eLon.to_s
                  endRef = id
                  sPoint = {
                      id: id,
                      location: {
                          lat: eLat,
                          lon: eLon
                      }
                  }
                  points.push(sPoint)
                end

                capacities = [
                    {
                        unit_id: 'unit_1',
                        limit:700
                    }
                ]
                vehicle = {
                    id: v[:reference],
                    start_point_id: startRef,
                    end_point_id: endRef,
                    capacities: capacities,
                    timewindows: [{
                        start: v[:start_time].to_s.to_i || 0,
                        end: v[:end_time].to_s.to_i || 0
                    }],
                    duration: v[:duration] || 0,
                    router_mode: v[:router_mode] || 'crow',
                    router_dimension: v[:router_dimension] || 'time',
                    speed_multiplier: v[:speed_multiplie] || 1
                }
                vehicles.push(vehicle)
              }

              vrp = {
                  points: points,
                  units: units,
                  shipments: shipments,
                  services: services,
                  vehicles: vehicles,
                  configuration: {
                      preprocessing: {
                          cluster_threshold: 0
                      },
                      resolution: {
                          duration: 600000 ,
                          iterations: 1000,
                          iterations_without_improvment: 100,
                          minimum_duration: 3000
                      }
                  }
              }
              rooturl = "http://localhost:1791/0.1/"
              resource_vrp = RestClient::Resource.new(rooturl + 'vrp/submit.json', timeout: nil)
              json = resource_vrp.post({api_key: apikey, vrp: vrp}.to_json, content_type: :json, accept: :json) { |response, request, result, &block|
                if response.code != 200 && response.code != 201
                  json = (response && /json/.match(response.headers[:content_type]) && response.size > 1) ? JSON.parse(response) : nil
                  msg = if json && json['message']
                          json['message']
                        elsif json && json['error']
                          json['error']
                        end
                  raise VRPUnprocessableError, msg || 'Unexpected error'
                end
                response
              }
              result = nil
              while json
                result = JSON.parse(json)
                if result['job']['status'] == 'completed'
                  break
                elsif ['queued', 'working'].include?(result['job']['status'])
                  sleep(2)
                  job_id = result['job']['id']
                  json = RestClient.get(rooturl + "vrp/jobs/#{job_id}.json", params: {api_key: apikey})
                else
                  if /No solution provided/.match result['job']['avancement']
                    raise VRPNoSolutionError.new
                  else
                    raise RuntimeError.new(result['job']['avancement'] || 'Optimizer return unknown error')
                  end
                end
              end
              result
          end
        end
      end
    end
  end
  end
end





