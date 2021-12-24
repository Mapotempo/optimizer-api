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

# bundle exec resque-web -F -d config/initializers/resque.rb
# needs the following gems to be able to launch on its own
require 'active_support/time'
require 'resque-status'

Resque.inline = ENV['APP_ENV'] == 'test'
Resque.redis = Redis.new(
  host: ENV['REDIS_RESQUE_HOST'] || ENV['REDIS_HOST'] || 'localhost',
  timeout: 300.0
)
Resque::Plugins::Status::Hash.expire_in = 7.days # In seconds, a too small value remove working or queuing jobs
