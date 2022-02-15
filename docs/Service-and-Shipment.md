### Service
Describe more specifically the activities to be performed.
Services are single [activities](Activity.md) which are self-sufficient.
```json
  "services": [{
    "id": "visit",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "position": "always_first",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "sticky_vehicle_ids": ["vehicle_id1", "vehicle_id2"]
  }
```

**position** field allows user to provide an indication on when service activity should take place among one route. Several values are available for this parameter : 
* "neutral" (default value) : service can take place at any position of the route, 
* "always_first" : service should take place at the beginning of the route that is to say in first position or among other services with this constraint, at the beginning of the route.
* "always_last" : service should take place at the end of the route that is to say in last position or among other services with this constraint, at the end of the route.
* "always_middle" : service should not be in first or last positions of the route.

Complementary options are also available : "never_first", "never_last", "never_middle".

**sticky_vehicle_ids** field allows user to specify whenever only a subset of vehicles can be assigned to this service. There can be one or several vehicle ids in the list.

### Shipment
Shipments are a couple of indivisible [activities](Activity.md), the __pickup__ is the action which must take-off a package and the __delivery__ the action which deliver this particular package.
__pickup__ and __delivery__ are build following the __[activity](Activity.md)__ model
```json
  "shipments": [{
    "id": "shipment",
    "pickup": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }]
    },
    "delivery": {
      "point_id": "visit-point-2",
      "duration": 2100.0
    },
    "sticky_vehicle_ids": ["vehicle_id1"],
  }]
```

### Pickup or Delivery
Services can be set with a __pickup__ or a __delivery__ type which inform the solver about the activity to perform. The __pickup__ allows a reload action within the route, the __delivery__ allows to drop off resources.
```json
  "services": [{
    "id": "visit-pickup",
    "type": "pickup",
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
  }, {
    "id": "visit-delivery",
    "type": "delivery",
    "activity": {
      "point_id": "visit-point-2",
      "position": "always_last",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    },
    "quantities": [{
      "unit_id": "unit-Kg",
      "value": 6
    }]
  }]
```
