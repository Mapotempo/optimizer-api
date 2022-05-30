# Matrix

Describe the topology of the problem, it represents travel time, distance or value between every points,
Matrices are not mandatory, if time or distance are not defined the vehicle fields related to the routing engine will be used accordingly to compute routing data and place it into the matrices.

```json
{
  "matrices": [{
    "id": "matrix-1",
    "time": [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0]
    ],
    "distance": [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0]
    ]
  }]
}
```

With this matrix defined, the router definition is now optional. Unless the polylines are required in output. To know more about polylines see [Configuration](Configuration.md)

```json
{
  "vehicles": [{
    "id": "vehicle_id",
    "matrix_id": "matrix-1",
    "start_point_id": "vehicle-start",
    "end_point_id": "vehicle-end",
    "timewindow": {
      "start": 0,
      "end": 7200
    },
    "cost_fixed": 0.0,
    "cost_distance_multiplier": 0.0,
    "cost_time_multiplier": 1.0
  }]
}
```

The value matrix is available to represent an additonnal cost matrix which cannot be represented by time or distance. It is always optionnal.

### Multiple Matrices

Every vehicle can have its own matrix to represent its custom speed or route behavior.

```json
{
  "matrices": [{
    "id": "matrix-1",
    "time": [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0]
    ]
  }, {
    "id": "matrix-2",
    "time": [
      [0, 541, 1645, 4800],
      [530, 0, 1503, 4465],
      [1506, 1298, 0, 5836],
      [4783, 4326, 5760, 0]
    ]
  }]
}
```
