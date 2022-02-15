### Solvers
The API has been built to wrap a large panel of  Traveling Salesman Problem(TSP) and Vehicle Routing Problem(VRP) constraints in order to call the most fitted solvers.

The currently integreted solvers are:
*   **[Vroom](https://github.com/VROOM-Project/vroom)** only handle the basic Traveling Salesman Problem.
*   **[OR-Tools](https://github.com/google/or-tools)** handle multiple vehicles, timewindows, quantities, skills and lateness.
*   **[Jsprit](https://github.com/graphhopper/jsprit)** handle multiple vehicles, timewindows, quantities, skills and setup duration. (Not used @Mapotempo)

### Asserts

In order to select which solver will be used, we have created several assert. If the conditions are satisfied, the solver called can be used.

*   **assert_at_least_one_mission** :
 *OR-Tools, Vroom*. The VRP has at least one service or one shipment.
*   **assert_end_optimization** :
 *OR-Tools*. The VRP has a resolution_duration or a resolution_iterations_without_improvment.
*   **assert_matrices_only_one** :
 *Vroom*. The VRP has only one matrix or only one vehicle configuration type (router_mode, router_dimension, speed_multiplier).
*   **assert_no_relations** :
 *Vroom*. The VRP has no relations or every relation has no linked_ids and no linked_vehicle_ids.
*   **assert_no_routes** :
 *Vroom*. The Routes have no mission_ids.
*   **assert_no_shipments** :
 *Vroom*. The VRP has no shipments.
*   **assert_no_shipments_with_multiple_timewindows** :
 The Shipments pickup and delivery have at most one timewindow.
*   **assert_no_value_matrix** :
 *Vroom*. The matrices have no value.
*   **assert_no_zones** :
 The VRP contains no zone.
*   **assert_one_sticky_at_most** :
 The Services and Shipments have at most one sticky_vehicle.
*   **assert_one_vehicle_only_or_no_sticky_vehicle** :
 *Vroom*. The VRP has no more than one vehicle || The Services and Shipments have no sticky_vehicle.
*   **assert_only_empty_or_fill_quantities** :
 *OR-Tools*. The VRP have no services which empty and fill the same quantity.
*   **assert_points_same_definition** :
 *OR-Tools, Vroom*. All the Points have the same definition, location || matrix_index || matrix_index.
*   **assert_services_at_most_two_timewindows** :
 The Services have at most two timewindows
*   **assert_services_no_capacities** :
 *Vroom*. The Vehicles have no capacity.
*   **assert_services_no_late_multiplier** :
 The Services have no late multiplier cost.
*   **assert_services_no_multiple_timewindows** :
 The Services have at most one timewindow.
*   **assert_services_no_priority** :
 *Vroom*. The Services have a priority equal to 4 (which means no priority).
*   **assert_services_no_skills** :
 *Vroom*. The Services have no skills.
*   **assert_services_no_timewindows** :
 *Vroom*. The Services have no timewindow.
*   **assert_services_quantities_only_one** :
 The Services have no size quantity strictly superior to 1.
*   **assert_shipments_no_late_multiplier** :
 The Shipments have no pickup and delivery late multiplier cost.
*   **assert_units_only_one** :
 The VRP has at most one unit.
*   **assert_vehicles_at_least_one** :
 *OR-Tools*. The VRP has at least one vehicle.
*   **assert_vehicles_capacities_only_one** :
 The Vehicles have at most one capacity.
*   **assert_vehicles_no_alternative_skills** :
 *OR-Tools*. The Vehicles have no altenartive skills.
*   **assert_vehicles_no_capacity_initial** :
 *OR-Tools*. The Vehicles have no inital capcity different than 0.
*   **assert_vehicles_no_duration_limit** :
 *Vroom*. The Vehicles have no duration.
*   **assert_vehicles_no_end_time_or_late_multiplier** :
 *Vroom*. The Vehicles have no timewindow or have a cost_late_multiplier strictly superior to 0.
*   **assert_vehicles_no_force_start** :
 The Vehicles have no start forced.
*   **assert_vehicles_no_late_multiplier** :
 The Vehicles have no late multiplier cost.
*   **assert_vehicles_no_overload_multiplier** :
 The Vehicles have no overload multiplier.
*   **assert_vehicles_no_rests** :
 The Vehicles have no rest.
*   **assert_vehicles_no_timewindow** :
 The Vehicles have no timewindow.
*   **assert_vehicles_no_zero_duration** :
 *OR-Tools*. The Vehicles have no duration equal to 0.
*   **assert_vehicles_only_one** :
 *Vroom*. The VRP has only one vehicle and the VRP has no schedule range indices and no schedule range date.
*   **assert_vehicles_start** :
 The Vehicles have no start_point.
*   **assert_vehicles_start_or_end** :
 *Vroom*. The Vehicles have no start_point and no end_point.
*   **assert_zones_only_size_one_alternative** :
 *OR-Tools*. The Zones have at most one alternative allocation.

### Solve

The current API can handle multiple particular behaviors. **first_solution_strategy** parameter forces a particular behavior in order to find first solution. In the remainder, \'a\', \'b\' and \'c\' are heuristic names.
Currently, 8 heuristics are available with ORtools :
*   **path_cheapest_arc** : Connect start node to the node which produces the cheapest route segment, then extend the route by iterating on the last node added to the route.
*   **global_cheapest_arc** : Iteratively connect two nodes which produce the cheapest route segment.
*   **local_cheapest_insertion** : Insert nodes at their cheapest position.
*   **savings** : The savings value is the difference between the cost of two routes visiting one node each and one route visiting both nodes.
*   **parallel_cheapest_insertion** : Insert nodes at their cheapest position on any route; potentially several routes can be built in parallel.
*   **first_unbound : First unbound minimum value** : Select the first node with an unbound successor and connect it to the first available node (default).
*   **christofides** : Extends route until no nodes can be inserted on it.
*   **periodic** : Heuristic for problems with periodicity.

Currently, 3 behaviors are available with **first_solution_strategy** :
* **\'a,b,c\'** : Test these heuristics and provide to full resolution the one which provided the best solution. There should be at least 2 and at most 3 heuristics provided. periodic heuristic should not be used in this case since it is not applied
on the same category of problems.
* **\'self_selection\'** : Same as previous, but list is an internal selection of heuristics.
* **\'a\'** : Forces the solver to use this specific heuristic.

```json
  "configuration": {
    "preprocessing": {
      "first_solution_strategy": "savings,christofides,first_unbound"
    }
  }
```

```json
  "configuration": {
    "preprocessing": {
      "first_solution_strategy": "self_selection"
    }
  }
```

```json
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
```
