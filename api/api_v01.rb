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
require 'grape'
require 'grape-swagger'
require 'grape-entity'
require 'grape_logging'

require './optimizer_wrapper'
require './api/v01/api'

module Api
  class ApiV01 < Grape::API
    version '0.1', using: :path

    mount V01::Api

    documentation_class = add_swagger_documentation base_path: (lambda do |request| "#{request.scheme}://#{request.host}" end), hide_documentation_path: true, info: {
      title: ::OptimizerWrapper::config[:product_title],
      description: ('<h2>Overview</h2>

        <p>
        The API has been build in order to call multiple VRP solver in order to cover a large panel of constraints.
        </p>

        <p>The currently integreted solvers are :
          <ul>
            <li> <b><a href="https://github.com/VROOM-Project/vroom">Vroom</a></b> handle only the basic TSP.</li>
            <li> <b><a href="https://github.com/google/or-tools">ORtools</a></b> handle multiple vehicles, timewindows, quantities, skills and lateness.</li>
            <li> <b><a href="https://github.com/graphhopper/jsprit">Jsprit</a></b> handle multiple vehicles, timewindows, quantities, skills and setup duration.</li>
          </ul>
        </p>

        <p>Before calling those libraries, a VRP model must be defined, which is decomposed in a few main principles.
        </p>
        <p>
          <ul>
            <li><b>Vehicles</b> : Describe the features of the existing or supposed vehicles.</li>
            <li><b>Services and Shipments</b> : Describe the activities to be performed into the VRP, its special features.</li>
            <li><b>Points</b> : Represent a point in space, it could call a matrix index or be self defined as latitude and longitude coordinates.</li>
          </ul>
        </p>
        <p> Some Structures are related to the above ones, in order to describe the API behavior.
        </p>
        <p>
          <ul>
            <li><b>Matrices</b> : Describe the topology of the problem, could of time or distance, depending of the constraints, could be build using the router wrapper.</li>
            <li><b>Units</b> : Describe the dimension used by the good carried.</li>
            <li><b>Capacities</b> : Define the limit of place allow for a unit into the vehicle.</li>
            <li><b>Quantities</b> : Give the place taken by a package into the vehicle capacity.</li>
            <li><b>Activities</b> : Describe where take place an activity, when it could be performed and how long it last.</li>
            <li><b>Rests</b> : Inform about the in route break of the vehicles.</li>
            <li><b>TimeWindows</b> : Define a time interval where activities could be performed.</li>
          </ul>
        </p>

        <p>The Vrp model carry its own parameters, which could be used depending on the called solver or the targeted result.</p>
        <p>
          <ul>
            <li><b>VROOM</b> : It requires no parameters and stops by itself.</li>
            <li><b>ORtools</b> : Could take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or a number of iterations without improvement.</li>
            <li><b>Jsprit</b> : Could take a maximum solve duration, a number of iterations wihtout improvment or a number of iteration without variation in the neighborhood search.</li>
          </ul>
        </p>

        ').delete("\n"),
      contact: ::OptimizerWrapper::config[:product_contact]
    }
  end
end
