# Copyright © Mapotempo, 2017
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

class ScheduleType
  def type_cast(value, mandatory = true)
    if !value.nil?
      if /[0-9]+:[0-9]+:[0-9]+/.match(value.to_s)
        pattern = /([0-9]+):([0-9]+):([0-9]+)/.match(value)
        3600 * pattern[1].to_i + 60 * pattern[2].to_i + pattern[3].to_i
      elsif /[0-9]+:[0-9]+/.match(value.to_s)
        pattern = /([0-9]+):([0-9]+)/.match(value)
        3600 * pattern[1].to_i + 60 * pattern[2].to_i
      elsif /\A[0-9]+\.{0,1}[0-9]*\z/.match(value.to_s)
        value.to_i
      elsif (value.kind_of?(Integer) || value.kind_of?(Float))
        value.to_i
      else
        puts 'error'
        raise ArgumentError.new("Invalid Time value")
      end
    elsif mandatory
      0
    end
  end
end
