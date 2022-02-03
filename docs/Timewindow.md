Define a time interval when a resource is available or when an activity can begin. By default times and durations are supposed to be defined in seconds. If a time matrix is send with the problem, values must be set on the same time unit.
Vehicles only have single timewindow
```json
  "timewindow": {
    "start": 0,
    "end": 7200
  }
```
Activities can have multiple timewindows
```json
  "timewindows": [{
    "start": 600,
    "end": 900
  },{
    "start": 1200,
    "end": 1500
  }],
```

### <a name="multiple-timewindows"></a>Multiple TimeWindows
```json
  "services": [{
    "id": "visit",
    "type": "service",
    "activity": {
      "point_id": "visit-point-1",
      "timewindows": [{
        "start": 1200,
        "end": 2400
      }, {
        "start": 3600,
        "end": 4800
      }],
      "duration": 2100.0
    }
  }
```
