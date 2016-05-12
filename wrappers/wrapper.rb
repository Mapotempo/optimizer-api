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
module Wrappers
  class Wrapper
    def initialize(cache, hash = {})
      @cache = cache
      @tmp_dir = hash[:tmp_dir] || Dir.tmpdir
    end

    def solve?(vrp)
      false
    end

    def assert_units_only_one(vrp)
      vrp.units.size <= 1
    end

    def assert_vehicles_only_one(vrp)
      vrp.vehicles.size <= 1
    end

    def assert_vehicles_start(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        vehicle.start_point.nil?
      }.nil?
    end

    def assert_vehicles_no_timewindows(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        !vehicle.timewindows.empty?
      }.nil?
    end

    def assert_vehicles_no_rests(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        !vehicle.rests.empty?
      }.nil?
    end

    def assert_services_no_quantities(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        !service.quantities.empty?
      }.nil?
    end

    def assert_vehicles_quantities_only_one(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicles|
        vehicles.quantities.size > 1
      }.nil?
    end

    def assert_vehicles_timewindows_only_one(vrp)
      vrp.vehicles.empty? || vrp.vehicles.find{ |vehicle|
        vehicle.timewindows.size > 1
      }.nil?
    end

    def assert_no_shipments(vrp)
      vrp.shipments.empty?
    end

    def assert_services_no_skills(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        !service.skills.empty?
      }.nil?
    end

    def assert_services_no_timewindows(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        !service.activity.timewindows.empty?
      }.nil?
    end

    def assert_services_no_multiple_timewindows(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        service.activity.timewindows.size > 1
      }.nil?
    end

    def assert_services_no_exclusion_cost(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        !service.exclusion_cost.nil?
      }.nil?
    end

    def assert_services_no_late_multiplier(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        service.late_multiplier
      }.nil?
    end

    def assert_services_quantities_only_one(vrp)
      vrp.services.empty? || vrp.services.find{ |service|
        service.quantities.size > 1
      }.nil?
    end
  end
end
