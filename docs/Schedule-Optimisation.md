Problem definition
---

The plan must be described in its general way, the schedule duration the begin and end days or indices.
Some day may have to be exclude from the resolution, like holiday, and could be defined by its days or indices.
```json
  "configuration": {
      "preprocessing": {
          "prefer_short_segment": true
      },
      "resolution": {
          "duration": 1000,
          "iterations_without_improvment": 100
      },
      "schedule": {
          "range_indices": {
              "start": 0,
              "end": 13
          },
          "unavailable_indices": [2]
      }
  }

```

Vehicle definition
---

The timewindows of a vehicle over a week can be defined with an array using __sequence_timewindows__ instead of a single timewindow.
To link a timewindow with a week day, a __day_index can__ be set (from 0 [monday] to 6 [sunday]). Those time slot will repeated over the entire period for every week contained.
As at the problem definition level, some days could be unavailable to a specific vehicle, this can be defined with __unavailable_work_date__ or __unavailable_work_day_indices__
```json
  {
    "id": "vehicle_id-1",
    "router_mode": "car",
    "router_dimension": "time",
    "speed_multiplier": 1.0,
    "sequence_timewindows": [{
        "day_index": 0,
        "start": 25200,
        "end": 57600
    }, {
        "day_index": 1,
        "start": 25200,
        "end": 57600
    }, {
        "day_index": 2,
        "start": 25200,
        "end": 57600
    }, {
        "day_index": 3,
        "start": 25200,
        "end": 57600
    }, {
        "day_index": 4,
        "start": 25200,
        "end": 57600
    }],
    "start_point_id": "store",
    "end_point_id": "store",
    "unavailable_work_day_indices": [5, 7]
  }
```

Services definition
---

As the vehicles, services have period defined timewindows, using __day_index__ parameter within its timewindows. And some days could be not available to deliver a customer, which can be defined with __unavailable_visit_day_indices__ or __unavailable_visit_day_date__
Some visits could be avoided because it is not mandatory, or any particular reason, __unavailable_visit_indices__ allow to not include a particular visit over the period.
To define multiple visit of a customer over the period, you can set it through the __visits_number__ field.
By default, it will divide the period by the number of visits in order to non overlap the multiple visits.
```json
  {
    "id": "visit-1",
    "type": "service",
    "activity": {
        "point_id": "visit-point-1",
        "timewindows": [{
            "day_index": 0,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 0,
            "start": 61200,
            "end": 97200
        }, {
            "day_index": 2,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 3,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 4,
            "start": 28800,
            "end": 64800
        }],
        "duration": 1200.0
    },
    "visits_number": 2
  }
```
N.B: Shipments are currently not available within the schedule optimisation

Additional parameters
---

**Minimum/Maximum Lapse**
Between to visits of the same mission, it could be necessary to determine exactly the lapse. At this purpose, the __minimum_lapse__ and __maximum_lapse__ fields of services are available.
```json
  {
    "id": "visit-1",
    "type": "service",
    "activity": {
        "point_id": "visit-point-1",
        "timewindows": [{
            "day_index": 0,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 0,
            "start": 61200,
            "end": 97200
        }, {
            "day_index": 2,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 3,
            "start": 28800,
            "end": 64800
        }, {
            "day_index": 4,
            "start": 28800,
            "end": 64800
        }],
        "duration": 1200.0
    },
    "visits_number": 2,
    "minimum_lapse": 7,
    "maximum_lapse": 14
  }
```
