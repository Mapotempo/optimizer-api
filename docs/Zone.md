In order to distribute geographically the problem, some sector can be defined. The API takes geojson and encrypted geojson. A zone contains the vehicles which are allowed to perform it at the same time. The API call make it feasible to have multiple elaborate combinations.
But only a single complex combination (multiple vehicles allowed to perform activities within the area at the same time).
```json
      "zones": [{
        "id": "zone_0",
        "polygon": {
        "type": "Polygon",
        "coordinates": [[[0.5,48.5],[1.5,48.5],[1.5,49.5],[0.5,49.5],[0.5,48.5]]]
        },
        "allocations": [["vehicle_0", "vehicle_1"]]
      }]
```
Or multiple unique vehicle alternative are currently implemented at the solver side.
```json
      "zones": [{
        "id": "zone_0",
        "polygon": {
        "type": "Polygon",
        "coordinates": [[[0.5,48.5],[1.5,48.5],[1.5,49.5],[0.5,49.5],[0.5,48.5]]]
        },
        "allocations": [["vehicle_0"], ["vehicle_1"]]
      }]
```
