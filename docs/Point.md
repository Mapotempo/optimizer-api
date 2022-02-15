Represent a point in space, it could be called as a __location__ with latitude and longitude coordinates.
With coordinates
```json
  "points": [{
      "id": "vehicle-start",
      "location": {
        "lat": start_lat,
        "lon": start_lon
      }
    }, {
      "id": "vehicle-end",
      "location": {
        "lat": start_lat,
        "lon": start_lon
      }
    }, {
      "id": "visit-point-1",
      "location": {
        "lat": visit_lat,
        "lon": visit_lon
      }
    }, {
      "id": "visit-point-2",
      "location": {
        "lat": visit_lat,
        "lon": visit_lon
      }
    }]
```
Or as a __matrix_index__ can be used to link to its position within the matrices.
This could be usefull if the routing data are provided from an external source.
```json
  "points": [{
      "id": "vehicle-start",
      "matrix_index": 0
    }, {
      "id": "vehicle-end",
      "matrix_index": 1
    }, {
      "id": "visit-point-1",
      "matrix_index": 2
    }, {
      "id": "visit-point-2",
      "matrix_index": 3
    }]
```
