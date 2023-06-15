from unittest.mock import Mock, patch
import pytest
import copy

from knowledge_sources.create_dictionnary_index_to_id import CreateDictionnaryIndexId


problem =  { "services": [
                {'id': "service_1"},
                {'id': "service_2"},
                {'id': "service_3"},
            ]
            }

def test_verify_missing_id_on_service():
    blackboard = Mock(problem = copy.deepcopy(problem))
    del blackboard.problem["services"][1]['id']
    knowledge_source = CreateDictionnaryIndexId(blackboard)

    with pytest.raises(AttributeError):
        knowledge_source.verify()

def test_process():
    blackboard = Mock(problem = copy.deepcopy(problem))
    knowledge_source = CreateDictionnaryIndexId(blackboard)

    knowledge_source.process()

    assert blackboard.service_index_to_id == { 0 : "service_1", 1 : "service_2", 2 : "service_3"}
