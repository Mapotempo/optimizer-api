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

  def self.flying_distance(a, b)
    if a[0] && b[0]
      r = 6378.137
      deg2rad_lat_a = a[0] * Math::PI / 180
      deg2rad_lat_b = b[0] * Math::PI / 180
      deg2rad_lon_a = a[1] * Math::PI / 180
      deg2rad_lon_b = b[1] * Math::PI / 180
      lat_distance = deg2rad_lat_b - deg2rad_lat_a
      lon_distance = deg2rad_lon_b - deg2rad_lon_a

      intermediate = Math.sin(lat_distance / 2) * Math.sin(lat_distance / 2) + Math.cos(deg2rad_lat_a) * Math.cos(deg2rad_lat_b) *
                     Math.sin(lon_distance / 2) * Math.sin(lon_distance / 2)

      fly_distance = 1000 * r * 2 * Math.atan2(Math.sqrt(intermediate), Math.sqrt(1 - intermediate))
    else
      0.0
    end
  end

end
