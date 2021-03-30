# Copyright © Mapotempo, 2021
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

class GeometryType
  ALL_TYPES = %i[polylines partitions].freeze

  def self.type_cast(value)
    value = value.split(',') if value.is_a?(String)

    if value.is_a?(FalseClass)
      []
    elsif value.is_a?(TrueClass)
      [:to_fill]
    elsif value.is_a?(Array)
      to_return = []
      value.each{ |geometry_type|
        unless ALL_TYPES.include?(geometry_type.to_sym)
          raise ArgumentError.new("Invalid geometry value : #{geometry_type}")
        end

        to_return << geometry_type.to_sym
      }

      to_return
    else
      raise ArgumentError.new('Invalid type for geometry value')
    end
  end
end
