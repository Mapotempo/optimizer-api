# Activity

Describe where an activity take place, when it can be performed and how long it last.
```json
{
  "activity": {
    "point_id": "visit-point",
    "timewindows": [{
      "start": 3600,
      "end": 4800
    }],
    "duration": 2100.0
  }
}
```
The available parameters are the following :
* **point_id** allows to designate the point where the activity takes place
* **duration** represents the uncompressible duration of the activity
* **setup_duration** represents the compressible duration in case of successive activities performed at the same point
* **timewindows** are the time slots where activities may be performed
* **late_multiplier** represents the tolerance to lateness. It is a cost applied by second of violation (0 means no lateness).
* **position** forces the activity to a given position into the route.

### point_id
It should refer to the id of point defined in the `points` field belonging to the `vrp`.

```json
{
  "vrp": {
     "services": [{
        "id": "visit-1",
        "activity": {
          "point_id": "visit-point-1"
        }
     }],
     "points": [{
       "id": "visit-point-1",
       "location": {
         "lat": 49.0,
         "lon": 1.0
       }
     }]
  }
}

```

### duration
It represents the time required to perform the current and specific activity. It could depend on the vehicle if the fields `coef_service` or
`additional_service` are defined by the vehicle which is assigned to perform the activity in the solution.
```json
{
   "services": [{
    "id": "visit-1",
    "activity": {
      "point_id": "visit-point-1",
      "duration": 600.0
    }
  }, {
    "id": "visit-2",
    "activity": {
      "point_id": "visit-point-1",
      "duration": 600.0
    }
  }]
}
```

### setup duration
When multiple activities are performed at the same location in a direct sequence it allows to have a common time of preparation. It Could be assimilated to an administrative time.
```json
{
  "services": [{
    "id": "visit-1",
    "activity": {
      "point_id": "visit-point-1",
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }, {
    "id": "visit-2",
    "activity": {
      "point_id": "visit-point-1",
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }]
}
```
If those two services are performed in a row, the cumulated time of activity will be : 1500 + 600 + 600 = 2700 instead of 4200 if the two duration were set to 2100.

### timewindows
```json
{
  "services": [{
    "id": "visit-1",
    "activity": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }, {
    "id": "visit-2",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3800,
        "end": 5000
      }],
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }]
}
```

### late_multiplier
It represents the cost applied for each second arrived late to start the activity.
```json
{
  "services": [{
    "id": "visit-1",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3600,
        "end": 4800
      }],
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }, {
    "id": "visit-2",
    "activity": {
      "point_id": "visit-point-1",
      "late_multiplier": 0.3,
      "timewindows": [{
        "start": 3800,
        "end": 5000
      }],
      "duration": 600.0,
      "setup_duration": 1500.0
    }
  }]
}
```
Note that, by default a maximum lateness value is fulfilled (depending on the server configuration) to limit the maximum lateness to 100% of each timewindow. Having a timewindow with a span of 1 hour. You could refer to [Lateness](Lateness.md) for more details.

### position
The available values are : `neutral`, `always_first`, `always_middle`, `always_last`, `never_first`, `never_middle`, `never_last`).

```json
{
  "services": [{
    "id": "visit-1",
    "activity": {
      "point_id": "visit-point-1",
      "position": "always_first"
    }
  }, {
    "id": "visit-2",
    "activity": {
      "point_id": "visit-point-1",
      "position": "always_first"
    }
  }]
}
```
Note that if multiple activities of different services have the same position, the solution will keep these activities grouped a the given position.
