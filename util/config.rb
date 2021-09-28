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
# frozen_string_literal: true

require './lib/routers/router_wrapper.rb'

module OptimizerWrapper
  REDIS = Resque.redis

  def self.config
    @@c
  end

  def self.dump_vrp_dir
    @@dump_vrp_dir
  end

  def self.dump_vrp_dir=(dir)
    @@dump_vrp_dir = dir
  end

  def self.access(force_load = false)
    load config[:access_by_api_key][:file] || './config/access.rb' if force_load
    @access_by_api_key
  end

  def self.router(api_key)
    @@router_by_api_key ||= {}
    @@router_by_api_key[api_key] ||=
      Routers::RouterWrapper.new(
        ActiveSupport::Cache::NullStore.new,
        ActiveSupport::Cache::NullStore.new,
        api_key
      )
  end
end
