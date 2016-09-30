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
            <li> <a href="https://github.com/VROOM-Project/vroom">Vroom</a> handle only the basic TSP</li>
            <li> <a href="https://github.com/google/or-tools">ORtools</a> handle multiple vehicles, timewindows, quantities, skills and lateness</li>
            <li> <a href="https://github.com/graphhopper/jsprit">Jsprit</a> handle multiple vehicles, timewindows, quantities, skills and setup duration</li>
          </ul>
        </p>

        <p>Before calling those libraries, a VRP model must be defined, which is decomposed in a few main principles
        </p>
        <p>
          <ul>
            <li>Vehicles : Describe the features of the existing or supposed vehicles</li>
            <li>Services and Shipments : Describe the activities to be performed into the VRP, its special features</li>
            <li>Points : Represent a point in space, it could call a matrix index or be self defined as latitude and longitude coordinates</li>
          </ul>
        </p>
        <p> Some Structures are related to the above ones, in order to describe the API behavior
        </p>
        <p>
          <ul>
            <li>Matrices : Describe the topology of the problem, could of time or distance, depending of the constraints, could be build using the router wrapper</li>
            <li>Units : Describe the dimension used by the good carried</li>
            <li>Capacities : Defined the limit of place allow for a unit into the vehicle</li>
            <li>Quantities : Give the place taken by a package into the vehicle capacity</li>
            <li>Activities : Describe where take place an activity, when it could be performed and how long it last</li>
            <li>Rests : Inform about the in route break of the vehicles</li>
            <li>TimeWindows : Defined a time interval where activities could be performed</li>
          </ul>
        </p>

        <p>The Vrp model carry its own parameters, which could be used depending on the used solver or the requirements</p>
        <p>
          <ul>
            <li>VROOM : It requires any parameters and stop by itself</li>
            <li>ORtools : Could take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or a number of iterations without improvement</li>
            <li>Jsprit : Could take a maximum solve duration, a number of iterations wihtout improvment or a number of iteration without variation in the neighborhood search</li>
          </ul>
        </p>

        <h2>Structure in details</h2>
        <h3>VRP</h3>
          <p> The VRP take on board all the concepts which are involved in the resolution</p>
        <h3>Configuration</h3>
          <p> Describe the limitations of the solve in term of computation</p>
          <h4>Preprocessing</h4>
          <ul>
            <li>cluster_threshold : regroup close points which constitute a cluster into a single geolocated point</li>
            <li>prefer_short_segment : Could allow to pass multiple time in the same street but deliver in a single row</li>
          </ul>
          <h4>Resolution</h4>
          <ul>
            <li>duration : maximum duration of resolution</li>
            <li>iterations : maximum number of iterations (Jsprit only)</li>
            <li>iterations_without_improvment : maximum number of iterations without improvment from the best solution already found</li>
            <li>stable_iterations : maximum number of iterations without variation in the solve bigger than the defined coefficient (Jsprit only)</li>
            <li>stable_coefficient : variation coefficient related to stable_iterations (Jsprit only)</li>
            <li>initial_time_out : minimum solve duration before the solve could stop (x10 in order to find the first solution) (ORtools only)</li>
            <li>time_out_multiplier : the solve could stop itself if the solve duration without finding a new solution is greater than the time currently elapsed multiplicate by this parameter (ORtools only)</li>
          </ul>
          <h4>Problem</h4>
          <ul>
            <li>Vehicles</li>
            <li>Services</li>
            <li>Shipments</li>
            <li>Points</li>
            <li>Locations</li>
            <li>Matrices</li>
            <li>Units</li>
            <li>Capacities</li>
            <li>Quantities</li>
            <li>Activities</li>
            <li>Rests</li>
            <li>TimeWindows</li>
          </ul>

        <h3>Vehicle</h3>
          <ul>
            <li>cost_fixed : Cost applied if the vehicle is used</li>
            <li>cost_distance_multiplier : Cost applied to the distance performed</li>
            <li>cost_time_multiplier : Cost applied to the total amount of time of travel (Jsprit) or to the total time of route (ORtools)</li>
            <li>cost_waiting_time_multiplier : Cost applied to the waiting in the route (Jsprit Only)</li>
            <li>cost_late_multiplier : Cost applied once a point is deliver late (ORtools only)</li>
            <li>cost_setup : Cost applied on the setup duration</li>
            <li>matrix_id : related matrix, if already defined</li>
            <li>router_mode : car, truck, bicycle...etc. See the Router Wrapper API doc</li>
            <li>router_dimension : time or dimension, choose between a matrix based on minimal route duration or on minimal route distance</li>
            <li>speed_multiplier : custom the vehicle speed</li>
            <li>duration : maximum tour duration</li>
            <li>skills : particular abilities that could be handle by the vehicle</li>
            <li>start_point_id : Begin of the tour</li>
            <li>end_point_id : End of the tour</li>
            <li>rests</li>
            <li>capacities</li>
            <li>timewindow</li>
          </ul>

        <h3>Service</h3>
          <ul>
            <li>late_multiplier : override the late_multiplier defined at the vehicle level (ORtools only)</li>
            <li>exclusion_cost : Cost applied to exclude the service in the solution (currently not used)</li>
            <li>sticky_vehicle_ids : Defined to which vehicle the service is assigned</li>
            <li>skills : particular abilities required by a vehicle to perform this service</li>
            <li>type : pickup or delivery</li>
            <li>activity</li>
            <li>quantities</li>
          </ul>

        <h3>Shipment</h3>
          <ul>
            <li>late_multiplier : override the late_multiplier defined at the vehicle level (ORtools only)</li>
            <li>exclusion_cost : Cost applied to exclude the service in the solution (currently not used)</li>
            <li>sticky_vehicle_ids : Defined to which vehicle the shipment is assigned</li>
            <li>skills : particular abilities required by a vehicle to perform this service</li>
            <li>pickup : Activity of collection</li>
            <li>delivery : Activity of drop off</li>
            <li>quantities</li>
          </ul>
        <h3>Point</h3>
          <ul>
            <li>matrix_index : Index in the matrix if it is defined</li>
            <li>location : location of the point if the matrix is not already defiend</li>
          </ul>

        <h3>Location</h3>
          <ul>
            <li>lat : latitude coordinate</li>
            <li>lon : longitude coordinate</li>
          </ul>

        <h3>Matrix</h3>
          <ul>
            <li>matrix_time : Matrix of time, travel duration between each point of the problem</li>
            <li>matrix_distance : Matrix of distance, travel distance between each point of the problem</li>
          </ul>

        <h3>Unit</h3>
          <ul>
            <li>label : name of the unit</li>
          </ul>

        <h3>Capacity</h3>
          <ul>
            <li>unit_id : unit related to this capacity</li>
            <li>limit : maximum capacity that could be take away</li>
            <li>initial : initial amout in the vehicle</li>
            <li>overload_multiplier : allow to exceed the limit against this cost</li>
          </ul>

        <h3>Quantity</h3>
          <ul>
            <li>unit_id : unit related to this quantity</li>
            <li>value : value of the current quantity</li>
          </ul>

        <h3>Activity</h3>
          <ul>
            <li>duration : time to perform this activity</li>
            <li>setup_duration : time to prepare the activity before effective activity</li>
            <li>point_id : point where the activity is performed</li>
            <li>quantities</li>
            <li>timewindows</li>
          </ul>

        <h3>Rest</h3>
          <ul>
            <li>duration : Duration of the vehicle rest</li>
            <li>late_multiplier : (not used)</li>
            <li>exclusion_cost : (not used)</li>
          </ul>

        <h3>TimeWindow</h3>
          <ul>
            <li>start : strict beginning of the timewindow</li>
            <li>end : end of timewindow, strict with Jsprit and could be soft or strict with ORtools</li>
          </ul>

        ').delete("\n"),
      contact: ::OptimizerWrapper::config[:product_contact]
    }
  end
end
