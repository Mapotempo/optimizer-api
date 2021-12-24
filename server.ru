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

require './environment'

use Rack::Cors do
  allow do
    origins '*'
    resource '*',
      headers: :any,
      methods: :any,
      expose: ['Cache-Control', 'Content-Encoding', 'Content-Type'],
      max_age: 1728000,
      credentials: false
  end
end

use Rack::Locale

#\ -p 1791
run Api::Root

# Serve files from the public directory
use Rack::TryStatic,
    root: 'public',
    urls: %w[/],
    try: ['.html', 'index.html', '/index.html']

use ActionDispatch::RemoteIp
