Routes structure allows you to provide an initial solution. You can provide routes when calling ORtools solver or periodic heuristic.
* When using ORtools solver, this route is used as initial solution. That is, we do not use any heuristic to find the first solution but we use provided one.
If the route is unfeasible we compute initial solution using a heuristic, as if no route was provided.
* When using periodic heuristic, we start from the solution corresponding to provided routes. If one of the missions is not feasible at its position it will be unassigned.
