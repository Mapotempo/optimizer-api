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

    content_type :json, 'application/json; charset=UTF-8'
    content_type :xml, 'application/xml'

    mount V01::Api

    documentation_class = add_swagger_documentation(
      hide_documentation_path: true,
      consumes: [
        'application/json; charset=UTF-8',
        'application/xml',
      ],
      produces: [
        'application/json; charset=UTF-8',
        'application/xml',
      ],
      info: {
        title: ::OptimizerWrapper::config[:product_title],
        contact: ::OptimizerWrapper::config[:product_contact],
        description: '
## Overview

The API has been build in order to call multiple VRP solver in order to cover a large panel of constraints.

The currently integreted solvers are:
*   **[Vroom](https://github.com/VROOM-Project/vroom)** handle only the basic TSP.
*   **[ORtools](https://github.com/google/or-tools)** handle multiple vehicles, timewindows, quantities, skills and lateness.
*   **[Jsprit](https://github.com/graphhopper/jsprit)** handle multiple vehicles, timewindows, quantities, skills and setup duration.

Before calling those libraries, a VRP model must be defined, which is decomposed in a few main principles.
*   **Vehicles**: Describe the features of the existing or supposed vehicles. It should be taken in every sense, it could represent a work day of a particular driver/vehicle, or a planning over long period of time. It represent the entity which must travel between points.
*   **Services and Shipments**: Describe the activities to be performed into the VRP, its special features.
*   **Points**: Represent a point in space, it could call a matrix index or be self defined as latitude and longitude coordinates.

Some Structures are related to the above ones, in order to describe the API behavior.
*   **Matrices**: Describe the topology of the problem, it represent travel time or distance, if not defined those are calculated using the router wrapper with the data hold by the points.
*   **Units**: Describe the dimension used for the goods. ie : kgs, litres, pallets...etc
*   **Capacities**: Define the limit allowed for a defined unit into the vehicle.
*   **Quantities**: Inform on the size taken by a package into the vehicle capacities.
*   **Activities**: Describe where an activity take place , when it could be performed and how long it last.
*   **Rests**: Inform about the in route break of the vehicles.
*   **TimeWindows**: Define a time interval where activities could be performed.

The Vrp model carry its own parameters, which could be used depending on the called solver or the targeted result.
*   **VROOM**: It requires no parameters and stops by itself.
*   **ORtools**: Could take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or a number of iterations without improvement.
*   **Jsprit**: Could take a maximum solve duration, a number of iterations wihtout improvment or a number of iteration without variation in the neighborhood search.'
      }
    )
  end
end
