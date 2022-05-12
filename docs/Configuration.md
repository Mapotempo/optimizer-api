# Configuration

The configuration is divided in four parts
* **[preprocessing](#preprocessing)**
* **[resolution](#resolution)**
* **[schedule](#schedule)**
* **[restitution](#restitution)**

## Preprocessing

Preprocessing parameters will prepare the problem in order to simplify or orient the resolution

```json
{
  "configuration": {
    "preprocessing": {
      "cluster_threshold": 5,
      "prefer_short_segment": true
    }
  }
}
```

### max_split_size

All problem with a service number greater than the given value will be split in two parts using "balalanced_kmeans". The two parts create each one a subproblem. Each subproblem is aswell split in two parts until the service number in the considered subproblem decreases below `max_split_size`. This split happen before any matrix computation. Its purpose is to avoid the computation of too large matrices.

### cluster_threshold

This will merge (zip) the services in a [clique](https://en.wikipedia.org/wiki/Clique_(graph_theory) whose maximum distance is given by `cluster_threshold` if the condition allows them to be merged. In the unzip phase, a TSP will be applied to each clique in order to provide a complete route.

### prefer_short_segment

In some cases, due to one-way streets, multiple services located in the same street will not be performed in a single row. The vehicle, or vehicles will come multiple times to serve them. As there no difference in the objective function between a solution with a single pass or multiple ones, `prefer_short_segment` will introduce a slight change in the time and distance matrix to penalize intermediate middle range routes. This will tend to favorize long legs in the street while legs close to zero will not be impacted.

### partitions

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
{
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
}
```

## Resolution

Resolution parameters will only indicate when stopping the search is tolerated. In this case, the solve will last at most 30 seconds and at least 3. If it doesn't find a new better solution within a time lapse of twice times the duration it takes to find the previous solution, the solve is interrupted.
```json
{
  "configuration": {
    "resolution": {
      "duration": 30000,
      "minimum_duration": 3000,
      "time_out_multiplier": 2
    }
  }
}
```

**VROOM** requires no parameters and stops by itself.

**ORtools** Can take a maximum solve duration, or can stop by itself depending on the solve state as a time-out between two new best solution, or as a number of iterations without improvement.

N.B : In most of the case, ORtools is called.

### duration

`duration` is the maximum time the resolution can last. It does not take into account the computation time of matrices neither the time to eventually perform partitions methods.

### minimum_duration

`minimum_duration` is the minimum time the resolution should last. The resolution can interrupt itself before the `duration` if there is no more improvement of the best solution. The early interruption may be customized using `time_out_multiplier`.

### time_out_multiplier

The early interruption may happen between `minimum_duration` and `duration`. We want to eventually stop the resolution once a stability level is reached. At this purpose we consider the time when the current best solution has been found. Let consider time_out_multiplier is equal to 1. If the current best solution has been found after 5 seconds of search. Then the time to consider we have reached a stability is : 5 seconds (current time) + 1 * 5 seconds (additionnal time to reach the stability level). So the resolution will stop at 10 seconds at the earliest (if and only if `duration` is greater than 10 seconds). Note that, if `minimum_duration` is 15 seconds, for example, the resolution won't stop until this time.

### vehicle_limit

The solution returned will not contain more routes than the defined `vehicle_limit` as it limits the number of vehicles which could be used.

### evaluate_only

The parameter force the solver to only compute the first solution. It should mainly be used to evaluate `routes` provided as part of the `vrp`.

### several_solutions

From a single `vrp` we expect to have multiple solutions provided in output. A `variation_ratio` may be provided to introduce some perturbations in the matrices.

### batch_heuristic

We only want to have the first solution found by each of the `first_solution_strategy` provided.

### variation_ratio

The `variation_ratio` will introduce some perturbations in the matrices between the resolutions created using `several_solutions` parameter.

### solver

In the case of the use of periodic heuristic, it defines if the solver should be used afterwars in order to improve the solution.

### minimize_days_worked

In the case of the use of periodic heuristic, it defines if the solution should reduce the number of days worked instead of trying to balance the work across the time horizon.

### same_point_day

In the case of the use of periodic heuristic, all the `services` with the same `point_id` should be served by the same vehicle within the same route at the same day.

For instance, two visits at the same location with the same minimum_lapse = maximum_lapse = 7 will be served by same vehicle and will take place on every monday if first visit is assigned to monday.
Another exemple : two visits with minimum_lapse = maximum_lapse = 2 will be served by the same vehicle and, if first visit is assigned on tuesday, both second visits will take place on next thursday, third visit
will take place on next saturday and so on.

### allow_partial_assignment

In the case of the use of periodic heuristic, it defines if it is allowed to only plan a subset of the visits of a single `service`.


## Schedule

Schedule parameters are only usefull in the case of Schedule Optimisation. Those allow to define the considerated period (**range_indices**) and the indices which are unavailable within the solve (**unavailable_indices**)

```json
{
  "configuration": {
    "schedule": {
      "range_indices": {
        "start": 0,
        "end": 13
      },
      "unavailable_indices": [5, 6, 12, 13]
    }
  }
}
```
An alternative exists to these parameters in order to define it by date instead of indices: **range_date**, **unavailable_date** and **unavailable_date_ranges**. Note that `index` and `date` based field are mutually exclusive.

### range_indices

It defines the total time horizon to consider the scheduling problem.

```json
{
  "schedule": {
    "range_indices": {
      "start": 0,
      "end": 13
    }
  }
}
```

### unavailable_indices and unavailable_index_ranges

Some days may be unavailable for all vehicles.These days may be defined individually or by range.

```json
{
  "schedule": {
    "range_indices": {
      "start": 0,
      "end": 13
    },
    "unavailable_indices": [5, 6, 12, 13],
    "unavailable_index_ranges": [{
      "start": 5,
      "end": 6
    }, {
      "start": 12,
      "end": 13
    }]
  }
}
```

### range_date

Similarly to `range_indices` it allows to define the time horizon considered by the scheduling problem.

```json
{
  "schedule": {
    "range_date": {
      "start": "2017-01-27",
      "end": "2017-02-09"
    }
  }
}
```

### unavailable_date and unavailable_date_ranges

```json
{
  "schedule": {
    "range_date": {
      "start": "2017-01-27",
      "end": "2017-02-09"
    },
    "unavailable_date": ["2017-02-01", "2017-02-02", "2017-02-08", "2017-02-09"],
    "unavailable_date_ranges": [{
      "start": "2017-02-01",
      "end": "2017-02-02"
    }, {
      "start": "2017-02-08",
      "end": "2017-02-09"
    }]
  }
}
```

## Restitution
Restitution parameters allow to have some control on the API response

### geometry
It informs the API to return the Geojson of the route in output, as a MultiLineString feature.

```json
{
  "configuration": {
    "restitution": {
      "geometry": true
    }
  }
}
```

### intermediate_solutions

If the solver has the capability to return the intermediate solutions, the parameter allows to generate the associated solutions, which then allows to reach the current best solution at any time of the resolution.

### csv

It indicates that once the resolution is finished, the solution should be returned in a CSV format. Note that, it may also be asked by putting `.csv` in the url called to retrieve the solution.

### use_deprecated_csv_headers

The csv headers have evolved through time, the current ones are closer to the format expected by Mapotempo Web. The parameter allows to retrieve the "legacy" headers.

