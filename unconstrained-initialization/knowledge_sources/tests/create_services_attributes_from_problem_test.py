from unittest.mock import Mock, patch
import pytest
import copy

from knowledge_sources.create_services_attributes_from_problem import CreateServicesAttributesFromProblem

problem =  { "services": [
                {'duration': 20,
                'priority': 4,
                'vehicleIndices': [0],
                'matrixIndex': 2,
                'id': '470d440f',
                'exclusionCost': -1.0,
                'pointId': '470d440f-047b-460b-8a9c-fa1efa8b1595',
                'timeWindows': [],
                'quantities': [],
                'setupDuration': 0,
                'lateMultiplier': 0.0,
                'setupQuantities': [],
                'additionalValue': 0,
                'refillQuantities': [],
                'problemIndex': 0,
                'alternativeIndex': 0},
                {'duration': 20,
                'priority': 4,
                'vehicleIndices': [0],
                'matrixIndex': 2,
                'id': '470d440g',
                'exclusionCost': -1.0,
                'pointId': '470d440f-047b-460b-8a9c-fa1efa8b1595',
                'timeWindows': [],
                'quantities': [],
                'setupDuration': 0,
                'lateMultiplier': 0.0,
                'setupQuantities': [],
                'additionalValue': 0,
                'refillQuantities': [],
                'problemIndex': 0,
                'alternativeIndex': 0}
            ]
            }

def test_no_problem():
    blackboard = Mock(problem = problem)

    knowledge_source = CreateServicesAttributesFromProblem(blackboard)

    assert knowledge_source.verify() == True

def test_verify_missing_TW_on_service():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["services"][1]['timeWindows']
    print(blackboard.problem["services"][1])
    knowledge_source = CreateServicesAttributesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()

def test_verify_missing_matrixIndex_on_service():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["services"][1]['matrixIndex']
    knowledge_source = CreateServicesAttributesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()

def test_verify_missing_id_on_service():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["services"][1]['id']
    knowledge_source = CreateServicesAttributesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()
