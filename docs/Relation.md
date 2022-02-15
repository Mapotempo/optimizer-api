Relations allow to define constraints explicitly between activities and/or vehicles.
Those could be of the following types:
  * **same_route** : force missions to be served within the same route.
  * **order** : force services to be served within the same route in a specific order, but allow to insert others missions between
  * **sequence** : force services to be served in a specific order, excluding others missions to be performed between
  * **meetup** : ensure that some missions are performed at the same time by multiple vehicles.
  * **maximum_duration_lapse** : Define a maximum in route duration between two activities.
  * **minimum_day_lapse** : Define a minimum number of unworked days between two worked days. For instance, if you what one visit per week, you should use a minimum lapse of 7.
  If the first service is assigned on a Monday then, with this minimum lapse, the solver will try to keep all these service\'s visits on Mondays.
  * **maximum_day_lapse** : Define a maximum number of unworked days between two worked days.
  * **vehicle_group_duration** : The sum of linked vehicles duration should not exceed lapse over whole period.
Some relations need to be extended over all period. Parameter **periodicity** allows to express recurrence of the relation over the period.

```json
  "relations": [{
    "id": "sequence_1",
    "type": "sequence",
    "linked_ids": ["service_1", "service_3", "service_2"],
    "lapse": null
  }, {
    "id": "group_duration",
    "type": "vehicle_group_duration",
    "linked_vehicle_ids": ["vehicle_1", "vehicle_2"],
    "lapse": 3
  }, {
    "id": "group_duration",
    "type": "vehicle_group_duration_on_weeks",
    "linked_vehicle_ids": ["vehicle_1", "vehicle_2"],
    "lapse": 3,
    "periodicity": 2
  }]
```

### Vehicle trips relation
Vehicles can be linked by _vehicle_trips_ relation : second vehicle of the relation can not start driving before first one came back to depot. This has some implications : 
- There should be an intermediate depot between two tours. That is, tour1 needs at least and end_point_id and tour2 needs at least one start_point_id. Those point_ids should be equal. This is to avoid teleportation.
- Every vehicle of one _vehicle_trips_ relation should be available at same days. Time-windows can be different from one tour to the other, but tour1 can not start after tour2 start. 
