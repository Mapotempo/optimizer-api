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
  def self.type_cast(value, mandatory = true, allow_zero = true)
    return_value = if !value.nil?
                    if /([0-9]+):([0-9]+):([0-9]+)/ =~ value.to_s
                      3600 * Regexp.last_match(1).to_i + 60 * Regexp.last_match(2).to_i + Regexp.last_match(3).to_i
                    elsif /([0-9]+):([0-9]+)/ =~ value.to_s
                      3600 * Regexp.last_match(1).to_i + 60 * Regexp.last_match(2).to_i
                    elsif /\A[0-9]+\.{0,1}[0-9]*\z/ =~ value.to_s
                      value.to_i
                    elsif value.is_a?(Integer) || value.is_a?(Float)
                      value.to_i
                    else
                      log 'error', level: :error
                      raise ArgumentError, 'Invalid Time value'
                    end
                  elsif mandatory
                    0
                  end

    if return_value&.negative? || (!allow_zero && return_value&.zero?)
      log 'error', level: :error
      raise ArgumentError, 'Invalid Time value'
    end

    return_value
  end
end
