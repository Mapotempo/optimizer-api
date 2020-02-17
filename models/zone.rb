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
require './models/base'

module Models
  class Zone < Base
    field :polygon
    field :allocations, default: []

    has_many :vehicles, class_name: 'Models::Vehicle'

    def decode_geom
      @geom = RGeo::GeoJSON.decode(polygon.to_json, json_parser: :json)
    end

    def inside(lat, lng)
      if !lat.nil? && !lng.nil?
        if (@geom || decode_geom).class == RGeo::Geos::CAPIPolygonImpl
          @geom.contains?(RGeo::Cartesian.factory.point(lng, lat))
        end
      end
    end
  end
end
