# Service and Shipment

### Service

Describe more specifically the activities to be performed.
Services are single [activities](Activity.md) which are self-sufficient.

```json
  "services": [{
    "id": "visit",
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

Shipments are a couple of indivisible [activities](Activity.md), the **pickup** is the action which must take-off a package and the **delivery** the action which deliver this particular package.
**pickup** and **delivery** are build following the **[activity](Activity.md)** model

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
