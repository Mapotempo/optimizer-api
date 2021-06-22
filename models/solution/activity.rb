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
require './models/base'
require './models/solution/timing'

module Models
  class RouteActivity < Base
    # field :point_id
    field :id
    field :type
    field :alternative
    field :reason, default: nil
    # TODO: The following fields should be merged into id in v2
    field :service_id
    field :pickup_shipment_id
    field :delivery_shipment_id
    field :rest_id

    has_many :loads, class_name: 'Models::Load'
    belongs_to :detail, class_name: 'Models::Activity'
    belongs_to :timing, class_name: 'Models::Timing', default: Models::Timing.new({})
  end
end
