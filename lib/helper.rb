# Copyright © Mapotempo, 2018
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

module Helper
  def self.string_padding(value, length)
    value.to_s.rjust(length, '0')
  end

  def self.deep_copy(original, override: {}, shallow_copy: [])
    # TODO: after testing move the logic to base.rb as a clone function (initialize_copy)

    # To override keys (and sub-keys) with values instead of using the originals
    # (i.e., original[:key1], original[:other][:key2] etc) do
    #                 override: { key1: value1, key2: value2 }
    # To prevent deep copy and use the original objects and sub-objects
    # (i.e., original[:key1], original[other][:key2]) do
    #                 shallow_copy: [:key1, :key2 ]

    # Assigning nil to a key in the override hash, skips the key and key_id of the objects

    # WARNING: custom fields will be missing from the objects! because if a key/method doesn't exist
    # in the Models::Class definition, it cannot be duplicated

    case original
    when Array # has_many
      original.collect{ |val| deep_copy(val, override: override, shallow_copy: shallow_copy) }
    when Models::Base # belongs_to
      raise 'Keys cannot be both overridden and shallow copied' if (override.keys & shallow_copy).any?

      # if an option doesn't exist for the current object level, pass it to lower levels
      unused_override = override.select{ |key, _value|
        [
          key, "#{key}_id", "#{key[0..-2]}_ids", "#{key[0..-4]}y_ids", key[0..-4], "#{key[0..-6]}ies", "#{key[0..-5]}s"
        ].none?{ |k| original.class.method_defined?(k.to_sym) }
      }

      unused_shallow_copy = shallow_copy.select{ |key|
        [
          key, "#{key}_id", "#{key[0..-2]}_ids", "#{key[0..-4]}y_ids", key[0..-4], "#{key[0..-6]}ies", "#{key[0..-5]}s"
        ].none?{ |k| original.class.method_defined?(k.to_sym) }
      }

      # if a non-"id" version of the key exists, then prefer the hash of the non-id method (i.e., skip x_id(s))
      # so that the objects are generated from scratch instead of re-used.
      # Unless the key or key_id is marked as shallow_copy (then use the object) or the key or key_id is given in override.
      keys = original.attributes.keys.flat_map{ |key|
        [
          key[0..-4].to_sym, "#{key[0..-6]}ies".to_sym, "#{key[0..-5]}s".to_sym, key
        ].find{ |k| original.class.method_defined?(k) }
      }.uniq - [:id] # cannot duplicate the object with the same id

      # To reuse the same sub-members, the key needs to be given in the shallow_copy
      # (which forces the duplication to use the original key object)
      keys.map!{ |key|
        if override.key?(key)
          next unless override[key].nil?

          [
            "#{key}_id".to_sym, "#{key[0..-2]}_ids".to_sym, "#{key[0..-4]}y_ids".to_sym
          ].find{ |k| original.class.method_defined?(k) && (!override.key?(k) || override[k]) }
        elsif ["#{key}_id", "#{key[0..-2]}_ids", "#{key[0..-4]}y_ids"].any?{ |k| override[k.to_sym] }
          next
        else
          key
        end
      }.compact!

      # if a key is supplied in the override manually as nil, this means removing the key
      # pass unused_override and unused_shallow_copy to the lower levels only
      keys |= override.keys.select{ |k| override[k] && original.class.method_defined?(k) }
      keys |= shallow_copy.select{ |k| original.class.method_defined?(k) }

      # prefer the option if supplied
      original.class.create(keys.each_with_object({}) { |key, data|
        data[key] = override[key] ||
                    (shallow_copy.include?(key) ? original.send(key) : deep_copy(original.send(key),
                                                                                 override: unused_override,
                                                                                 shallow_copy: unused_shallow_copy))
      })
    else
      original.dup
    end
  end

  def self.merge_results(results, merge_unassigned = true)
    results.flatten!
    results.compact!
    {
      solvers: results.flat_map{ |r| r[:solvers] }.compact,
      cost: results.map{ |r| r[:cost] }.compact.reduce(&:+),
      cost_details: results.map{ |r| r[:cost_details] }.compact.sum,
      iterations: results.size != 1 ? nil : results[0][:iterations],
      heuristic_synthesis: results.size != 1 ? nil : results[0][:heuristic_synthesis],
      routes: results.flat_map{ |r| r[:routes] }.compact.uniq,
      unassigned: merge_unassigned ? results.flat_map{ |r| r[:unassigned] }.compact.uniq : results.map{ |r| r[:unassigned] }.compact.last,
      elapsed: results.map{ |r| r[:elapsed] || 0 }.reduce(&:+),
      total_time: results.map{ |r| r[:total_time] }.compact.reduce(&:+),
      total_travel_time: results.map{ |r| r[:total_travel_time] }.compact.reduce(&:+),
      total_value: results.map{ |r| r[:total_travel_value] }.compact.reduce(&:+),
      total_distance: results.map{ |r| r[:total_distance] }.compact.reduce(&:+),
      use_deprecated_csv_headers: results.any?{ |r| r[:use_deprecated_csv_headers] },
    }
  end

  def self.replace_routes_in_result(result, new_result)
    # Updates the routes of result with the ones in new_result and corrects the total stats
    # TODO: Correct total cost (needs cost per route!!!)

    # Correct unassigned services
    result[:unassigned].delete_if{ |activity|
      # Remove from unassigned if they appear in new unasigned or if they are served in new routes
      new_result[:unassigned].any?{ |a| a[:service_id] == activity[:service_id] } ||
        new_result[:routes].any?{ |r| r[:activities].any?{ |a| a[:service_id] == activity[:service_id] } }
    }
    result[:unassigned] += new_result[:unassigned]

    # Correct total stats and delete old routes
    new_result[:routes].each{ |new_route|
      old_route = result[:routes].find{ |r| r[:vehicle_id] == new_route[:vehicle_id] } || {} # this vehicle might not be used in the old results

      [:total_time, :total_travel_time, :total_travel_value, :total_distance].each{ |stat|
        next if new_route[stat].nil? && old_route[stat].nil? # if both nil no correction necessary

        result[stat] = result[stat].to_f + new_route[stat].to_f - old_route[stat].to_f # = to_f incase this stat was nil
      }

      result[:routes].delete(old_route)
    }

    # Add the new routes
    result[:routes] += new_result[:routes]

    result
  end

  def self.services_duration(services)
    services.group_by{ |s| s.activity.point_id }.map{ |_point_id, ss|
      sm = ss.max_by(&:visits_number)
      sm.activity.setup_duration * sm.visits_number + ss.map{ |s| s.activity.duration * s.visits_number }.sum
    }.sum
  end

  def self.visits(services)
    services.sum(&:visits_number)
  end
end

class Numeric
  # rounds the value to the closest multiple of `num`
  # https://en.wikipedia.org/wiki/Rounding#Rounding_to_other_values
  def round_to_multiple_of(num)
    (self / num).round(6).round(0) * num # .round(6).round(0) to prevent floating point errors
  end

  # rounds the number to the closest step in between [val.round(ndigits), val.round(ndigits) + 1/10**ndigits].
  # Useful when rounding is performed to reduce the number of uniq elements.
  #
  # ndigits: the number of decimal places (when nsteps = 0)
  #
  # nsteps: the number of steps between val.round(ndigits) and val.round(ndigits) + 1/10**ndigits
  #
  # For example,
  # array = [0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.17, 0.18, 0.19, 0.2]
  #
  # With round():
  # array.collect{ |val| val.round(1) }.uniq      :=>      [0.1, 0.2]                                                       # too little
  # array.collect{ |val| val.round(2) }.uniq      :=>      [0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.17, 0.18, 0.19, 0.2] # too much
  #
  # With nsteps the number of uniq elements between two decimals can be controlled:
  # array.collect{ |val| val.round_with_steps(1, 0) }.uniq      :=>     [0.1, 0.2]                                                         # same with round(1)
  # array.collect{ |val| val.round_with_steps(1, 1) }.uniq      :=>     [0.1, 0.15, 0.2]                                                   # one extra step in between
  # array.collect{ |val| val.round_with_steps(1, 2) }.uniq      :=>     [0.1, 0.13, 0.17, 0.2]                                             # two extra step in between
  # ...
  # array.collect{ |val| val.round_with_steps(1, 8) }.uniq      :=>     [0.1, 0.11, 0.12, 0.13, 0.14, 0.16, 0.17, 0.18, 0.19, 0.2]         # eigth extra step in between
  # array.collect{ |val| val.round_with_steps(1, 9) }.uniq      :=>     [0.1, 0.11, 0.12, 0.13, 0.14, 0.15, 0.16, 0.17, 0.18, 0.19, 0.2]   # same with round(2)
  #
  # Theoretically, val.round_with_steps(ndigits, nsteps) is
  # equivalent to  val.round_to_multiple_of(1.0 / (nsteps + 1) / 10**ndigits )
  def round_with_steps(ndigits, nsteps = 0)
    self.round_to_multiple_of(1.fdiv((nsteps + 1) * 10**ndigits)).round(ndigits + 1) # same as ((self * (nsteps + 1.0)).round(ndigits) / (nsteps + 1.0)).round(ndigits + 1)
  end
end
