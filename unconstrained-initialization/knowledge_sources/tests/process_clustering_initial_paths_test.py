from unittest.mock import Mock, patch, MagicMock
import pytest
import numpy
import copy

from knowledge_sources.process_clustering_initial_paths import ProcessClusteringInitialPaths

def paths_contains(paths, values):

    return (all(x in paths[0] for x in values[0]) and all(x in paths[1] for x in values[1])) or (all(x in paths[1] for x in values[0]) and all(x in paths[0] for x in values[1]))

def test_time_matrix_is_not_square():
    time_matrices = numpy.array([[[1,2],[1,2],[1,2]]])
    blackboard = MagicMock(time_matrices = time_matrices)
    knowledge_source = ProcessClusteringInitialPaths(blackboard)
    with pytest.raises(AttributeError):
        knowledge_source.verify()

def test_matrix_is_none():
    blackboard = Mock(time_matrices = None)
    knowledge_source = ProcessClusteringInitialPaths(blackboard)
    with pytest.raises(AttributeError):
        knowledge_source.verify()

def test_process():
    blackboard = Mock(time_matrices     = numpy.array([[[0,0,5,5,1,1],
                                                        [0,0,5,5,5,1],
                                                        [5,5,0,0,5,1],
                                                        [5,5,0,0,1,1],
                                                        [1,5,1,1,0,1],
                                                        [1,5,1,1,1,0]]]),
                     distance_matrices  = numpy.array([[[0,1,1,1,1,1],
                                                        [1,0,1,5,5,1],
                                                        [1,1,0,5,5,1],
                                                        [1,5,1,0,1,1],
                                                        [1,5,1,1,0,1],
                                                        [1,5,1,1,1,0]]]),
                      vehicle_start_index = [4,5],
                      vehicle_end_index   = [4,5],
                      num_vehicle = 2)
    knowledge_source = ProcessClusteringInitialPaths(blackboard)

    knowledge_source.process()
    assert paths_contains(blackboard.paths, [[0,1],[2,3]])
