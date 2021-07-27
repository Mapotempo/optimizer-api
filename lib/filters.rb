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
  def self.filter(vrp)
    merge_timewindows(vrp)

    filter_skills(vrp)

    # calculate_unit_precision # TODO: treat only input vrp, not all models in memory from other vrps
    nil
  end

  # Calculates a coefficient for each unit so that when multiplied with
  # this coefficient; each non-integer capacity and quantity (service
  # and shipment) becomes integer and maximum capacities of different
  # units becomes balanced (i.e., in the same order of magnitude).
  #
  # Needs to be called while preparing the input data of the solvers
  # which expects integer values for capacitiy and quantity values
  # (e.g., ortools).
  def self.calculate_unit_precision
    return if Models::Unit.all.empty? ||
              (Models::Capacity.all.empty? && Models::Quantity.all.empty?)

    # Find all quantity and capacity values by unit type to calculate the coefficients
    all_values_by_units = {}

    # First check the capacities to initialize the hash
    Models::Capacity.all.each{ |capacity|
      if all_values_by_units[capacity.unit].nil?
        all_values_by_units[capacity.unit] = [] # create the array of the unit if first
      end
      all_values_by_units[capacity.unit].push(capacity.limit) unless capacity.limit.nil? || capacity.limit.zero?
    }

    # Then services and shipments
    Models::Quantity.all.each{ |quantity|
      if all_values_by_units[quantity.unit].nil? # This unit has no capacity in none of the service_vrps, but we still might turn it into integer
        all_values_by_units[quantity.unit] = []
      end
      all_values_by_units[quantity.unit].push(quantity.value) unless quantity.value.nil? || quantity.value.zero?
      all_values_by_units[quantity.unit].push(quantity.setup_value) if quantity.unit.counting && !quantity.setup_value.zero?
    }

    all_values_by_units.reject!{ |_unit, value_array| value_array.empty? }

    float_unit_has_overload_multiplier = false # there is a unit with a float value/limit and a non-zero overload cost
    # For each unit, find the coefficient to convert all floating point numbers
    # of this unit (i.e., capacities, quantities of unit_id "x") to integer
    all_values_by_units.each_pair{ |unit, value_array|
      unit.precision_coef = smallest_coef_to_make_array_all_integer(value_array).to_r
      # FIXME: We need to decide what to do if there is an overload_multiplier cost in one unit and it
      # has a noninteger capacity/quantitiy (i.e., we need to multiply the values of a unit with a precision_coef)
      # Currently precision_coef is not in use so this souldn't cause a problem.
      float_unit_has_overload_multiplier = true if !float_unit_has_overload_multiplier &&
                                                   (unit.precision_coef != Models::Unit.default_attributes[:precision_coef]) &&
                                                   (Models::Capacity.where(unit: unit).all?{ |cap| cap.overload_multiplier.nil? || cap.overload_multiplier.zero? })
    }

    if float_unit_has_overload_multiplier ||
       (Models::Capacity.all.size != Models::Capacity.where(overload_multiplier: 0).size)
      # FIXME: Even if there is no unit with_overload_cost and with_non_integral_values
      # we might be still in trouble if there is a non-zero overload cost in some of the
      # units since normalization and balancing will most certainly modify the precision_coef
    end

    # Normalise the precision_coef (within the unit) using greatest-common-divisor
    all_values_by_units.each_pair{ |unit, value_array|
      integer_value_array = value_array.map{ |value| (value * unit.precision_coef).round }
      gcd_of_integer_value_array = gcd_of_array(integer_value_array)
      unit.precision_coef = (unit.precision_coef / gcd_of_integer_value_array).to_r
    }

    # Skip the following units before balancing:
    # counting units (the precision_coef turns them into integer, they don't need to be in the balancing)
    # the units which only has services/shipments without capacity or which only has capacity without any services/shipments
    all_values_by_units.delete_if{ |unit, value_array|
      unit.counting ||
        (value_array.size == Models::Capacity.where(unit: unit).size) ||
        (value_array.size == Models::Quantity.where(unit: unit).size)
    }

    return if all_values_by_units.empty?

    # Find the overall max capacity limit and max capacity by unit for balancing
    max_capacity_by_unit_after_precision_coef = {}
    all_values_by_units.each_pair{ |unit, value_array|
      integer_value_array = value_array.map{ |value| (value * unit.precision_coef).round }
      max_capacity_by_unit_after_precision_coef[unit] = integer_value_array.max
    }
    max_overall_capacity_after_prec_coef = max_capacity_by_unit_after_precision_coef.max_by(&:last).last.to_f

    # Lastly balance the coefficient between different units
    # so that max capacity of each unit is in the same order of magnitude
    max_capacity_by_unit_after_precision_coef.each_pair{ |unit, max_unit_capacity|
      next if max_overall_capacity_after_prec_coef == max_unit_capacity

      unit.precision_coef *= (max_overall_capacity_after_prec_coef.to_f / max_unit_capacity).round
    }

    nil
  end

  # Returns the smallest coefficient which turns an array of floatig point numbers into integer
  def self.smallest_coef_to_make_array_all_integer(values)
    coefficient = 1
    values.each{ |value|
      coef = smallest_coef_to_make_value_integer(value)
      # Lowest common multiple of all coefs
      # That is if array has 0.1 and 0.25 as values
      # they, respectively, need be multiplies by 10 and 4 to become integer
      # and a coef of 20 (=lcm(10,4)) turns both numbers to integer
      coefficient = coefficient.lcm(coef)
    }
    coefficient
  end

  # Returns the smallest coefficient which turns a floatig point number into integer
  def self.smallest_coef_to_make_value_integer(value)
    # Find number of decimal places in the value
    decimal_place_count = decimal_places(value)

    # Find denominator in fraction form. For example,
    # for 30.25, denominator is 100
    denominator = 10**decimal_place_count

    # Result is denominator divided by GCD-of-numerator-and-denominator.
    # For example, for 30.25, result is 100 / GCD(3025,100) = 100/25 = 4
    # Round should be okay because we calculate the decimal places exactly
    denominator / denominator.gcd((value * denominator).round)
  end

  # Returns the number of decimal places in a value
  def self.decimal_places(value)
    decimal_count = 0
    original_value = value
    until (value - value.round).abs < 1e-10 # Check if integer (it needs to be done like this due to floating point representation)
        decimal_count += 1
        value = original_value * 10**decimal_count # value *= 10 propogates the floating point error
    end
    decimal_count
  end

  # Returns the GCD of an array of numbers
  def self.gcd_of_array(values)
    result = values[0]
    values.each{ |value| result = result.gcd(value) }
    result
  end

  def self.merge_timewindows(vrp)
    vrp.services.each{ |service|
      next if !service.activity || service.activity.timewindows.size <= 1

      unified_timewindows = {}
      inter = {}
      new_timewindows = []

      service.activity.timewindows.each{ |timewindow|
        unified_timewindows[timewindow.id] = {
          start: (timewindow.day_index || 0) * 86400 + timewindow.start,
          end: timewindow.end && ((timewindow.day_index || 0) * 86400 + timewindow.end) || (0 + (1 + (timewindow.day_index || 6)) * 86400)
        }
        inter[timewindow.id] = []
      }

      unified_timewindows.each{ |key, value|
        unified_timewindows.each{ |s_key, s_value|
          next if key == s_key || s_value.include?(key) || value.include?(s_key)

          next unless value[:start] >= s_value[:start] && value[:start] <= s_value[:end] || value[:end] >= s_value[:start] && value[:end] <= s_value[:end]

          inter[key].each{ |k_value| inter[k_value] << s_key }
          inter[s_key].each{ |k_value| inter[k_value] << key }
          inter[key] << s_key
          inter[s_key] << key
        }
      }
      to_merge_ids = []

      next unless inter.any?{ |_key, value| !value.empty? }

      inter.each{ |key, value|
        to_merge_ids = ([key] + value).uniq
        to_merge_ids.each{ |id| inter.delete(id) }
        inter.delete(to_merge_ids)
        to_merge_tws = service.activity.timewindows.select{ |timewindow| to_merge_ids.include?(timewindow.id) }
        day_indices = to_merge_tws.collect(&:day_index)
        starts = to_merge_tws.collect(&:start)
        ends = to_merge_tws.collect(&:end)
        earliest_day_index = day_indices.include?(nil) ? nil : day_indices.min
        # latest_day_index = day_indices.include?(nil) ? nil : day_indices.max
        earliest_start = starts.include?(nil) ? nil : starts.min
        latest_end = ends.include?(nil) ? nil : ends.max
        new_timewindows << Models::Timewindow.new(start: earliest_start, end: latest_end, day_index: earliest_day_index)
      }
      service.activity.timewindows = new_timewindows
    }

    nil
  end

  def self.filter_skills(vrp)
    # Remove duplicate skills and sort
    vrp.services.each{ |s|
      s.skills = s.skills&.uniq&.sort
    }

    vrp.vehicles.each{ |v|
      v.skills = v.skills.map{ |s| s&.uniq&.sort }.compact.uniq
    }

    # Remove infeasible skills
    filter_infeasible_service_skills(vrp)
    filter_unnecessary_vehicle_skills(vrp)

    nil
  end

  def self.filter_infeasible_service_skills(vrp)
    # Eliminate the skills which do not appear in any vehicle
    individual_vehicle_skills = vrp.vehicles.map(&:skills).flatten(2).compact.uniq

    vrp.services.each{ |s|
      next if s.skills.empty?

      s.skills -= s.skills - individual_vehicle_skills
    }

    nil
  end

  def self.filter_unnecessary_vehicle_skills(vrp)
    # Eliminate skills of vehicles if there is no service needing it
    needed_service_skills = vrp.services.flat_map(&:skills).compact.uniq

    vrp.vehicles.each{ |v|
      next if v.skills.empty?

      v.skills.each.with_index{ |veh_skill, s_ind|
        next if veh_skill.empty?

        v.skills[s_ind] -= veh_skill - needed_service_skills
      }
    }

    nil
  end
end
