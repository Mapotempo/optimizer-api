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

# RestClient.log = $stdout

class RouterError < StandardError; end

module Routers
  class RouterWrapper
    attr_accessor :cache_request, :cache_result, :api_key

    def initialize(cache_request, cache_result, api_key)
      @cache_request, @cache_result = cache_request, cache_result
      @api_key = api_key
    end

    def compute_batch(url, mode, dimension, segments, polyline, options = {})
      results = {}
      nocache_segments = []
      segments.each{ |s|
        key_segment = ['c', url, mode, dimension, Digest::MD5.hexdigest(Marshal.dump([s, options.to_a.sort_by{ |i| i[0].to_s }]))]
        request_segment = @cache_request.read key_segment
        if request_segment
          results[s] = JSON.parse request_segment
        else
          nocache_segments << s if !request_segment
        end
      }
      if !nocache_segments.empty?
        format = polyline ? 'json' : 'geojson'
        nocache_segments.each_slice(50){ |slice_segments|
          resource = RestClient::Resource.new(url + "/routes.#{format}", timeout: nil)
          request = resource.post(params(mode, dimension, options).merge({
            locs: slice_segments.collect{ |segment| segment.join(',') }.join('|')
          })) { |response, _request, result, &_block|
            case response.code
            when 200
              response
            when 204 # UnreachablePointError
              ''
            when 417 # OutOfSupportedAreaError
              ''
            else
              response = (response && /json/.match(response.headers[:content_type]) && response.size > 1) ? JSON.parse(response) : nil
              raise RouterError.new(result.message + (response && response['message'] ? ' - ' + response['message'] : ''))
            end
          }
          if request != ''
            datas = JSON.parse request
            if datas && datas.has_key?('features') && !datas['features'].empty?
              slice_segments.each_with_index{ |s, i|
                data = datas['features'][i]
                if data
                  key_segment = ['c', url, mode, dimension, Digest::MD5.hexdigest(Marshal.dump([s, options.to_a.sort_by{ |ii| ii[0].to_s }]))]
                  @cache_request.write(key_segment, data.to_json)
                  results[s] = data
                end
              }
            end
          end
        }
      end

      if results.empty?
        []
      else
        segments.collect{ |segment|
          feature = results[segment]
          if feature
            distance = feature['properties']['router']['total_distance'] if feature['properties'] && feature['properties']['router']
            time = feature['properties']['router']['total_time'] if feature['properties'] && feature['properties']['router']
            trace =  if feature['geometry']
              if polyline
                feature['geometry']['polylines']
              else
                feature['geometry']['coordinates']
              end
            end
            [distance, time, trace]
          else
            [nil, nil, nil]
          end
        }
      end
    end

    def matrix(url, mode, dimensions, row, column, options = {})
      if row.empty? || column.empty?
        return [[] * row.size] * column.size
      elsif row.size == 1 && row == column
        return dimensions.map{ |d| [[0]] }
      end

      key = ['m', url, mode, dimensions, Digest::MD5.hexdigest(Marshal.dump([row, column, options.to_a.sort_by{ |i| i[0].to_s }]))]

      request = @cache_request.read(key)
      if !request
        resource = RestClient::Resource.new(url + '/matrix.json', timeout: nil)
        request = resource.post(params(mode, dimensions.join('_'), options).merge({
          src: row.flatten.join(','),
          dst: row != column ? column.flatten.join(',') : nil,
        }.compact)) { |response, _request, result, &_block|
          case response.code
          when 200
            response
          # Disable to get info when no matrice is returned
          # when 417
          #   ''
          else
            response = (response && /json/.match(response.headers[:content_type]) && response.size > 1) ? JSON.parse(response) : nil
            raise RouterError.new(result.message + (response && response['message'] ? ' - ' + response['message'] : ''))
          end
        }

        @cache_request.write(key, request && request.to_s)
      end

      unless request.to_s.empty?
        data = JSON.parse(request)
        dimensions.collect{ |dim|
          if data.has_key?("matrix_#{dim}")
            data["matrix_#{dim}"].collect{ |r|
              r.collect{ |rr|
                rr || 2147483647
              }
            }
          end
        }
      end
    end

    def isoline(url, mode, dimension, lat, lng, size, options = {})
      key = ['i', url, mode, dimension, Digest::MD5.hexdigest(Marshal.dump([lat, lng, size, options.to_a.sort_by{ |i| i[0].to_s }]))]

      request = @cache_request.read(key)
      if !request
        resource = RestClient::Resource.new(url + '/isoline.json', timeout: nil)
        request = resource.post(params(mode, dimension, options).merge({
          loc: [lat, lng].join(','),
          size: size,
        })) { |response, _request, result, &_block|
          case response.code
          when 200
            response
          when 417
            ''
          else
            response = (response && /json/.match(response.headers[:content_type]) && response.size > 1) ? JSON.parse(response) : nil
            raise RouterError.new(result.message + (response && response['message'] ? ' - ' + response['message'] : ''))
          end
        }

        @cache_request.write(key, request && request.to_s)
      end

      if request != ''
        data = JSON.parse(request)
        if data['features']
          # MultiPolygon not supported by Leaflet.Draw
          data['features'].collect! { |feat|
            if feat['geometry']['type'] == 'LineString'
              feat['geometry']['type'] = 'Polygon'
              feat['geometry']['coordinates'] = [feat['geometry']['coordinates']]
            end
            feat
          }
          data.to_json
        end
      end
    end

    private

    def params(mode, dimension, options)
      {
        api_key: @api_key,
        mode: mode,
        dimension: dimension,
        traffic: options[:traffic],
        departure: options[:departure],
        speed_multiplier: options[:speed_multiplier] == 1 ? nil : options[:speed_multiplier],
        area: options[:area] ? options[:area].collect{ |a| a.join(',') }.join('|') : nil,
        speed_multiplier_area: options[:speed_multiplier_area] ? options[:speed_multiplier_area].join('|') : nil,
        track: options[:track],
        motorway: options[:motorway],
        toll: options[:toll],
        trailers: options[:trailers],
        weight: options[:weight],
        weight_per_axle: options[:weight_per_axle],
        height: options[:height],
        width: options[:width],
        length: options[:length],
        hazardous_goods: options[:hazardous_goods],
        max_walk_distance: options[:max_walk_distance],
        approach: options[:approach],
        snap: options[:snap],
        strict_restriction: options[:strict_restriction] || false
      }.compact
    end
  end
end
