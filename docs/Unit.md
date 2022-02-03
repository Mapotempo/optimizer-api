Describe the dimension used for the goods. ie : kgs, litres, pallets...etc
```json
  "units": [{
    "id": "unit-Kg",
    "label": "Kilogram"
  }]
```

### Capacity

Define the limit allowed for a defined unit into the vehicle.
```json
  "capacities": [{
    "unit_id": "unit-Kg",
    "limit": 10,
    "overload_multiplier": 0
  }]
```
Which is defined as follows
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
    "capacities": [{
      "unit_id": "unit-Kg",
      "limit": 10,
      "overload_multiplier": 0
    }],
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
```

### Quantity

Inform of the package size, shift within a route once loaded into a vehicle.
```json
  "quantities": [{
    "unit_id": "unit-Kg",
    "value": 8
  }]
```
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
    "quantities": [{
      "unit_id": "unit-Kg",
      "value": 8
    }]
  }
```
```json
  "shipments": [{
    "id": "pickup_delivery",
    "pickup": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "delivery": {
      "point_id": "visit-point-2",
      "timewindows": [{
        "start": 4500,
        "end": 7200
      }],
      "duration": 1100.0
    },
    "quantities": [{
      "unit_id": "unit-Kg",
      "value": 8
    }]
  }
```
The "refill" parameters allow to let the optimizer decide how many values of the current quantity can be loaded at the current activity.
