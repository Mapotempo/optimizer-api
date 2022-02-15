Some package must be carried by some particular vehicle, or some points can only be visited by some particular vehicle or driver. Skills allow to represent those kind of constraints.
A vehicle can carry the __services__ or __shipments__ with the defined __skills__ and the ones which have none or part of the current vehicle skills.
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "skills": [
        ["frozen"]
      ],
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
```
Missions must be carried by a vehicle which have at least all the required skills by the current service or shipment.
```json
  "services": [{
    "id": "visit",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "skills": ["frozen"]
  }
```

### <a name="alternative-skills"></a>Alternative Skills
_This feature is currently only supported by Jsprit_

Some vehicles can change its __skills__ once empty, passing from one configuration to another. Here passing from a configuration it can carry only cool products from another it can only tool frozen ones and vice versa.
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "skills": [
        ["cool"],
        ["frozen"]
      ],
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
```
```json
  "services": [{
    "id": "visit-1",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "skills": ["frozen"]
  }, {
    "id": "visit-2",
    "type": "service",
    "activity": {
      "point_id": "visit-point-2",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "skills": ["cool"]
  }]
```
