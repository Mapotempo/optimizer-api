# Point

Represent a point in space, it could be defined using a **location** with latitude and longitude coordinates or using a **matrix_index** that links the point to its position within the matrices. This could be usefull if the routing data are provided from an external source.

### location
The location of a point is composed of two fields `lat` and `lon` which are respectively latitude and longitude of the point.

```json
{
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
}
```

### matrix_index
The `matrix_index` directly links the point to the associated rows and columns within the matrices. To know more about it, see [Matrix](Matrix.md).

```json
{
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
}
```
