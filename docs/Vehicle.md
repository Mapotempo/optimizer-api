# Vehicle

Describe the features of the existing or supposed vehicles. It should be taken in every sense, it could represent a work day of a particular driver/vehicle, or a planning over long period of time. It represents the entity which must travel between points.
```json
{
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
}
```

## Costs

Costs can also be added in order to fit more precisely the real operating cost

```json
{
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
}
```
## Routing profile

The fields related to the routing profile are a direct tranposition of the fields define within [Router-API](http://swagger.mapotempo.com/?url=https://router.mapotempo.com/0.1/swagger_doc) project
* router_mode
* router_dimension
* speed_multiplier
* area
* speed_multiplier_area
* traffic
* departure
* track
* motorway
* toll
* trailers
* weight
* weight_per_axle
* height
* width
* length
* hazardous_goods
* max_walk_distance
* approach
* snap
* strict_restriction

## VRP properties

### matrix_id

It links the current vehicle to a [matrix](Matrix.md) and its dimensions.

### value_matrix_id

The value matrix may be provided separatly, this is particularly the case when the time and distance dimensions should be computed using the routing profile. `value_matrix_id` allows to point a particular matrix for its `value` dimension.

### coef_service

`coef_service` allows to ponderate the [activity](Activity.md) durations.

### additional_service

It applies a fix duration to the route activities[Activity.md].

### coef_setup

This field is similar to `coef_service` but applies on `setup_duration`.

### additional_setup


This field is similar to `additional_service` but applies on `setup_duration`.

### shift_preference

`force_start` Forces the vehicle to leave its depot at the starting time of its working timewindow. While `force_end`  force to get back to depot at the end of the vehicle working timewindow. By default, the value is `minimize_span`, it tries to minimize the total duration of the route even by shifting the start and end times.

### duration

It limits the total duration of the vehicle route.

### distance

It limits the total distance of the vehicle route.

### maximum_ride_time

It limits the route duration between two activities of the route.

### maximum_ride_distance

It limits the route distance between two activities of the route.

### skills

The vehicle `skills` represents the sets of properties it can handle. See [Skills.md](Skills.md) for more details.

### free_approach

The first leg of the route may not have to be counted in the objective function. But all the other constraints should apply.

### free_return

The first leg of the route may not have to be counted in the objective function. But all the other constraints should apply.

---
The following fields are related to [scheduling problems](Schedule-Optimisation.md).

### unavailable_work_day_indices

The given may not work all days of the time horizon. This field allows to exclude a set of day indices. The date based field is `unavailable_work_date`

### unavailable_index_ranges

The given may not work all days of the time horizon. This field allows to exclude a set of day ranges when the vehicle cannot perform routes. The date based field is `unavailable_date_ranges`

## Multiple vehicles

```json
{
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
}
```

## Multiple depots

Depots can be set to any points or stay free (in such case don\'t send the associated key word)

```json
{
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
}
```
