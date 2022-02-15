Inform about the drivers obligations to have some rest within a route
```json
  "rests": [{
    "id": "Break-1",
    "timewindows": [{
      "start": 1200,
      "end": 2400
    }],
    "duration": 600
  }]
```

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
    "rests_ids": ["Break-1"],
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
```
