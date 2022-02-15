Describe the features of the existing or supposed vehicles. It should be taken in every sense, it could represent a work day of a particular driver/vehicle, or a planning over long period of time. It represents the entity which must travel between points.
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "timewindow": {
      "start": 0,
      "end": 7200
    },
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end"
  }]
```
Costs can also be added in order to fit more precisely the real operating cost
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "timewindow": {
      "start": 0,
      "end": 7200
    },
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 500.0,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  }]
```
The router dimension can be set as distance, this describe that the route between will be the shortest, instead of the fastest.
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "distance",
    "speed_multiplier": 1.0,
    "timewindow": {
      "start": 0,
      "end": 7200
    },
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 500.0,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 0.0
  }]
```
Some additional parameters are available :
* **force_start** [ DEPRECATED ] Force the vehicle to leave its depot at the starting time of its working timewindow. This option is deprecated.
* **shift_preference** Force the vehicle to leave its depot at the starting time of its working timewindow or to get back to depot at the end of its working timewindow or, by default, minimize span.
* **duration** Define the maximum daily duration of the vehicle route. Expressed in seconds.
* **overall_duration** Define the maximum work duration over whole period for the vehicle, if planning goes for several days
* **distance** Define the maximum distance of the vehicle route
* **maximum_ride_time** and **maximum_ride_distance** To define a maximum ride distance or duration, you can set the "maximum_ride_distance" and "maximum_ride_time" parameters with meter and seconds.


### Multiple vehicles
```json
  "vehicles": [{
    "id": "vehicle_id-1",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "timewindow": {
      "start": 0,
      "end": 7200
    },
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 500.0,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  },{
    "id": "vehicle_id-2",
    "router_mode": "truck",
    "router_dimension": "distance",
    "speed_multiplier": 0.9,
    "timewindow": {
      "start": 8900,
      "end": 14400
    },
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 4000.0,
    "cost_distance_multiplier": 0.60,
    "cost_time_multiplier": 0
  }]
```
### Multiple depots
Depots can be set to any points or stay free (in such case don\'t send the associated key word)
```json
  "vehicles": [{
    "id": "vehicle_id-1",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "start_point_id": "vehicle-start-1",
    "end_point_id": "vehicle-start-1",
    "cost_fixed": 500.0,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  }, {
    "id": "vehicle_id-2",
    "router_mode": "truck",
    "router_dimension": "distance",
    "speed_multiplier": 0.9,
    "start_point_id": "vehicle-start-2",
    "end_point_id": "vehicle-end-2",
    "cost_fixed": 4000.0,
    "cost_distance_multiplier": 0.60,
    "cost_time_multiplier": 0
  }, {
    "id": "vehicle_id-2",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "end_point_id": "vehicle-end-2",
    "cost_fixed": 500.0,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  }]
```
