Describe where an activity take place, when it can be performed and how long it last.
```json
  "activity": {
    "point_id": "visit-point",
    "timewindows": [{
      "start": 3600,
      "end": 4800
    }],
    "duration": 2100.0
  }
```
Some additional parameters are available :
* **setup_duration** allow to combine the activities durations performed at the same place

### Setup Duration
When multiple activities are performed at the same location in a direct sequence it allows to have a common time of preparation. It Could be assimilated to an administrative time.
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
      "setup_duration": 1500.0
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
      "setup_duration": 1500.0
    }
  }]
```
If those two services are performed in a row, the cumulated time of activity will be : 1500 + 600 + 600 = 2700 instead of 4200 if the two duration were set to 2100.
