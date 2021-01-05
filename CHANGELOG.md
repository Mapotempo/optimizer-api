# Changelog

## [Unreleased]

## [v0.1.5] - 2021-01-05

### Added

- Allow support for semicolumn and tabulation in CSV files
- Collect current distance from OR-Tools
- Allow initial routes when clustering methods are required
- Position field for activities
- Sheduling and initial routes are now compatible
- Unfeasible missions are removed from routes [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Log reasons of unfeasible missions [#35](https://github.com/Mapotempo/optimizer-api/pull/35)
- Read and log OR-Tools version
- Route costs [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- Log of matrix computation [#52](https://github.com/Mapotempo/optimizer-api/pull/52)
- Allow multidepot within clustering [#56](https://github.com/Mapotempo/optimizer-api/pull/56)
- Introduce direct shipments, pickup and delivery must be consecutive [#51](https://github.com/Mapotempo/optimizer-api/pull/51)
- Return total_time and total_travel_distance from scheduling heuristic [#63](https://github.com/Mapotempo/optimizer-api/pull/63)
- Return original ids for missions and vehicles [#73](https://github.com/Mapotempo/optimizer-api/pull/73)
- Introduce minimize_days_worked parameter for scheduling heuristic [#89](https://github.com/Mapotempo/optimizer-api/pull/89)
- Detect unconsistent same_point_day defintion [#76](https://github.com/Mapotempo/optimizer-api/pull/76)

### Changed

- Cache is now part of wrappers hash
- Update tests
- Refactoring of the chaining of the various solving procedures (Rework define_process)
- Now use OR-Tools asserts instead or recompiling the entire project
- Reject too small lapses
- Bump OR-Tools to v7.8
- Various edits, improvments and refactoring within sheduling heuristic
- Sheduling heuristic now empty underfilled routes to reaffect [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Improve unreachable detection performances [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Avoid heuristic selection when unncessary [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Shipments are now tolerated within split_clustering if the pickup or the delivery is located at a depot [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- Reduce clustering default restarts from 50 to 10 [#49](https://github.com/Mapotempo/optimizer-api/pull/49)
- Replace balanced_kmeans by balanced_vrp_clustering gem [#49](https://github.com/Mapotempo/optimizer-api/pull/49)
- Factorize get operation status codes [#52](https://github.com/Mapotempo/optimizer-api/pull/52)
- VROOM is no more refused due to initial routes [#59](https://github.com/Mapotempo/optimizer-api/pull/59)
- Improved kill of jobs within scheduling heuristic [#57](https://github.com/Mapotempo/optimizer-api/pull/57)
- CSV is now only returned for completed jobs [#60](https://github.com/Mapotempo/optimizer-api/pull/60)
- Update fronts accordingly to CSV edits [#61](https://github.com/Mapotempo/optimizer-api/pull/61)
- Ensure matrix, matrix_id and matrix_index consistency [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Dump filtered problems [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Default multi_trips value is 1 [#47](https://github.com/Mapotempo/optimizer-api/pull/47)
- Bump VROOM to v1.5.0 [#66](https://github.com/Mapotempo/optimizer-api/pull/66)
- Reduce memory usage within scheduling heuristic [#71](https://github.com/Mapotempo/optimizer-api/pull/71)
- Reduce OR-Tools computation time within scheduling heuristic [#78](https://github.com/Mapotempo/optimizer-api/pull/78)
- Route referents [#89](https://github.com/Mapotempo/optimizer-api/pull/89)
- Bump Ruby to 2.5.5 [#97](https://github.com/Mapotempo/optimizer-api/pull/97)
- Delegate quantity rounding to optimizer-ortools [#98](https://github.com/Mapotempo/optimizer-api/pull/98)
- Improve Force start & breaks through optimizer-ortools [#98](https://github.com/Mapotempo/optimizer-api/pull/98)

### Removed

- solver_parameter from the model
- OR-Tools logs within sheduling heuristic [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Relation id [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Vehicle sort by day index [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- overall_duration parameter from API as it is not functional [#46](https://github.com/Mapotempo/optimizer-api/pull/46)

### Fixed

- Resolution time when using split_independent or max_split procedures
- Alternative activities with empties and fills
- Unreachable points detection
- Shift computation for sheduling problems
- Sheduling heuristic now rejects shipments and rests [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Reject empty problems [#35](https://github.com/Mapotempo/optimizer-api/pull/35)
- Negative time limits [#35](https://github.com/Mapotempo/optimizer-api/pull/35)
- Expand multi_trips only once [#36](https://github.com/Mapotempo/optimizer-api/pull/36)
- Remove data from already started jobs [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Clean interrupted working jobs at startup [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Error when delete operation is invoked immedialty after get [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Coerce first_solution_strategy into array [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Avoid unecessary route generation [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- Correclty handle consecutive delete operations [#52](https://github.com/Mapotempo/optimizer-api/pull/52)
- Solution returned from cache [#53](https://github.com/Mapotempo/optimizer-api/pull/53)
- Returned http error codes [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Check distance method to separate time and distance logics [#65](https://github.com/Mapotempo/optimizer-api/pull/65)
- Split by skills was generating unexpected sub-problems [#47](https://github.com/Mapotempo/optimizer-api/pull/47)
- Remove duplicated empty routes for the same vehicle [#50](https://github.com/Mapotempo/optimizer-api/pull/50)
- Infinite loop due to impossible split within dicho [#67](https://github.com/Mapotempo/optimizer-api/pull/67)
- Avoid depot duplication [#72](https://github.com/Mapotempo/optimizer-api/pull/72)
- Wrong number of visits [#86](https://github.com/Mapotempo/optimizer-api/pull/86)
- Protobuf needs binarymode [#87](https://github.com/Mapotempo/optimizer-api/pull/87)
- Rewind protobuf output before decode [#87](https://github.com/Mapotempo/optimizer-api/pull/87)
- Parse the last solution provided by optimizer-ortools only once [#87](https://github.com/Mapotempo/optimizer-api/pull/87)
- Uniformize wrappers output accordingly to API documentation [#83](https://github.com/Mapotempo/optimizer-api/pull/83)

### Deprecated

- Positions are no longer relations
- Route indice is now index [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
