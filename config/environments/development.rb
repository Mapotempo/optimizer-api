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
require './wrappers/ortools'

require './lib/cache_manager'

module OptimizerWrapper
  CACHE = CacheManager.new(ActiveSupport::Cache::FileStore.new(File.join(Dir.tmpdir, 'mapotempo-optimizer-api'), namespace: 'mapotempo-optimizer-api', expires_in: 60*60*24*1))

  DEMO = Wrappers::Demo.new(CACHE)
  VROOM = Wrappers::Vroom.new(CACHE)
  # if dependencies don't exist (libprotobuf10 on debian) provide or-tools dependencies location
  ORTOOLS = Wrappers::Ortools.new(CACHE, exec_ortools: 'LD_LIBRARY_PATH=../or-tools/dependencies/install/lib/:../or-tools/lib/ ../optimizer-ortools/tsp_simple')

  @@dump_vrp_cache = CacheManager.new(ActiveSupport::Cache::FileStore.new(File.join(Dir.tmpdir, 'mapotempo-optimizer-api'), namespace: "vrp", expires_in: 60*60*24*30))

  @@c = {
    product_title: 'Optimizers API',
    product_contact_email: 'tech@mapotempo.com',
    product_contact_url: 'https://github.com/Mapotempo/optimizer-api',
    services: {
      demo: DEMO,
      vroom: VROOM,
      ortools: ORTOOLS,
    },
    profiles: [{
      api_keys: ['demo'],
      queue: 'DEFAULT',
      services: {
        vrp: [:vroom, :ortools]
      }
    }],
    router: {
      api_key: 'demo',
      url: 'https://router.mapotempo.com'
    }
  }

  @@c[:api_keys] = Hash[@@c[:profiles].collect{ |profile|
    profile[:api_keys].collect{ |api_key|
      [api_key, {
        queue: profile[:queue],
        services: profile[:services]
      }]
    }
  }.flatten(1)]

  DUMP_VRP = true
end
