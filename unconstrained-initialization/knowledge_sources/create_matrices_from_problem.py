#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import math
import numpy
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
        time_matrices       = []
        distance_matrices   = []

        for matrice in self.blackboard.problem['matrices']:
            time_matrix = []
            matrix_size = int(math.sqrt(len(matrice['time'])))
            for pointFrom in range(matrix_size):
                matrix_row = []
                for pointTo in range(matrix_size):
                    matrix_row.append(matrice["time"][pointFrom * matrix_size + pointTo])
                time_matrix.append(matrix_row)
            time_matrices.append(time_matrix)

            distance_matrix = []
            matrix_size = int(math.sqrt(len(matrice['distance'])))
            for pointFrom in range(matrix_size):
                matrix_row = []
                for pointTo in range(matrix_size):
                    matrix_row.append(matrice['distance'][pointFrom * matrix_size + pointTo])
                distance_matrix.append(matrix_row)
            distance_matrices.append(distance_matrix)

        # Matrices
        self.blackboard.distance_matrices   = numpy.array(distance_matrices, dtype=numpy.float64)
        self.blackboard.time_matrices       = numpy.array(time_matrices, dtype=numpy.float64)
