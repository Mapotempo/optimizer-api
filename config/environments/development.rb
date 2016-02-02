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

  @@c = {
    product_title: 'Optimizers API',
    product_contact: 'frederic@mapotempo.com',
    services: {
      vrp: [Wrappers::Demo.new(CACHE), Wrappers::Vroom.new(CACHE), Wrappers::Jsprit.new(CACHE), Wrappers::Ortools.new(CACHE)],
    },
    api_keys: ['demo']
  }
end
