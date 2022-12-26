# Copyright © Mapotempo, 2015
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

module Api
  module V01
    class Metrics < Grape::Entity
      def self.entity_name
        'Metrics'
      end

      expose(:count_asset, documentation: {type: String, desc: 'Asset given to the request' })
      expose(:count_date, documentation: {type: Date, desc: 'The date of the request' })
      expose(:count_endpoint, documentation: {type: String, desc: 'Endpoint of the request' })
      expose(:count_hits, documentation: {type: Integer, desc: 'Hits of the request' })
      expose(:count_ip, documentation: {type: String, desc: 'IP of the request' })
      expose(:count_key, documentation: {type: String, desc: 'Key used for the request' })
      expose(:count_service, documentation: {type: String, desc: 'Service used for the request' })
      expose(:count_transactions, documentation: {type: Integer, desc: 'Transactions in the service for the request' })
      expose(:count_current_jobs, documentation: {type: Integer, \
                                                  desc: 'Number of current running jobs for the api key' })
    end
  end
end
