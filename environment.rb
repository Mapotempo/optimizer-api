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
ENV['APP_ENV'] ||= 'development'

require 'rubygems'
require 'bundler/setup'

ORIGINAL_VERBOSITY = $VERBOSE
$VERBOSE = nil if $VERBOSE && ENV['APP_ENV'] == 'test' # suppress the warnings of external libraries
Bundler.require(:default, ENV['APP_ENV'].to_sym)
Resque::Plugins::Status::Hash.inspect # eager load resque-hash
$VERBOSE = ORIGINAL_VERBOSITY

# Gems that needs to be manually required because they are part of an already included gem
require 'active_support/concern'
require 'active_support/core_ext'
require 'active_support/core_ext/string/conversions'
require 'active_support/time'

# gems from standard library
require 'csv'
require 'date'
require 'fileutils'
require 'json'
require 'logger'
require 'open3'
require 'tempfile'
require 'tmpdir'
require 'zlib'

require_rel 'config/environments/' + ENV['APP_ENV']
require_all 'config/initializers'

require './optimizer_wrapper'
require './api/root'
