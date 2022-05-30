# Service and Shipment

## Service

Describe more specifically the activities to be performed.
Services are single [activities](Activity.md) which are self-sufficient.

```json
{
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
  }]
}
```

### exclusion_cost

The `exclusion_cost` always to represent some kind of revenue earned for performing this service. If the service is not part of the solution, then this cost is applied. This means that if a service is not part of the solution, serving it (through time and distance cost) is more expansive to serve it than letting it aside.

### priority

In most of the case, the points should "theoriticaly be served". Nevertheless, it may not be feasible to have all the services active in the solution. At this purpose, the priority allows to define which services are prefered.
The priority 0 is the more important, while 8 priority is not important.

### sticky_vehicle_ids

`sticky_vehicle_ids` field allows user to specify whenever only a subset of vehicles can be assigned to this service. There can be one or several vehicle ids in the list.
### skills

The service skills are the properties required for a vehicle to perform the associated activity. See [Skills.md](Skills.md) for more details.

### activity and activities

A service may be composed of one specific `activity` or a set of alternative `activities`. See [Activity.md](Activity.md) for more details.

### quantities

The `quantities` are the value of each `unit` that are exchanged once the activity is performed. See [Unit.md](Unit.md) for more details

---

The following fields are related to [scheduling problems](Schedule-Optimisation.md)

### visits_number

It defines the number of visits to fulfill the current service needs.

### minimum_lapse

`minimum_lapse` defines the minimum number of days between two visits of this service.

### maxmimum_lapse

`maximum_lapse` defines the maximum number of days between two visits of this service.

### first_possible_day_indices

Each visit may have a particular first day index to be performed. The date based field is `first_possible_dates`

### last_possible_day_indices
Each visit may have a particular last day index to be performed. The date based field is `last_possible_dates`

### unavailable_visit_indices

In the given time horizon, some visits may not have to be perfomed due to vacancies or holidays.

### unavailable_visit_day_indices

The final customer to be served may have some particular closing days. The date based field is `unavailable_visit_date`

### unavailable_index_ranges

This field is similar to `unavailable_visit_day_indices` but instead of defining these days by days, it is possible to define it through ranges. The date based field is `unavailable_date_ranges`

## Shipment

Shipments are a couple of indivisible [activities](Activity.md), the **pickup** is the action which must take-off a package and the **delivery** the action which deliver this particular package.
**pickup** and **delivery** are build following the **[activity](Activity.md)** model

```json
{
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
    "sticky_vehicle_ids": ["vehicle_id1"]
  }]
}
```

### direct

If a `shipment` is marked as `direct`, then the `pickup` and the `delivery` have to be performed in `sequence`.

### maximum_inroute_duration

 the field `maximum_inroute_duration` allows to define a time limit between the `pickup` and the `delivery`.
