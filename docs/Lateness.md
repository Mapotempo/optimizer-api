# Lateness

Once defined at the service level it allows the vehicles to arrive late to begin the related activity.

```json
{
  "services": [{
    "id": "visit",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    }
  }]
}
```

Defined at the vehicle level, it allows the vehicles to arrive late at the ending depot.

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
    "start_point_id": "vehicle-start-1",
    "end_point_id": "vehicle-start-1",
    "cost_fixed": 500.0,
    "cost_late_multiplier": 0.3,
    "cost_distance_multiplier": 1.0,
    "cost_time_multiplier": 1.0
  }]
}
```

Note : By default, the maximum lateness tolerated of a timewindow is 100% of the actual timewindow. In other words, if the timewindow is 6 hours wide, the maximum lateness will be 6 hours too. This value can be changed through an environment variable (server side) or individually within each timewindow using the field `maximum_lateness`.
