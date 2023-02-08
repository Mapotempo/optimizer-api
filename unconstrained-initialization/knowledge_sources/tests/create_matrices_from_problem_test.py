from unittest.mock import Mock, patch
import pytest

from knowledge_sources.create_matrices_from_problem import CreateMatricesFromProblem
import schema
import numpy

@pytest.mark.parametrize("problem", [None, "Coucou"])
def test_verify_problem_error(problem):
    blackboard = Mock(problem = problem)
    knowledge_source = CreateMatricesFromProblem(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()


def test_verify_problem_missing_keys():
    blackboard = Mock(problem = {})
    knowledge_source = CreateMatricesFromProblem(blackboard)

    with pytest.raises(schema.SchemaError):
        knowledge_source.verify()


problem = {
    "matrices" : [{
        "time":[0,2,3,
                4,0,6,
                7,8,0],
        "distance":[1,2,3,
                    4,5,6,
                    7,8,9]
    }],
    "vehicles" : [{
        'endIndex': 0,
        'startIndex': 0,
    },
    {
        'endIndex': 0,
        'startIndex': 0,
    }],
    "services" : [
        {
            'matrixIndex':1,
        },
        {
            'matrixIndex':2,
        }
    ]
}

def test_verify_problem_ok():
    blackboard = Mock(problem = problem)
    knowledge_source = CreateMatricesFromProblem(blackboard)

    assert knowledge_source.verify() == True


def test_process():
    blackboard = Mock(problem = problem)
    knowledge_source = CreateMatricesFromProblem(blackboard)

    knowledge_source.process()
    # assert (blackboard.distance_matrices == numpy.array([[[5,3,1,1],[5,6,7],[8,9,10]]], dtype=numpy.float64)).all()
    assert (blackboard.time_matrices == numpy.array([[[0, 6, 4], [8, 0, 7], [2, 3, 0]]], dtype=numpy.float64)).all()
