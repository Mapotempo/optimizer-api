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
      frequencies = []
      services_unavailable_indices = []
      if vrp.schedule_range_indices || vrp.schedule_range_date
        epoch = Date.new(1970,1,1)
        real_schedule_start = vrp.schedule_range_indices ? vrp.schedule_range_indices[:start] : (vrp.schedule_range_date[:start] - epoch).to_i
        real_schedule_end = vrp.schedule_range_indices ? vrp.schedule_range_indices[:end] : (vrp.schedule_range_date[:end] - epoch).to_i
        shift = vrp.schedule_range_indices ? vrp.schedule_range_indices[:start] : vrp.schedule_range_date[:start].cwday - 1
        schedule_end = real_schedule_end - real_schedule_start
        schedule_start = 0

        unavailable_indices = if vrp.schedule_unavailable_indices
          vrp.schedule_unavailable_indices
        elsif vrp.schedule_unavailable_date
          vrp.schedule_unavailable_date.collect{ |date|
            (date - epoch).to_i - real_schedule_start if (date - epoch).to_i >= real_schedule_start
          }.compact
        end

        new_services = vrp.services.collect{ |service|
          if service.unavailable_visit_day_date
            service.unavailable_visit_day_indices = service.unavailable_visit_day_date.collect{ |unavailable_date|
              (unavailable_date - epoch).to_i - real_schedule_start + shift if (unavailable_date - epoch).to_i >= real_schedule_start
            }.compact
            if vrp.schedule_unavailable_indices
              service.unavailable_visit_day_indices += vrp.schedule_unavailable_indices
              service.unavailable_visit_day_indices.uniq
            end
          end

          if service.visits_number
            frequencies << service.visits_number
            visit_period = (schedule_end + 1).to_f/service.visits_number
            timewindows_iterations = (visit_period /(6 || 1)).ceil
            ## Create as much service as needed
            (0..service.visits_number-1).collect{ |visit_index|
              new_service = nil
              if !service.unavailable_visit_indices || service.unavailable_visit_indices.none?{ |unavailable_index| unavailable_index == visit_index }
                new_service = Marshal::load(Marshal.dump(service))
                new_service.id = "#{new_service.id}_#{visit_index+1}/#{new_service.visits_number}"
                new_service.activity.timewindows = if service.activity.timewindows
                  new_timewindows = service.activity.timewindows.collect{ |timewindow|
                    if timewindow.day_index
                      {
                        start: timewindow[:start] + timewindow.day_index * 86400,
                        end: timewindow[:end] + timewindow.day_index * 86400
                      }
                    else
                      (0..[6, schedule_end].min).collect{ |day_index|
                        {
                          start: timewindow[:start] + (day_index).to_i * 86400,
                          end: timewindow[:end] + (day_index).to_i * 86400
                        }
                      }
                    end
                  }.flatten.sort_by{ |tw| tw[:start] }.compact.uniq
                  if new_timewindows.size > 0
                    new_timewindows
                  end
                end
                new_service.skills += ["#{visit_index+1}_f_#{service.visits_number}"]
                new_service.skills += service.unavailable_visit_day_indices.collect{ |day_index|
                  services_unavailable_indices << day_index
                  "not_#{day_index}"
                } if service.unavailable_visit_day_indices
                new_service
              else
                nil
              end
              new_service
            }.compact
          else
            service
          end
        }.flatten
        vrp.services = new_services

        services_unavailable_indices.uniq!
        frequencies.uniq!

        new_vehicles = vrp.vehicles.collect { |vehicle|
          if vehicle.unavailable_work_date
            vehicle.unavailable_work_day_indices = vehicle.unavailable_work_date.collect{ |unavailable_date|
              (unavailable_date - epoch).to_i - real_schedule_start if (unavailable_date - epoch).to_i >= real_schedule_start
            }.compact
          end
          if vrp.schedule_unavailable_indices
            vehicle.unavailable_work_day_indices += vrp.schedule_unavailable_indices
            vehicle.unavailable_work_day_indices.uniq!
          end

          if vehicle.sequence_timewindows
            new_vehicles = (schedule_start..schedule_end).collect{ |vehicle_day_index|
              if !vehicle.unavailable_work_day_indices || vehicle.unavailable_work_day_indices.none?{ |index| index - shift == vehicle_day_index}
                associated_timewindow = vehicle.sequence_timewindows.find{ |timewindow| !timewindow[:day_index] || timewindow[:day_index] == (vehicle_day_index + shift) % 7 }
                if associated_timewindow
                  new_vehicle = Marshal::load(Marshal.dump(vehicle))
                  new_vehicle.id = "#{vehicle.id}_#{vehicle_day_index+1}"
                  new_vehicle.timewindow = {
                    start: ((vehicle_day_index + shift)* 86400 + associated_timewindow[:start]) % (7 * 86400),
                    end: ((vehicle_day_index  + shift)* 86400 + associated_timewindow[:end]) % (7 * 86400)
                  }
                  new_vehicle.sequence_timewindows = nil
                  associated_rests = vehicle.rests.select{ |rest| rest.timewindows.any?{ |timewindow| timewindow[:day_index] == (vehicle_day_index + shift) % 7 } }
                  new_vehicle.rests = associated_rests.collect{ |rest|
                    new_rest = Marshal::load(Marshal.dump(rest))
                    new_rest_timewindows = new_rest.timewindows.collect{ |timewindow|
                      if timewindow[:day_index] == (vehicle_day_index + shift) % 7
                        {
                          start: ((vehicle_day_index + shift) * 86400 + timewindow[:start]) % (7 * 86400),
                          end: ((vehicle_day_index + shift) * 86400 + timewindow[:end]) % (7 * 86400)
                        }
                      end
                    }.compact
                    if new_rest_timewindows.size > 0
                      new_rest.timewindows = new_rest_timewindows
                      new_rest[:id] = "#{new_rest[:id]}_#{vehicle_day_index+1}"
                      new_rest
                    end
                  }
                  if new_vehicle.skills.empty?
                    new_vehicle.skills = [frequencies.collect { |frequency| "#{(vehicle_day_index * frequency / (schedule_end + 1)).to_i + 1}_f_#{frequency}" } + services_unavailable_indices.collect { |index|
                      if index != vehicle_day_index
                        "not_#{index}"
                      end
                    }.compact]
                  else
                    new_vehicle.skills.each{ |alternative_skill|
                      alternative_skill += frequencies.collect { |frequency| "#{(vehicle_day_index * frequency / (schedule_end + 1)).to_i + 1}_f_#{frequency}" } + services_unavailable_indices.collect { |index|
                        if index != vehicle_day_index
                          "not_#{index}"
                        end
                      }.compact
                    }
                  end
                  vrp.rests += new_vehicle.rests
                  new_vehicle
                else
                  nil
                end
              end
            }.compact
            vehicle.rests.each{ |rest|
              vrp.rests.delete(rest)
            }
            new_vehicles
          else
            vehicle
          end
        }.flatten
        vrp.vehicles = new_vehicles
      end
      vrp
    end

  end
end
