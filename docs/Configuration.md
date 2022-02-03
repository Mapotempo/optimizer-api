The configuration is divided in four parts
Preprocessing parameters will twist the problem in order to simplify or orient the solve
```json
  "configuration": {
    "preprocessing": {
      "cluster_threshold": 5,
      "prefer_short_segment": true
    }
  }
```

You can ask to apply some clustering method before solving. **partitions** structure specifies which clustering steps should be performed.
Each partition step should be defined by a method:
  * **balanced_kmeans**
  * **hierarchical_tree**  
Each partition step should be defined by a metric, which will be used to partition:
  * **duration**
  * **visits**
  * any existing unit  
Each partition step should be defined by a entity:
  * **vehicle**
  * **work_day**

```json
  "configuration": {
    "preprocessing": {
      "partitions": [{
        "method": "balanced_kmeans",
        "metric": "duration",
        "entity": "vehicle"
      },{
        "method": "hierarchical_tree",
        "metric": "visits",
        "entity": "work_day"
      }]
    }
  }
```

Resolution parameters will only indicate when stopping the search is tolerated. In this case, the solve will last at most 30 seconds and at least 3. If it doesn`t find a new better solution within a time lapse of twice times the duration it takes to find the previous solution, the solve is interrupted.
```json
  "configuration": {
    "resolution": {
      "duration": 30000,
      "minimum_duration": 3000,
      "time_out_multiplier": 2
    }
  }
```

**VROOM** requires no parameters and stops by itself.
**ORtools** Can take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or as a number of iterations without improvement.
**Jsprit**: Can take a maximum solve duration, a number of iterations wihtout improvment or a number of iteration without variation in the neighborhood search.

The followings paramaters are available :
* **duration** : ORtools, Jsprit
* **iterations_without_improvment** : ORtools, Jsprit
* **minimum_duration** : ORtools
* **time_out_multiplier** : ORtools
* **stable_iterations** : Jsprit
* **stable_coefficient** : Jsprit

N.B : In most of the case, ORtools is called.

Schedule parameters are only usefull in the case of Schedule Optimisation. Those allow to define the considerated period (__range_indices__) and the indices which are unavailable within the solve (__unavailable_indices__)
```json
  "configuration": {
    "schedule": {
      "range_indices": {
        "start": 0,
        "end": 13
      },
      "unavailable_indices": [5, 6, 12, 13]
    }
  }
```
An alternative exist to those parameters in order to define it by date instead of indices __schedule_range_date__ and __schedule_unavailable_date__.

More specific parameters are also available when dealing with Schedule Optimisation:
* **same_point_day** : all services located at the same geografical point will take place on the same days.
For instance, two visits at the same location with the same minimum_lapse = maximum_lapse = 7 will be served by same vehicle and will take place on every monday if first visit is assigned to monday.
Another exemple : two visits with minimum_lapse = maximum_lapse = 2 will be served by the same vehicle and, if first visit is assigned on tuesday, both second visits will take place on next thursday, third visit
will take place on next saturday and so on.
* **allow_partial_assignment** : solution is valid even if only a subset of one service\'s visits are affected. Default : true.

Restitution parameters allow to have some control on the API response
```json
  "configuration": {
    "restitution": {
      "geometry": true,
      "geometry_polyline": false
    }
  }
```
__geometry__ inform the API to return the Geojson of the route in output, as a MultiLineString feature
__geometry_polyline__ precise that if the geomtry is asked the Geojson must be encoded.
