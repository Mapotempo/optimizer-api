# Resolution

### Solvers
The API has been built to wrap a large panel of Traveling Salesman Problem(TSP) and Vehicle Routing Problem(VRP) attributes in order to call the most fitted solvers.

The currently integreted solvers are:

* **[Vroom](https://github.com/VROOM-Project/vroom)** only handle the TSP and some simple variants of the VRP.
* **[OR-Tools](https://github.com/google/or-tools)** handle a large set of attributes as multiple vehicles, timewindows, quantities, skills and lateness.

### Asserts

In order to select which solver will be used, we have created several assert. If the conditions are satisfied, the solver called can be used.


#### Configuration

* **assert_end_optimization**:
 *OR-Tools*. The VRP has a `duration` or a `iterations_without_improvment` in the `resolution` section of the `configuration`.

#### Vehicles and Matrices
* **assert_matrices_only_one**:
 *Vroom*. The VRP has only one matrix or only one vehicle routing profile (router_mode, router_dimension, speed_multiplier).
* **assert_no_value_matrix**:
 *Vroom*. The matrices contains no value dimension.
* **assert_vehicles_no_alternative_skills**:
 *OR-Tools*. The Vehicles have no alternative skills.
* **assert_vehicles_no_capacity_initial**:
 *Vroom*. The Vehicles have no initial capacity or a initial capacity lower than the limit.
* **assert_vehicles_no_duration_limit**:
 *Vroom*. The Vehicles have no duration constraint.
* **assert_vehicles_no_force_start**:
 *Vroom*. The Vehicles have no start forced.
* **assert_vehicles_no_late_multiplier**:
 *Vroom* The Vehicles have no late multiplier cost.
* **assert_vehicles_no_overload_multiplier**:
 *Vroom* The Vehicles have no capacity with an overload multiplier.
* **assert_vehicles_start_or_end**:
 *Vroom*. The Vehicles should have at least a start_point and an end_point.
* **assert_vehicles_objective**
 *OR-Tools*. The vehicles should have at least one cost among time, distance, waiting and value.
* **assert_square_matrix**
 *OR-Tools*. The matrix, if provided, should be square.
* **assert_no_distance_limitation**
 *Vroom*. The vehicles should have no distance limit.
* **assert_no_free_approach_or_return**
 *Vroom*. The vehicles should not contain the `free_approach` and `free_return` instructions.
* **assert_no_cost_fixed**
 *Vroom*. The output cost of the vehicles should not be provided.

#### Services
* **assert_no_empty_or_fill**:
 *Vroom*. The VRP services should contain no empty or fill.
* **assert_only_empty_or_fill_quantities**:
 *OR-Tools*. A single unit should only have empty or fill, but never both on the same one.
* **assert_services_no_late_multiplier**:
 *Vroom*. The Services have no late multiplier cost.
* **assert_services_no_priority**:
 *Vroom*. The Services have no priority or a priority equal to 4 (which is the value by default).
* **assert_no_service_duration_modifiers**
 *Vroom*. The `duration` and `setup_duration` should not have coefficient or additionnal duration relative to the vehicles.
* **assert_no_exclusion_cost**
 *Vroom*. The exclusion cost of services should not be provided.
* **assert_no_complex_setup_durations**
 *Vroom*. The `setup_duration` should not be different for multiple services at the same point. Neither the coefficient and additionnal setup duration should not be provided.

#### Points
* **assert_points_same_definition**:
 *OR-Tools, Vroom*. All the Points have the same definition, location || matrix_index || matrix_index.

#### Relations
* **assert_no_relations_except_simple_shipments**:
 *Vroom*. The VRP has no relations but some shipments with the same quantities associated to the pickup and the delivery.

#### Misc

* **assert_zones_only_size_one_alternative**:
 *OR-Tools*. The Zones have at most one alternative allocation.
* **assert_correctness_matrices_vehicles_and_points_definition**
 *OR-Tools*, *Vroom*. In cas of matrices provided, the points should refer a `matrix_index`, the vehicles a `matrix_id`. If the matrices are not provided, the points should contain a location.
* **assert_single_dimension**
 *Vroom*. The objectives, constraints and matrices should only refer to a single dimension.


### Solve

The current API can handle multiple particular behaviors. **first_solution_strategy** parameter forces a particular behavior in order to find first solution. In the remainder, \'a\', \'b\' and \'c\' are heuristic names.
Currently, 8 heuristics are available with ORtools :

* **path_cheapest_arc** : Connect start node to the node which produces the cheapest route segment, then extend the route by iterating on the last node added to the route.
* **global_cheapest_arc** : Iteratively connect two nodes which produce the cheapest route segment.
* **local_cheapest_insertion** : Insert nodes at their cheapest position.
* **savings** : The savings value is the difference between the cost of two routes visiting one node each and one route visiting both nodes.
* **parallel_cheapest_insertion** : Insert nodes at their cheapest position on any route; potentially several routes can be built in parallel.
* **first_unbound : First unbound minimum value** : Select the first node with an unbound successor and connect it to the first available node (default).
* **christofides** : Extends route until no nodes can be inserted on it.
* **periodic** : Heuristic for problems with periodicity.

Currently, 3 behaviors are available with **first_solution_strategy** :

* **["a", "b", "c"]** or **"a,b,c"** : Test these heuristics and provide to the proper resolution the one which provided the best solution. There should be at least 2 and at most 3 heuristics provided. periodic heuristic should not be used in this case since it is not applied
on the same category of problems.
* **"self_selection"** : Same as previous, but list is an internal selection of heuristics.
* **"a"** : Forces the solver to use this specific heuristic.

```json
{
  "configuration": {
    "preprocessing": {
      "first_solution_strategy": ["savings", "christofides", "first_unbound"]
    }
  }
}
```

```json
{
  "configuration": {
    "preprocessing": {
      "first_solution_strategy": "self_selection"
    }
  }
}
```

```json
{
  "configuration": {
    "preprocessing": {
      "first_solution_strategy": "periodic"
    },
    "schedule": {
      "range_indices": {
        "start": 0,
        "end": 10
      }
    }
  }
}
```
