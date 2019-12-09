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

  def self.fixnum_max
    (2**(0.size * 8 - 2) - 1)
  end

  def self.fixnum_min
    -(2**(0.size * 8 - 2))
  end

  def self.flying_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    if (loc_a[0] - loc_b[0]).abs < 30 && [loc_a[0].abs, loc_b[0].abs].max + (loc_a[1] - loc_b[1]).abs < 100
      # These limits ensures that relative error cannot be much greather than 2%
      # For a distance like Bordeaux - Berlin, relative error between
      # euclidean_distance and flying_distance is 0.1%.
      # That is no need for trigonometric calculation.
      return euclidean_distance(loc_a, loc_b)
    end

    r = 6378137 # Earth's radius in meters
    deg2rad_lat_a = loc_a[0] * Math::PI / 180
    deg2rad_lat_b = loc_b[0] * Math::PI / 180
    deg2rad_lon_a = loc_a[1] * Math::PI / 180
    deg2rad_lon_b = loc_b[1] * Math::PI / 180
    lat_distance = deg2rad_lat_b - deg2rad_lat_a
    lon_distance = deg2rad_lon_b - deg2rad_lon_a

    intermediate = Math.sin(lat_distance / 2) * Math.sin(lat_distance / 2) + Math.cos(deg2rad_lat_a) * Math.cos(deg2rad_lat_b) *
                    Math.sin(lon_distance / 2) * Math.sin(lon_distance / 2)

    return r * 2 * Math.atan2(Math.sqrt(intermediate), Math.sqrt(1 - intermediate))
  end

  def self.euclidean_distance(loc_a, loc_b)
    return 0.0 unless loc_a[0] && loc_b[0]

    delta_lat = loc_a[0] - loc_b[0]
    delta_lon = (loc_a[1] - loc_b[1]) * Math.cos((loc_a[0] + loc_b[0]) * Math::PI / 360.0) # Correct the length of a lon difference with cosine of avereage latitude

    return 111321 * Math.sqrt(delta_lat**2 + delta_lon**2) # 111321 is the length of a degree (of lon and lat) in meters
  end

  def self.merge_results(results, merge_unassigned = true)
    results.flatten!
    {
      solvers: results.flat_map{ |r| r && r[:solvers] }.compact,
      cost: results.map{ |r| r && r[:cost] }.compact.reduce(&:+),
      routes: results.flat_map{ |r| r && r[:routes] }.compact.uniq,
      unassigned: merge_unassigned ? results.flat_map{ |r| r && r[:unassigned] }.compact.uniq : results.map{ |r| r && r[:unassigned] }.compact.last,
      elapsed: results.map{ |r| r && r[:elapsed] || 0 }.reduce(&:+),
      total_time: results.map{ |r| r && r[:total_travel_time] }.compact.reduce(&:+),
      total_value: results.map{ |r| r && r[:total_travel_value] }.compact.reduce(&:+),
      total_distance: results.map{ |r| r && r[:total_distance] }.compact.reduce(&:+)
    }
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

# Some functions for convenience
# In the same vein as active_support Enumerable.sum implementation
module Enumerable
  # Provide the average on an array
  #  [5, 15, 7].mean # => 9.0
  def mean
    return nil if empty?
    inject(0) { |sum, x| sum + x } / size.to_f
  end

  # If the array has an odd number, then simply pick the one in the middle
  # If the array size is even, then we return the mean of the two middle.
  #  [5, 15, 7].median # => 7
  def median(already_sorted = false)
    return nil if empty?
    sort! unless already_sorted
    m_pos = size / 2 # no to_f!
    size.odd? ? self[m_pos] : self[m_pos - 1..m_pos].mean
  end

  # The mode is the single most popular item in the array.
  #  [5, 15, 10, 15].mode # => 15
  def mode
    modes(false)[0]
  end

  # In case there are multiple elements with the highest occurence
  #  [5, 15, 10, 10, 15].modes # => [10, 15]
  #  [5, 15, 10, 15].modes     # => [15] (Note that modes() returns an array)
  def modes(find_all = true)
    return nil if empty?
    histogram = each_with_object(Hash.new(0)) { |n, h| h[n] += 1 }
    modes = nil
    histogram.each_pair do |item, times|
      modes << item if find_all && !modes.nil? && times == modes[0]
      modes = [times, item] if (modes && times > modes[0]) || (modes.nil? && times > 1)
    end
    !modes.nil? ? modes[1...modes.size] : nil
  end
end