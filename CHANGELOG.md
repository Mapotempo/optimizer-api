# Changelog

## [v1.9.0-dev] - Unreleased

### Added

- Allow to compute geojsons for synchronous resolutions [#356](https://github.com/Mapotempo/optimizer-api/pull/356/files)

### Changed

- Geojson object colors are now related to vehicle partition if defined [#338](https://github.com/Mapotempo/optimizer-api/pull/338)
- The time horizon has been changed in optimizer-ortools which increases the performances in case of timewindows without end [#341](https://github.com/Mapotempo/optimizer-api/pull/341)
- Partition field `method` is renamed as `technique` [#321](https://github.com/Mapotempo/optimizer-api/pull/321)
- The resolution method called through `cluster_threshold` now use VROOM instead of `sim_annealing` gem [#321](https://github.com/Mapotempo/optimizer-api/pull/321)
- Reduce consequently the time to separate independent vrps.This change reduces also the memory usage. [#321](https://github.com/Mapotempo/optimizer-api/pull/321)
- The internal solution object now use a single model for all the resolution methods. This improve the consistency and the completness of the solutions returned. [#321](https://github.com/Mapotempo/optimizer-api/pull/321)

### Removed

- The unused field `type` is removed in input [#321](https://github.com/Mapotempo/optimizer-api/pull/321)

### Fixed

- Fix find_best_heuristic selection logic [#337](https://github.com/Mapotempo/optimizer-api/pull/337)

## [v1.8.2] - 2022-01-19

### Added

- Timewindow violation ("lateness") can now be limited using the `maximum_lateness` field of timewindows (not yet available for periodic heuristic). By default, `maximum_lateness` is set to be 100% of the timewindow -- i.e., `end` - `start`. The default value can be overridden via the environment variable `OPTIM_DEFAULT_MAX_LATENESS_RATIO`. [#303](https://github.com/Mapotempo/optimizer-api/pull/303)

### Changed

- Alternative activities are now available using shipment relations [#302](https://github.com/Mapotempo/optimizer-api/pull/302)
- The `entity` field is now mandatory for a `partition` [#332](https://github.com/Mapotempo/optimizer-api/pull/332)

### Removed

- Unused assemble heuristic [#314](https://github.com/Mapotempo/optimizer-api/pull/314)

### Fixed

- Polylines geometries were disabled. They can now be returned if the `OPTIM_GENERATE_GEOJSON_POLYLINES` environment variable is present. [#297](https://github.com/Mapotempo/optimizer-api/pull/297)
- Correctly handles shipments with empty quantities with VROOM [#300](https://github.com/Mapotempo/optimizer-api/pull/300)
- In some cases dicho was unable to find the correct matrices for the sub-problems [#299](https://github.com/Mapotempo/optimizer-api/pull/299)

## [v1.8.1] - 2021-12-08

### Added

- Each api key may now have its own router api key [#287](https://github.com/Mapotempo/optimizer-api/pull/287)

### Changed

- Avoid unnecessary repetition if solution contains no unassigned mission [#296](https://github.com/Mapotempo/optimizer-api/pull/296)

### Fixed

- The complex shipments now correctly handles vrp with routes [#294](https://github.com/Mapotempo/optimizer-api/pull/294)
- In some cases, the partitioning phase was trying to cluster empty vrps [#296](https://github.com/Mapotempo/optimizer-api/pull/296)
- Correctly handles timewindows out of range for periodic problems

## [v1.8.0] - 2021-09-29

### Added

- Support skills in periodic heuristic (`first_solution_strategy='periodic'`) [#194](https://github.com/Mapotempo/optimizer-api/pull/194)
- Implementation of `vehicle_trips` relation: the routes can be successive or with a minimum duration `lapse` in between [#123](https://github.com/Mapotempo/optimizer-api/pull/123)
- CSV headers adapts to the language provided through HTTP_ACCEPT_LANGUAGE header to facilitate import in Mapotempo-Web [#196](https://github.com/Mapotempo/optimizer-api/pull/196)
- Return route day/date and visits' index in result [#196](https://github.com/Mapotempo/optimizer-api/pull/196)
- Treat complex shipments (multi-pickup-single-delivery and single-pickup-multi-delivery) as multiple simple shipments internally to increase performance [#261](https://github.com/Mapotempo/optimizer-api/pull/261)
- Prioritize the vehicles (and trips of `vehicle_trips` relation) via modifying the fixed costs so that first vehicles (and trips) are preferred over the latter ones [#266](https://github.com/Mapotempo/optimizer-api/pull/266)
- Document return codes [#224](https://github.com/Mapotempo/optimizer-api/pull/224)
- OR-Tools wrapper can use `initial` capacity value [#245](https://github.com/Mapotempo/optimizer-api/pull/245)

### Changed

- Improve cases where a service has two visits in periodic heuristic: ensure that the second visit can be assigned to the right day [#227](https://github.com/Mapotempo/optimizer-api/pull/227)
- Relation `lapse` becomes `lapses` : we can now provide a specific lapse for every consecutive ID in the relation [#265](https://github.com/Mapotempo/optimizer-api/pull/265)

### Removed

- Field `trips` in vehicle model. Use `vehicle_trips` relation instead [#123](https://github.com/Mapotempo/optimizer-api/pull/123)

### Fixed

- VROOM was used incorrectly in various cases: negative quantities, vehicle duration, activity position [#223](https://github.com/Mapotempo/optimizer-api/pull/223) [#242](https://github.com/Mapotempo/optimizer-api/pull/242)
- Capacity violation in periodic heuristic algorithm (`first_solution_strategy='periodic'`) [#227](https://github.com/Mapotempo/optimizer-api/pull/227)
- Service timewindows without an `end` were not respected [#262](https://github.com/Mapotempo/optimizer-api/pull/262)
- `total_time`, `total_travel_time` and related values are correctly calculated [#237](https://github.com/Mapotempo/optimizer-api/pull/237)

## [v1.7.1] - 2021-05-20

### Added

- Remove simple pauses before optimization and reinsert them back into the solution to increase solver performance [#211](https://github.com/Mapotempo/optimizer-api/pull/211)

## [v1.7.0] - 2021-05-03

### Added

- Corresponding vehicle_id is returned within each service's skills if problem is partitioned with vehicle entity [#110](https://github.com/Mapotempo/optimizer-api/pull/110)
- Support initial routes and skills in split_solve (`max_split_size`) algorithm [#140](https://github.com/Mapotempo/optimizer-api/pull/140)
- Support relations (`order`, `same_route`, `sequence`, `shipment`) in split_solve algorithm (`max_split_size`) and partitions (`[:configuration][:preprocessing][:partitions]`) [#145](https://github.com/Mapotempo/optimizer-api/pull/145)
- split_solve algorithm (`max_split_size`) respects relations (`vehicle_trips`, `meetup`, `minimum_duration_lapse`, `maximum_duration_lapse`, `minimum_day_lapse`, `maximum_day_lapse`) [#145](https://github.com/Mapotempo/optimizer-api/pull/145)
- Return `geojsons` structure according to `geometry` parameter [#165](https://github.com/Mapotempo/optimizer-api/pull/165)

### Changed

- Bump grape to v1.5.0 - It speeds up the processing of POST requests for nested problems (up to 20 times faster, https://github.com/ruby-grape/grape/pull/2096) [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Bump grape-swagger to v1.3.0 - The documentation is now correctly generated. It allows SDK generation. [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- The fields `costs` introduced in v0.1.5 is renamed `cost_details` to avoid confusion with field `cost` [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Bump VROOM to v1.8.0 and start using the features integrated since v1.3.0 [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Bump OR-Tools v7.8 [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- VROOM were previously always called synchronously, it is now reserved to a set of effective `router_mode` (:car, :truck_medium) within a limit of points (<200). [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Heuristic selection (`first_solution_strategy='self_selection'`) takes into account the supplied initial routes (`routes`) and the best solution is used as the initial route [#159](https://github.com/Mapotempo/optimizer-api/pull/159)

### Removed

- `geometry_polyline` parameter now be provided through `geometry` parameter [#165](https://github.com/Mapotempo/optimizer-api/pull/165)

### Fixed

- `unassigned` output were in some cases returning the key `shipment_id` instead of `pickup_shipment_id` and `delivery_shipment_id` [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Uniformize route content and always return `original_vehicle_id` [#107](https://github.com/Mapotempo/optimizer-api/pull/107)
- Infeasibility detection of services with negative quantity [#111](https://github.com/Mapotempo/optimizer-api/pull/111)
- Correctly display when an error occurs in `scheduling` page [#207](https://github.com/Mapotempo/optimizer-api/pull/207)


## [v1.6.0] - 2021-02-10

### Added

- Allow support for semicolumn and tabulation in CSV files
- Initial routes are now correctly grouped when using partitions (Especially for Scheduling Problems). However, this feature is still under development within split based algorithms (`split_solve` and `dichotomous`)
- `position` field for activities
- Unfeasible missions are removed from routes [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Detailed route costs both for routes and solutions [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- [WIP] Allow multidepot within clustering. For now, this only influences clusters initialization [#56](https://github.com/Mapotempo/optimizer-api/pull/56)
- Introduce direct shipments: pickup and delivery must be consecutive [#51](https://github.com/Mapotempo/optimizer-api/pull/51)
- Return original ids for missions and vehicles [#73](https://github.com/Mapotempo/optimizer-api/pull/73)
- Return `total_waiting_time` [#83](https://github.com/Mapotempo/optimizer-api/pull/83)
- Introduce `minimize_days_worked` parameter for scheduling heuristic. The default behavior of scheduling heuristic is now to balance work load over the period, the introduced parameter allows to return to the previous behavior [#89](https://github.com/Mapotempo/optimizer-api/pull/89)
- Detect inconsistent `same_point_day` definition [#76](https://github.com/Mapotempo/optimizer-api/pull/76)

### Changed

- Cache is now part of wrappers hash
- Collect current distance from OR-Tools
- Refactoring of the chaining of the various solving procedures (Rework `define_process`)
- Now use OR-Tools asserts instead or recompiling the entire project
- Reject too small lapses
- Bump OR-Tools to v7.8
- Various edits, improvements and refactoring within scheduling heuristic
- Scheduling heuristic now empties under-filled routes to reassign them [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Improve unfeasible service detection performance [#28](https://github.com/Mapotempo/optimizer-api/pull/28) [#65](https://github.com/Mapotempo/optimizer-api/pull/65)
- Avoid heuristic selection when unnecessary [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Shipments are now tolerated within `split_clustering` if the pickup or the delivery is located at a depot [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- Reduce clustering default restarts from 50 to 10 [#49](https://github.com/Mapotempo/optimizer-api/pull/49)
- Replace `balanced_kmeans` by `balanced_vrp_clustering` gem [#49](https://github.com/Mapotempo/optimizer-api/pull/49)
- Factorize get operation status codes [#52](https://github.com/Mapotempo/optimizer-api/pull/52)
- VROOM is no more refused due to initial routes [#59](https://github.com/Mapotempo/optimizer-api/pull/59)
- Improved kill of jobs within scheduling heuristic [#57](https://github.com/Mapotempo/optimizer-api/pull/57)
- CSV is now only returned for completed jobs [#60](https://github.com/Mapotempo/optimizer-api/pull/60)
- Update fronts accordingly to CSV edits [#61](https://github.com/Mapotempo/optimizer-api/pull/61)
- Ensure matrix, matrix_id and matrix_index consistency [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Dump filtered problems [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Default `multi_trips` value is now 1 [#47](https://github.com/Mapotempo/optimizer-api/pull/47)
- Bump VROOM to v1.5.0 [#66](https://github.com/Mapotempo/optimizer-api/pull/66)
- Reduce memory usage for scheduling problems [#71](https://github.com/Mapotempo/optimizer-api/pull/71)
- Reduce OR-Tools computation time within scheduling heuristic [#78](https://github.com/Mapotempo/optimizer-api/pull/78)
- Rework route referents definition within scheduling heuristic, in order to improve routes initialization [#89](https://github.com/Mapotempo/optimizer-api/pull/89)
- Bump Ruby to 2.5.5 [#97](https://github.com/Mapotempo/optimizer-api/pull/97)
- Delegate quantity rounding to optimizer-ortools [#98](https://github.com/Mapotempo/optimizer-api/pull/98)
- Improve Force start & breaks through optimizer-ortools [#98](https://github.com/Mapotempo/optimizer-api/pull/98)

### Removed

- `solver_parameter` from the internal model, it is replaced by `solver` and `first_solution_strategy` parameters
- Relation `id` was mandatory, but was never used or returned [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- Vehicle sort by day index [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
- `overall_duration` parameter from API as it is not functional [#46](https://github.com/Mapotempo/optimizer-api/pull/46)

### Fixed

- Resolution time when using split_independent or max_split procedures
- Alternative activities with empties and fills
- Shift computation for sheduling problems
- Sheduling heuristic now rejects shipments and rests [#28](https://github.com/Mapotempo/optimizer-api/pull/28)
- Reject empty problems [#35](https://github.com/Mapotempo/optimizer-api/pull/35)
- Negative time limits [#35](https://github.com/Mapotempo/optimizer-api/pull/35)
- Expand multi_trips only once [#36](https://github.com/Mapotempo/optimizer-api/pull/36)
- Remove data from already started jobs [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Clean interrupted working jobs at startup [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Error when delete operation is invoked immedialty after get [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Coerce `first_solution_strategy` into array [#38](https://github.com/Mapotempo/optimizer-api/pull/38)
- Avoid unnecessary route generation [#46](https://github.com/Mapotempo/optimizer-api/pull/46)
- Correctly handle consecutive delete operations [#52](https://github.com/Mapotempo/optimizer-api/pull/52)
- Returned http error codes [#62](https://github.com/Mapotempo/optimizer-api/pull/62)
- Split by skills generating unexpected sub-problems [#47](https://github.com/Mapotempo/optimizer-api/pull/47)
- Remove duplicated empty routes for the same vehicle [#50](https://github.com/Mapotempo/optimizer-api/pull/50)
- Return `total_time` and `total_travel_distance` from scheduling heuristic [#63](https://github.com/Mapotempo/optimizer-api/pull/63)
- Infinite loop due to impossible split within `dichotomous` [#67](https://github.com/Mapotempo/optimizer-api/pull/67)
- Avoid depot duplication [#72](https://github.com/Mapotempo/optimizer-api/pull/72)
- Wrong number of visits [#86](https://github.com/Mapotempo/optimizer-api/pull/86)
- Parsing of intermediate protobuf file returned by optimizer-ortools [#87](https://github.com/Mapotempo/optimizer-api/pull/87)
- Uniformize wrappers output accordingly to API documentation [#83](https://github.com/Mapotempo/optimizer-api/pull/83)

### Deprecated

- Positions are no longer relations and must be defined at activity level
- Route `indice` is now `index` [#31](https://github.com/Mapotempo/optimizer-api/pull/31)
