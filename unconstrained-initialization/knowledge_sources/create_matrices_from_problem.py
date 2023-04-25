#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import math
import numpy as np
from schema import Use, Const, And, Schema, Or

class CreateMatricesFromProblem(AbstractKnowledgeSource):
    """
    Create Matrices from problem
    """

    def verify(self):

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to create matrices")
        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create matrices")


        problem_schema = Schema(
            {
                "matrices" : [{
                    "time":[Or(float, int)],
                    "distance":[Or(float, int)]
                }],
                "vehicles" : [{
                    'endIndex': int,
                    'startIndex': int,
                }],
                "services" : [
                    {
                        'matrixIndex':int,
                    }
                ]
            },
            ignore_extra_keys=True
        )
        problem_schema.validate(self.blackboard.problem)

        return True

    def process(self):

        matrices = self.blackboard.problem['matrices']
        num_matrices = len(matrices)
        matrix_size = int(math.sqrt(len(matrices[0]['time'])))

        # Create empty 3D arrays for time_matrices and distance_matrices
        time_matrices = np.zeros((num_matrices, matrix_size, matrix_size), dtype=np.float64)
        distance_matrices = np.zeros((num_matrices, matrix_size, matrix_size), dtype=np.float64)

        for matrix_index, matrix in enumerate(matrices):

                # Create and fill time_matrix
                for pointFrom in range(matrix_size):
                    for pointTo in range(matrix_size):
                        time_matrices[matrix_index, pointFrom, pointTo] = matrix["time"][pointFrom * matrix_size + pointTo]

                # Create and fill distance_matrix
                for pointFrom in range(matrix_size):
                    for pointTo in range(matrix_size):
                        distance_matrices[matrix_index, pointFrom, pointTo] = matrix['distance'][pointFrom * matrix_size + pointTo]

        # Matrices
        self.blackboard.distance_matrices = distance_matrices
        self.blackboard.time_matrices = time_matrices
