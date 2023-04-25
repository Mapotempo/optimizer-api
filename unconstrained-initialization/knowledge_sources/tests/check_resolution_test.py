from unittest.mock import Mock, patch
import pytest
import copy
from schema import Schema, And, Use, Optional, SchemaError, Or
import pdb

from knowledge_sources.check_resolution import CheckResolution


problem_missing_keys =  { "services": [
                {'id': "service_1"},
                {'id': "service_2"},
                {'id': "service_3"},
            ],
             "vehicles": [

             ],
             "matrices":[]
            }

problem =  { "services": [
                {
                    'id': "service_1",
                    'matrixIndex': 0,

                },
                {
                    'id': "service_2",
                    'matrixIndex': 1,

                }
            ],
             "vehicles": [
                {
                    "matrixIndex": 0,
                    "endIndex": 0,
                    "startIndex": 0,
                }
             ],
             "matrices": [
                {
                    "time": [0,1,1,0],
                    "distance": [0,1,1,0]
                }
             ]
            }

def test_order_relation():
    blackboard = Mock(problem = copy.deepcopy(problem))
    knowledge_source = CheckResolution(blackboard)
    blackboard.problem["relations"] = [
        {
            "type" : "order",
            "linked_ids" : ["1","2"]
        }
    ]

    with pytest.raises(NotImplementedError):
        knowledge_source.verify()

def test_sequence_relation():
    blackboard = Mock(problem = copy.deepcopy(problem))
    knowledge_source = CheckResolution(blackboard)
    blackboard.problem["relations"] = [
        {
            "type" : "sequence",
            "linked_ids" : ["1","2"]
        }
    ]

    with pytest.raises(NotImplementedError):
        knowledge_source.verify()

def test_always_last_position():
    blackboard = Mock(problem = copy.deepcopy(problem))
    knowledge_source = CheckResolution(blackboard)
    activity = {
            "position": "always_last"
          }
    blackboard.problem["services"][0]["activity"] = activity

    with pytest.raises(NotImplementedError):
        knowledge_source.verify()

def test_always_first_position():
    blackboard = Mock(problem = copy.deepcopy(problem))
    knowledge_source = CheckResolution(blackboard)
    activity = {
            "position": "always_first"
          }
    blackboard.problem["services"][0]["activity"] = activity

    with pytest.raises(NotImplementedError):
        knowledge_source.verify()

def test_missing_keys():
    blackboard = Mock(problem = problem_missing_keys)
    knowledge_source = CheckResolution(blackboard)

    with pytest.raises(SchemaError):
        knowledge_source.verify()

def test_ok_for_resolution():
    blackboard = Mock(problem = problem)
    knowledge_source = CheckResolution(blackboard)

    assert knowledge_source.verify()
