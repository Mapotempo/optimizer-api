Describe the topology of the problem, it represent travel time, distance or value between every points,
Matrices are not mandatory, if time or distance are not defined the router wrapper will use the points data to build it.
```json
  "matrices": [{
    "id": "matrix-1",
    "time": [
      [0, 655, 1948, 5231],
      [603, 0, 1692, 4977],
      [1861, 1636, 0, 6143],
      [5184, 4951, 6221, 0]
    ]
  }]
```
With this matrix defined, the vehicle definition is now the following :
```json
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
```
Note that every vehicle could be linked to different matrices in order to model multiple transport mode.

In the case the distance cost is greater than 0, it will be mandatory to transmit the related matrix
```json
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
```
Whenever there is no time constraint and the objective is only set on distance, the time matrix is not mandatory.

An additional value matrix is available to represent a cost matrix.

### Multiple Matrices
Every vehicle can have its own matrix to represent its custom speed or route behavior.
```json
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
```
