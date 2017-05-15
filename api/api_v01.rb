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
        contact_email: ::OptimizerWrapper::config[:product_contact_email],
        contact_url: ::OptimizerWrapper::config[:product_contact_url],
        license: 'GNU Affero General Public License 3',
        license_url: 'https://raw.githubusercontent.com/Mapotempo/optimizer-api/master/LICENSE',
        description: '
## Table of Contents
* [Overview](#overview)
* [Input Model](#input-model)
  * [General Model](#general-model)
  * [Points](#points)
  * [TimeWindows](#timewindows)
  * [Vehicles](#vehicles)
  * [Activities](#activities)
  * [Services and Shipments](#services-and-shipments)
  * [Matrices](#matrices)
  * [Units](#units)
  * [Capacities](#capacities)
  * [Quantities](#quantities)
  * [Rests](#rests)
  * [Configuration](#configuration)
* [Solve](#solve)
  * [Lateness²](#lateness)
  * [Multiple Vehicles](#multiple-vehicles)
  * [Multiple Depots](#multiple-depots)
  * [Multiple Timewindows¹](#multiple-timewindows)
  * [Multiple Matrices²](#multiple-matrices)
  * [Pickup and Delivery³](#pickup-and-delivery)
  * [Priority²](#priority)
  * [Quantities Overload²](#quantities-overload)
  * [Setup Duration](#setup-duration)
  * [Skills](#skills)
  * [Alternative Skills³](#alternative-skills)

-----------------
¹ Limit of 2 timewindows with ORtools  
² Currently not available with Jsprit  
³ Currently not available with ORtools  

-----------------

Overview (#overview)
--

The API has been built to wrap a large panel of  Traveling Salesman Problem(TSP) and Vehicle Routing Problem(VRP) constraints in order to call the most fitted solvers.

The currently integreted solvers are:
*   **[Vroom](https://github.com/VROOM-Project/vroom)** only handle the basic Traveling Salesman Problem.
*   **[ORtools](https://github.com/google/or-tools)** handle multiple vehicles, timewindows, quantities, skills and lateness.
*   **[Jsprit](https://github.com/graphhopper/jsprit)** handle multiple vehicles, timewindows, quantities, skills and setup duration.

Input Model (#input-model)
--

Before calling the solvers, a VRP model must be defined, which represent the problem to solve with all its parameters and constraints.

### **General Model**(#general-model)
```json
vrp:{
  points: [..],
  vehicles: [..],
  units: [..],
  services: [..],
  shipments: [..],
  matrices: [..],
  rests: [..],
  configuration: [..]
}
```
Those high level entities are completed by few others as **timewindows** and **activities** which are locally defined.
To define the model, the first step will be to every **points** which will be used in the description of the problem. This will include the depots and the customers locations.
Furthermore at least one **vehicle** is mandatory and define at least one **service** or **shipment** will be essential to launch the solve.
The others entities are optional but will be unavoidable depending on the problem to describe.

### **Points**(#points)
Represent a point in space, it could call a matrix index or be self defined as latitude and longitude coordinates.  
With coordinates
```json
  points: [{
      id: "vehicle-start",
      location: {
        lat: start_lat,
        lon: start_lon
      }
    }, {
      id: "vehicle-end",
      location: {
        lat: start_lat,
        lon: start_lon
      }
    }, {
      id: "visit-point-1",
      location: {
        lat: visit_lat,
        lon: visit_lon
      }, {
      id: "visit-point-2",
      location: {
        lat: visit_lat,
        lon: visit_lon
      }
    }]
```
If the problem matrices are defined the matrix indices can be used to link each point to its distance to other points instead of coordinates.
This could be usefull if the routing data are provided from an external source.
```json
  points: [{
      id: "vehicle-start",
      matrix_index: 0
    }, {
      id: "vehicle-end",
      matrix_index: 1
    }, {
      id: "visit-point-1",
      matrix_index: 2
    }, {
      id: "visit-point-2",
      matrix_index: 3
    }]
```
### **TimeWindows**(#timewindows)
Define a time interval when a resource is available or when an activity can be performed.  
Vehicles only have single timewindow
```json
  timewindow: {
    start: 0,
    end: 7200
  }
```
Activities can have multiple timewindows
```json
  timewindows: [{
    start: 600,
    end: 900
  },{
    start: 1200,
    end: 1500
  }],
```
### **Vehicles**(#vehicles)
Describe the features of the existing or supposed vehicles. It should be taken in every sense, it could represent a work day of a particular driver/vehicle, or a planning over long period of time. It represent the entity which must travel between points.
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
  }]
```
Costs can also be added in order to fit more precisely the real constraints
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 500.0,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 1.0,
  }]
```
The router dimension can be set as distance, this describe that the route between will be the shortest, instead of the fastest.
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "distance",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 500.0,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 0.0,
  }]
```

### **Activities**(#activities)
Describe where an activity take place , when it could be performed and how long it last.
```json
  activity: {
    point_id: "visit-point",
    timewindows: [{
      start: 3600,
      end: 4800
    }],
    duration: 2100.0
  }
```
### **Services and Shipments**(#services-and-shipments)
Describe more precisely the activities to be performed into the VRP.
Services are single activities which are self-sufficient.
```json
  services: [{
    id: "visit",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    }
  }
```
Shipments are a couple of activities, the pickup is where the vehicle must take-off a package and the delivery the place the vehicle must deliver this particular package.
pickup and delivery are build following the activity model
```json
  shipments: [{
    id: "shipment",
    pickup: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }]
    },
    delivery: {
      point_id: "visit-point-2",
      duration: 2100.0
    }
  }]
```
### **Matrices**(#matrices)
Describe the topology of the problem, it represent travel time or distance between every points,
Matrices are not mandatory, if those are not defined the router wrapper will use the points data to build it.
```json
  matrices: [{
    id: "matrix-1",
    time: [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0],
    ]
  }]
```
With this matrix defined, the vehicle definition is now the following :
```json
  vehicles: [{
    id: "vehicle_id",
    matrix_id: "matrix-1",
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    timewindow: {
      start: 0,
      end: 7200
    },
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```
Note that every vehicle could be linked to a unique matrix in order to model multiple transport mode

In the case the distance cost is greater than 0, it will be mandatory to transmit the related matrix
```json
  matrices: [{
    id: "matrix-1",
    time: [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0],
    ],
    distance: [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0],
    ]
  }]
```
Whenever there is no time constraint and the objective is only set on distance, the time matrix is not mandatory
### **Units**(#units)
Describe the dimension used for the goods. ie : kgs, litres, pallets...etc
```json
  units: [{
    id: "unit-Kg",
    label: "Kilogram"
  }]
```
### **Capacities**(#capacities)
Define the limit allowed for a defined unit into the vehicle.
```json
  capacities: [{
    unit_id: "unit-Kg",
    limit: 10,
    overload_multiplier: 0,
  }]
```
Which is defined as follows
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    capacities: [{
      unit_id: "Kg",
      limit: 10,
      overload_multiplier: 0,
    }],
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```
### **Quantities**(#quantities)
Inform on the size taken by an activity package once loaded into a vehicle.
```json
  quantities: [{
    unit_id: "Kg",
    value: 8,
  }]
```
```json
  services: [{
    id: "visit",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    quantities: [{
      unit_id: "Kg",
      value: 8,
    }]
  }
```
### **Rests**(#rests)
Inform about the drivers obligations to have some rest within a route
```json
  rests: [{
    id: "Break-1",
    timewindows: [{
      start: 1200,
      end: 2400
    }],
    duration: 600
  }]
```

```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    rests_ids: ["Break-1"]
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```

### **Configuration**(#configuration)
The configuration is divided in two parts  
Preprocessing parameters will twist the problem in order to simplify or orient the solve
```json
  configuration: {
    preprocessing: {
      cluster_threshold: 5,
      prefer_short_segment: true
    }
  }
```
Resolution parameters will only indicate when stopping the search is admissible
```json
  configuration: {
    resolution: {
      duration: 30,
      iterations: 1000,
      iterations_without_improvment: 100,
    }
  }
```
**VROOM** requires no parameters and stops by itself.  
 **ORtools** Can take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or as a number of iterations without improvement.  
**Jsprit**: Can take a maximum solve duration, a number of iterations wihtout improvment or a number of iteration without variation in the neighborhood search.  

Solve(#solve)
--
The current API can handle multiple particular behavior.
### Lateness²(#lateness)
Once defined at the service level it allow the vehicles to arrive late at a points to serve.
```json
  services: [{
    id: "visit",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      late_multiplier: 0.3,
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    }
  }
```
Defined at the vehicle level, it allow the vehicle to arrive late at the ending depot.
```json
  vehicles: [{
    id: "vehicle_id-1",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    start_point_id: "vehicle-start-1",
    end_point_id: "vehicle-start-1",
    cost_fixed: 500.0,
    cost_late_multiplier, 0.3,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 1.0,
  }]
```
Note : In the case of a global optimization, at least one those two level parameters must be set to zero. All the services __late_multiplier__ or all the vehicles __cost_late_multiplier__
### Multiple vehicles(#multiple-vehicles)
```json
  vehicles: [{
    id: "vehicle_id-1",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    timewindow: {
      start: 0,
      end: 7200
    },
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 500.0,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 1.0,
  },{
    id: "vehicle_id-2",
    router_mode: "truck",
    router_dimension: "distance",
    speed_multiplier: 0.9,
    timewindow: {
      start: 8900,
      end: 14400
    },
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 4000.0,
    cost_distance_multiplier: 0.60,
    cost_time_multiplier: 0,
  }]
```
### Multiple depots(#multiple-depots)
Depots can be set to any points or stay free
```json
  vehicles: [{
    id: "vehicle_id-1",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    start_point_id: "vehicle-start-1",
    end_point_id: "vehicle-start-1",
    cost_fixed: 500.0,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 1.0,
  }, {
    id: "vehicle_id-2",
    router_mode: "truck",
    router_dimension: "distance",
    speed_multiplier: 0.9,
    start_point_id: "vehicle-start-2",
    end_point_id: "vehicle-end-2",
    cost_fixed: 4000.0,
    cost_distance_multiplier: 0.60,
    cost_time_multiplier: 0,
  }, {
    id: "vehicle_id-2",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    end_point_id: "vehicle-end-2",
    cost_fixed: 500.0,
    cost_distance_multiplier: 1.0,
    cost_time_multiplier: 1.0,
  }]
```
### Multiple matrices²(#multiple-matrices)
Every vehicle can have its own matrix to represent its custom speed or route behavior.
```json
  matrices: [{
    id: "matrix-1",
    time: [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0],
    ]
  }, {
    id: "matrix-2",
    time: [
      [0, 541, 1645, 4800],
      [530, 0, 1503, 4465],
      [1506, 1298, 0, 5836],
      [4783, 4326, 5760, 0],
    ]
  }]
```
### Multiple TimeWindows¹(#multiple-timewindows)
```json
  services: [{
    id: "visit",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 1200,
        end: 2400
      }, {
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    }
  }
```
### Pickup and Delivery³(#pickup-and-delivery)
Services can be set with a __pickup__ or a __delivery__ type which inform the solver about the activity to perform. The __pickup__ allows some kind of reload in route, the __delivery__ allows to drop off some resources.
```json
  services: [{
    id: "visit-pickup",
    type: "pickup",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    quantities: [{
      unit_id: "Kg",
      value: 8,
    }]
  }, {
    id: "visit-delivery",
    type: "delivery",
    activity: {
      point_id: "visit-point-2",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    quantities: [{
      unit_id: "Kg",
      value: 6,
    }]
  }]
### Priority²(#priority)
Indicate to the solver which activities are the most important, the priority 0 is two times more important than a priority 1 which is itself two times more important than a priority 2 and so on until the priority 8.
```json
 services: [{
    id: "visit-1",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      late_multiplier: 0.3,
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 600.0,
      priority: 0
    }
  }, {
    id: "visit-2",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      late_multiplier: 0.3,
      timewindows: [{
        start: 3800,
        end: 5000
      }],
      duration: 600.0,
      priority: 2
    }
  }]
```
### Quantities overload²(#quantities-overload)
Allow the vehicles to load more than the defined limit, but add a cost in return of every excess unit.
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    capacities: [{
      unit_id: "Kg",
      limit: 10,
      overload_multiplier: 0.3,
    }],
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```
### Setup duration³(#setup-duration)
When two activities are performed at the same location in a direct sequence allow to have a common time of preparation. It Could be assimilated to a parking time.
```json
 services: [{
    id: "visit-1",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      late_multiplier: 0.3,
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 600.0,
      setup_duration: 1500.0
    }
  }, {
    id: "visit-2",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      late_multiplier: 0.3,
      timewindows: [{
        start: 3800,
        end: 5000
      }],
      duration: 600.0,
      setup_duration: 1500.0
    }
  }]
```
If those two services are performed in a row, the cumulated time of activity will be : 1500 + 600 + 600 = 2700 instead of 4200 if the two duration were set to 2100.
### Skills(#skills)
Some package must be carried by some particular vehicle, or some points can only be visited by some particular vehicle or driver. Skills allow to represent those kind of constraints.  
A vehicle can carry the services or shipments with the defined skills and the ones which have none or part of the current vehicle skills.
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    skills: [
        ["frozen"]
      ]
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```
Services must be carried by a vehicle which have at least all the required skills by the current service or shipment.
```json
  services: [{
    id: "visit",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    skills: ["frozen"]
  }
```
### Alternative Skills³(#alternative-skills)
Some vehicles can change its skills once empty, passing from one configuration to another. Here passing from a configuration it can carry only cool products from another it can only tool frozen ones and vice versa.
```json
  vehicles: [{
    id: "vehicle_id",
    router_mode: "car",
    router_dimension: "time",
    speed_multiplier: 1.0,
    start_point_id: "vehicle-start",
    end_point_id: "vehicle-end",
    skills: [
        ["cool"],
        ["frozen"]
      ]
    cost_fixed: 0.0,
    cost_distance_multiplier: 0.0,
    cost_time_multiplier: 1.0,
  }]
```
```json
  services: [{
    id: "visit-1",
    type: "service",
    activity: {
      point_id: "visit-point-1",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    skills: ["frozen"]
  }, {
    id: "visit-2",
    type: "service",
    activity: {
      point_id: "visit-point-2",
      timewindows: [{
        start: 3600,
        end: 4800
      }],
      duration: 2100.0
    },
    skills: ["cool"]
  }]
```
'
      }
    )
  end
end
