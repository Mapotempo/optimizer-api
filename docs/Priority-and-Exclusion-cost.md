Priority indicate to the solver which activities are the most important, the priority 0 is two times more important than a priority 1 which is itself two times more important than a priority 2 and so on until the priority 8. The default value is 4.
```json
 "services": [{
    "id": "visit-1",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 600.0,
      "priority": 0
    }
  }, {
    "id": "visit-2",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3800,
        "end": 5000
      }],
      "duration": 600.0,
      "priority": 2
    }
  }]
```
The "exclusion_cost" parameter override the priority and define at which cost the current activity can be unassigned.
### <a name="quantities-overload"></a>Quantities overload¹
Allow the vehicles to load more than the defined limit, but add a cost at every excess unit.
```json
  "vehicles": [{
    "id": "vehicle_id",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "capacities": [{
      "unit_id": "unit-Kg",
      "limit": 10,
      "overload_multiplier": 0.3
    }],
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
```
