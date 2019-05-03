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
require './models/timewindow.rb'

module Filters
  def self.filter(services_vrps)
    services_vrps = merge_timewindows(services_vrps)

    services_vrps
  end

  def self.merge_timewindows(services_vrps)
    services_vrps.each{ |service_vrp|
      service_vrp[:vrp].services.each{ |service|
        next if !service.activity
        unified_timewindows = {}
        inter = {}
        new_timewindows = []
        if service.activity.timewindows.size > 1
          service.activity.timewindows.each{ |timewindow|
            unified_timewindows[timewindow.id] = {
              start: timewindow.start && ((timewindow.day_index || 0) * 86400 + timewindow.start) || (0 + (timewindow.day_index || 0) * 86400),
              end: timewindow.end && ((timewindow.day_index || 0) * 86400 + timewindow.end) || (0 + (1 + (timewindow.day_index || 6)) * 86400)
            }
            inter[timewindow.id] = []
          }
          unified_timewindows.each{ |key, value|
            unified_timewindows.each{ |s_key, s_value|
              next if key == s_key || s_value.include?(key) || value.include?(s_key)
              if value[:start] >= s_value[:start] && value[:start] <= s_value[:end] ||
                 value[:end] >= s_value[:start] && value[:end] <= s_value[:end]
                inter[key].each{ |k_value| inter[k_value] << s_key }
                inter[s_key].each{ |k_value| inter[k_value] << key }
                inter[key] << s_key
                inter[s_key] << key
              end
            }
          }
          to_merge_ids = []
          if inter.any?{ |key, value| !value.empty? }
            inter.each{ |key, value|
              to_merge_ids = ([key] + value).uniq
              to_merge_ids.each{ |id| inter.delete(id) }
              inter.delete(to_merge_ids)
              to_merge_tws = service.activity.timewindows.select{ |timewindow| to_merge_ids.include?(timewindow.id) }
              day_indices = to_merge_tws.collect{ |tw| tw.day_index }
              starts = to_merge_tws.collect{ |tw| tw.start }
              ends = to_merge_tws.collect{ |tw| tw.end }
              earliest_day_index = day_indices.include?(nil) ? nil : day_indices.min
              latest_day_index = day_indices.include?(nil) ? nil : day_indices.max
              earliest_start = starts.include?(nil) ? nil : starts.min
              latest_end = ends.include?(nil) ? nil : ends.max
              new_timewindows << Models::Timewindow.new(start: earliest_start, end: latest_end, day_index: earliest_day_index)
            }
            service.activity.timewindows = new_timewindows
          end
        end
      }
    }
  end
end
