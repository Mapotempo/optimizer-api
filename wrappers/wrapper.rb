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
      @threads = hash[:threads] || 1
    end

    def job=(id)
      @job = id
    end

    def solver_constraints
      []
    end

    def inapplicable_solve?(vrp)
      solver_constraints.select{ |constraint|
        !self.send(constraint, vrp)
      }
    end

    def assert_units_only_one(vrp)
      vrp.units.size <= 1
    end

    def assert_vehicles_only_one(vrp)
      vrp.vehicles.size == 1
    end

    def assert_vehicles_at_least_one(vrp)
      vrp.vehicles.size >= 1
    end

    def assert_vehicles_start(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.start_point.nil?
      }
    end

    def assert_vehicles_no_timewindow(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.timewindow.nil?
      }
    end

    def assert_vehicles_no_rests(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        !vehicle.rests.empty?
      }
    end

    def assert_services_no_quantities(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.quantities.empty?
      }
    end

    def assert_vehicles_capacities_only_one(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.size > 1
      }
    end

    def assert_vehicles_no_capacity_initial(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |c| c.initial && c.initial != 0 }
      }
    end

    def assert_no_shipments(vrp)
      vrp.shipments.empty?
    end

    def assert_services_no_skills(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.skills.empty?
      }
    end

    def assert_services_no_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.activity.timewindows.empty?
      }
    end

    def assert_services_no_multiple_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity.timewindows.size > 1
      }
    end

    def assert_services_at_most_two_timewindows(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.activity.timewindows.size > 2
      }
    end

    def assert_services_no_exclusion_cost(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        !service.exclusion_cost.nil?
      }
    end

    def assert_vehicles_no_late_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.cost_late_multiplier && vehicle.cost_late_multiplier != 0
      }
    end

    def assert_vehicles_no_overload_multiplier(vrp)
      vrp.vehicles.empty? || vrp.vehicles.none?{ |vehicle|
        vehicle.capacities.find{ |capacity|
          capacity.overload_multiplier && capacity.overload_multiplier != 0
        }
      }
    end

    def assert_services_no_late_multiplier(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.late_multiplier && service.late_multiplier != 0
      }
    end

    def assert_services_quantities_only_one(vrp)
      vrp.services.empty? || vrp.services.none?{ |service|
        service.quantities.size > 1
      }
    end

    def assert_matrices_only_one(vrp)
      vrp.vehicles.collect{ |vehicle|
        vehicle.matrix_id || [vehicle.router_mode.to_sym, vehicle.router_dimension, vehicle.speed_multiplier]
      }.uniq.size == 1
    end

    def assert_one_sticky_at_most(vrp)
      (vrp.services.empty? || vrp.services.none?{ |service|
        service.sticky_vehicles.size > 1
      }) && (vrp.shipments.empty? || vrp.shipments.none?{ |shipment|
        shipment.sticky_vehicles.size > 1
      })
    end

    def assert_one_vehicle_only_or_no_sticky_vehicle(vrp)
      vrp.vehicles.size <= 1 ||
      (vrp.services.empty? || vrp.services.none?{ |service|
        service.sticky_vehicles.size > 0
      }) && (vrp.shipments.empty? || vrp.shipments.none?{ |shipment|
        shipment.sticky_vehicles.size > 0
      })
    end

    def solve_synchronous?(vrp)
      false
    end

    def kill
    end
  end
end
