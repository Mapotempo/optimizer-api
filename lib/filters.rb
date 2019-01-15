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
module Filters
  def self.filter(services_vrps)
    services_vrps = group_tws(services_vrps)

    services_vrps
  end

  def self.group_tws(services_vrps)
    services_vrps.each{ |service_vrp|
      service_vrp[:vrp].services.each{ |service|
        next if !service.activity
        new_timewindows = []
        deleted_timewindows = []
        equivalent = {}
        service.activity.timewindows.each_with_index{ |tw1, i1|
          tw1 = Marshal.load(Marshal.dump(tw1))
          if deleted_timewindows.include?(tw1) && equivalent[tw1]
            tw1 = Marshal.load(Marshal.dump(equivalent[tw1]))
          end
          tw1.start = 0 if tw1.start.nil?
          tw1.end = Float::INFINITY if tw1.end.nil?

          if service.activity.timewindows.size == 1
            new_timewindows << Marshal.load(Marshal.dump(tw1))
          end
          service.activity.timewindows.slice(i1 + 1, service.activity.timewindows.size).each{ |tw2|
            tw2 = Marshal.load(Marshal.dump(tw2))
            tw2.start = 0 if tw2.start.nil?
            tw2.end = Float::INFINITY if tw1.end.nil?
            compatible_day = tw1.day_index == tw2.day_index || tw1.day_index.nil? || tw2.day_index.nil?

            if compatible_day && (tw2.start.between?(tw1.start, tw1.end) || tw1.start.between?(tw2.start, tw2.end))
              main_tw = tw1
              to_group_tw = tw2
              if tw1.start.between?(tw2.start, tw2.end)
                main_tw = tw2
                to_group_tw = tw1
              end

              if main_tw.day_index.nil? && to_group_tw.day_index.nil? || (!main_tw.day_index.nil? && !to_group_tw.day_index.nil?)
                deleted_timewindows << Marshal.load(Marshal.dump(main_tw))
                main_tw.end = [main_tw.end, to_group_tw.end].max
                equivalent[deleted_timewindows.last] = Marshal.load(Marshal.dump(main_tw))
                new_timewindows << Marshal.load(Marshal.dump(main_tw))
                deleted_timewindows << to_group_tw
              elsif main_tw.day_index
                deleted_timewindows << Marshal.load(Marshal.dump(main_tw))
                main_tw.end = [main_tw.end, to_group_tw.end].max
                equivalent[deleted_timewindows.last] = Marshal.load(Marshal.dump(main_tw))
                new_timewindows << Marshal.load(Marshal.dump(main_tw))
                new_timewindows << Marshal.load(Marshal.dump(to_group_tw))
              else
                deleted_timewindows << Marshal.load(Marshal.dump(to_group_tw))
                to_group_tw.start = [main_tw.start, to_group_tw.start].min
                to_group_tw.end = [main_tw.end, to_group_tw.end].max
                equivalent[deleted_timewindows.last] = Marshal.load(Marshal.dump(to_group_tw))
                new_timewindows << Marshal.load(Marshal.dump(main_tw))
                new_timewindows << Marshal.load(Marshal.dump(to_group_tw))
              end
            else
              new_timewindows << Marshal.load(Marshal.dump(tw1))
              new_timewindows << Marshal.load(Marshal.dump(tw2))
            end
          }
        }
        new_timewindows.each{ |tw|
          tw.end = nil if tw.end == Float::INFINITY
        }
        service.activity.timewindows = new_timewindows.delete_if{ |tw| deleted_timewindows.any?{ |tw2| tw.start == tw2.start && tw.end == tw2.end }}.uniq
      }
    }
  end
end
