Once defined at the service level it allow the vehicles to arrive late at a points to serve.
```json
  "services": [{
    "id": "visit",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    }
  }
```
Defined at the vehicle level, it allow the vehicle to arrive late at the ending depot.
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
    "start_point_id": "vehicle-start-1",
    "end_point_id": "vehicle-start-1",
    "cost_fixed": 500.0,
    "cost_late_multiplier": 0.3,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  }]
```
Note : In the case of a global optimization, at least one those two parameters (__late_multiplier__ or __cost_late_multiplier__) must be set to zero, otherwise only one vehicle would be used.
