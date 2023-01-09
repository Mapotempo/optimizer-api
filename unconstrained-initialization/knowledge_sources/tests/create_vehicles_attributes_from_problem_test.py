from unittest.mock import Mock, patch
import pytest
import copy
import numpy

from knowledge_sources.create_vehicles_attributes_from_problem import CreateVehiclesAttributesFromProblem

problem =  { "vehicles":
            [
                {
                    "id" : "1",
                    "costFixed": 1000,
                    "capacities": [
                        {
                            "units" : "kg",
                            "limit" : 100,
                            "overloadMultiplier" : 100
                        }
                    ],
                    "costDistanceMultiplier":1,
                    "costTimeMultiplier":1,
                    "timeWindow": {
                        "start":0,
                        "end" : 900,
                        "maximumLateness": 100
                    },
                    "distance": 1000
                },
                {
                    "id" : "2",
                    "costFixed": 1000,
                    "capacities": [
                        {
                            "units" : "kg",
                            "limit" : 100,
                            "overloadMultiplier" : 100
                        }
                    ],
                    "costDistanceMultiplier":1,
                    "costTimeMultiplier":1,
                    "timeWindow": {
                        "start":0,
                        "end" : 900,
                        "maximumLateness": 10
                    },
                    "distance" : 1000
                }
            ],
            "relations" : [{
                "type": "vehicle_trips",
                "linkedVehicleIds": ["1", "2"]
                }
            ]
        }

def test_arrays():
    blackboard = Mock(problem = copy.deepcopy(problem))

    knowledge_source = CreateVehiclesAttributesFromProblem(blackboard)

    knowledge_source.process()

    assert (blackboard.vehicles_distance_max        ==  numpy.array([ 1000., 1000.])).all()
    assert (blackboard.cost_time_multiplier         ==  numpy.array([ 1., 1.])).all()
    assert (blackboard.cost_distance_multiplier     ==  numpy.array([ 1., 1.])).all()
    assert (blackboard.vehicle_capacity             ==  numpy.array([ 100., 100.])).all()
    assert (blackboard.vehicles_TW_starts           ==  numpy.array([ 0., 0.])).all()
    assert (blackboard.vehicles_TW_ends             ==  numpy.array([ 1000., 910.])).all()
    assert (blackboard.previous_vehicle             ==  numpy.array([ -1., 0.])).all()
    assert (blackboard.vehicles_overload_multiplier ==  numpy.array([ 100., 100.])).all()

def test_no_attributes_second_vehicles():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["vehicles"][1]['distance']
    del blackboard.problem["vehicles"][1]['costTimeMultiplier']
    del blackboard.problem["vehicles"][1]['costDistanceMultiplier']
    del blackboard.problem["vehicles"][1]['capacities']
    del blackboard.problem["vehicles"][0]['capacities'][0]['overloadMultiplier']

    knowledge_source = CreateVehiclesAttributesFromProblem(blackboard)

    knowledge_source.process()

    assert (blackboard.vehicles_distance_max        ==  numpy.array([ 1000., -1.])).all()
    assert (blackboard.cost_time_multiplier         ==  numpy.array([ 1., 0.])).all()
    assert (blackboard.cost_distance_multiplier     ==  numpy.array([ 1., 0.])).all()
    assert (blackboard.vehicle_capacity             ==  numpy.array([ 100., -1.])).all()
    assert (blackboard.vehicles_overload_multiplier ==  numpy.array([ 0., 0.])).all()



def test_no_id():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["vehicles"][1]['id']

    knowledge_source = CreateVehiclesAttributesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()


def test_no_vehicle():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["vehicles"]

    knowledge_source = CreateVehiclesAttributesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()


def test_no_multitour():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["relations"]

    knowledge_source = CreateVehiclesAttributesFromProblem(blackboard)

    knowledge_source.process()
    print(blackboard.previous_vehicle)
    assert (blackboard.previous_vehicle ==  numpy.array([-1.,-1.])).all()
