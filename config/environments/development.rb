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
require 'active_support'
require 'tmpdir'

require './wrappers/demo'
require './wrappers/vroom'
require './wrappers/jsprit'
require './wrappers/ortools'

module OptimizerWrapper
  CACHE = ActiveSupport::Cache::FileStore.new(File.join(Dir.tmpdir, 'mapotempo-optimizer-api'), namespace: 'mapotempo-optimizer-api', expires_in: 60*60*24*1)

  DEMO = Wrappers::Demo.new(CACHE)
  VROOM = Wrappers::Vroom.new(CACHE)
  JSPRIT = Wrappers::Jsprit.new(CACHE)
  ORTOOLS = Wrappers::Ortools.new(CACHE)

  @@c = {
    product_title: 'Optimizers API',
    product_contact: 'frederic@mapotempo.com',
    services: {
      demo: DEMO,
      vroom: VROOM,
      jsprit: JSPRIT,
      ortools: ORTOOLS,
    },
    profiles: [{
      api_keys: ['demo'],
      services: {
        vrp: [:vroom, :ortools, :jsprit]
      }
    }],
    router: {
      api_key: 'demo',
      car: 'https://router.mapotempo.com'
    }
  }

  @@c[:api_keys] = Hash[@@c[:profiles].collect{ |profile|
    profile[:api_keys].collect{ |api_key|
      [api_key, profile[:services]]
    }
  }.flatten(1)]
end
