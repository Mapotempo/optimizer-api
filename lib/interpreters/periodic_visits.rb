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

module Interpreters
  class PeriodicVisits

    def self.expand(vrp)
      if vrp.schedule_range_indices || vrp.schedule_range_date
        epoch = Date.new(1970,1,1)
        schedule_start = vrp.schedule_range_indices ? vrp.schedule_range_indices[0] : (vrp.schedule_range_date[:start] - epoch).to_i
        schedule_end = vrp.schedule_range_indices ? vrp.schedule_range_indices[1] : (vrp.schedule_range_date[:end] - epoch).to_i

        unavailable_indices = if vrp.schedule_unavailable_indices
          schedule_unavailable_indices
        elsif vrp.schedule_unavailable_date
          vrp.schedule_unavailable_date.collect{ |date|
            (date - epoch).to_i if (date - epoch).to_i >= schedule_start
          }.compact
        end

        new_vehicles = vrp.vehicles.collect { |vehicle|

          if vehicle.particular_unavailable_date
            vehicle.particular_unavailable_indice = vehicle.particular_unavailable_date.collect{ |particular_date|
              (particular_date - epoch).to_i if particular_date >= schedule_start
            }.compact
          end

          if vehicle.static_interval_date
            vehicle.static_interval_indices = vehicle.static_interval_date.collect{ |static_interval|
              [(static_interval[:start] >= vrp.schedule_range_date[:start] ? (static_interval[:start] - epoch).to_i : schedule_start), (static_interval[:end] <= vrp.schedule_range_date[:end] ? (static_interval[:end] - epoch).to_i : schedule_end)] if static_interval[:start] >= schedule_start || static_interval[:end] <= schedule_end
            }.compact
          end

          if vehicle.sequence_timewindows || vehicle.static_interval_indices
            (schedule_start..schedule_end).collect{ |vehicle_day_index|
              sequence_vehicle_index = ((vehicle_day_index - schedule_start)%vehicle.sequence_timewindows.size).to_i
              if !vehicle.particular_unavailable_indices || vehicle.particular_unavailable_indices.none?{ |index| index == vehicle_day_index}
                if (vehicle.sequence_timewindows[(sequence_vehicle_index + vehicle.sequence_timewindow_start_index)%vehicle.sequence_timewindows.size][:start] || vehicle.sequence_timewindows[(sequence_vehicle_index + vehicle.sequence_timewindow_start_index)%vehicle.sequence_timewindows.size][:end]) && 
                (!vehicle.static_interval_indices || vehicle.static_interval_indices && vehicle.static_interval_indices.any?{ |interval| interval[0] <= vehicle_day_index && interval[1] >= vehicle_day_index })
                  original_timewindow = vehicle.sequence_timewindows[(sequence_vehicle_index + vehicle.sequence_timewindow_start_index)%vehicle.sequence_timewindows.size]
                  new_vehicle = Marshal::load(Marshal.dump(vehicle))
                  new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index+1}"
                  new_vehicle.timewindow = {
                    start: vehicle_day_index * 86400 + original_timewindow[:start],
                    end: vehicle_day_index * 86400 + original_timewindow[:end]
                  }
                  new_vehicle.rests.collect!{ |rest|
                    new_rest  = Marshal::load(Marshal.dump(rest))
                    timewindows = new_rest.timewindows.collect!{ |timewindow|
                      {
                        start: vehicle_day_index * 86400 + timewindow[:start],
                        end: vehicle_day_index * 86400 + timewindow[:end]
                      }
                    }
                    new_rest[:id] = "#{new_rest[:id]}_#{vehicle_day_index+1}"
                    new_rest
                  }
                  new_vehicle.day_index = vehicle_day_index
                  new_vehicle
                end
              end
            }.compact
          else
            vehicle
          end
        }.flatten

        vrp.vehicles = new_vehicles

        new_services = vrp.services.collect{ |service|

          if service.particular_unavailable_date
            service.particular_unavailable_indices = service.particular_unavailable_date.collect{ |particular_date|
              (particular_date - epoch).to_i if particular_date >= schedule_start
            }.compact
          end

          if service.static_interval_date
            service.static_interval_indices = service.static_interval_date.collect{ |static_interval|
              [static_interval[:start] >= vrp.schedule_range_date[:start] ? (static_interval[:start] - epoch).to_i : schedule_start, static_interval[:end] <= vrp.schedule_range_date[:end] ? (static_interval[:end] - epoch).to_i : schedule_end] if static_interval[:start] >= schedule_start || static_interval[:end] <= schedule_end
            }.compact
          end

          if service.visits_number
            day_range = (service.activity.timewindows.last[:end].to_f/86400).ceil - (service.activity.timewindows.first[:start].to_f/86400).floor
            ## Create as much service as needed
            (0..service.visits_number-1).collect{ |visit_index|
              new_service = Marshal::load(Marshal.dump(service))
              new_service.id = "#{new_service.id}_#{visit_index+1}/#{new_service.visits_number}"
              new_service.activity.timewindows = if service.static_interval_indices
                (service.static_interval_indices[visit_index][0]..service.static_interval_indices[visit_index][1]).collect{ |index|
                  service.activity.timewindows.collect{ |timewindow|
                    ## Extract the right timewindows to the current index day
                    if service.particular_unavailable_indices.none?{ |unavailable| unavailable == index} && (timewindow[:start].to_f/86400) >= (index - service.activity.timewindow_start_day_shift_number)%day_range &&
                    (timewindow[:end].to_f/86400) < (index - service.activity.timewindow_start_day_shift_number)%day_range + 1
                      {
                        start: timewindow[:start]%86400 + (index)* 86400,
                        end: timewindow[:end]%86400 + (index) * 86400
                      }
                    end
                  }.compact
                }.flatten
              elsif service.visits_range_days_number
                service.activity.timewindows.collect{ |timewindow|
                  if service.particular_unavailable_indices.none?{ |unavailable| unavailable * 86400 == timewindow[:start] + 86400 * (visit_index * (service.visits_range_days_number + service.activity.timewindow_start_day_shift_number) + schedule_start) }
                    {
                      start: timewindow[:start] + 86400 * (schedule_start + visit_index * (service.visits_range_days_number + service.activity.timewindow_start_day_shift_number)%(service.visits_range_days_number + 1)),
                      end: timewindow[:end] + 86400 * (schedule_start + visit_index * (service.visits_range_days_number + service.activity.timewindow_start_day_shift_number)%(service.visits_range_days_number + 1))
                    }
                  end
                }.compact.flatten
              end
              new_service
            }
          else
            service
          end
        }.flatten

        vrp.services = new_services

      end
      vrp
    end

  end
end
