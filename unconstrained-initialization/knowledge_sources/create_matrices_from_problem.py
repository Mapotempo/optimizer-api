#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
import math
import numpy


class CreateMatricesFromProblem(AbstractKnowledgeSource):
    """
    Create Matrices from problem
    """

    def verify(self):

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to create matrices")
        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create matrices")

        return True

    def process(self):
            # # Build Matrices :
        time_matrices     = []
        distance_matrices = []
        vehicle_index     = 0
        for matrice in self.blackboard.problem['matrices']:
            vehicle = self.blackboard.problem['vehicles'][vehicle_index]
            time_matrix = []
            time_matrix_size = int(math.sqrt(len(matrice['time'])))
            timeToWarehouse =[]
            timeToWarehouse.append(matrice['time'][vehicle['endIndex'] * time_matrix_size + vehicle['endIndex']])
            for service in self.blackboard.problem['services']:
                timeToWarehouse.append(matrice['time'][vehicle['startIndex'] * time_matrix_size + service['matrixIndex'] ])
            time_matrix.append(timeToWarehouse)
            for serviceFrom in self.blackboard.problem['services']:
                # print(serviceFrom)
                matrix_row = []
                matrix_row.append(matrice['time'][ serviceFrom['matrixIndex']* time_matrix_size + vehicle['endIndex'] ])
                for serviceTo in self.blackboard.problem['services']:
                    matrix_row.append(matrice['time'][serviceFrom['matrixIndex'] * time_matrix_size + serviceTo['matrixIndex']])
                time_matrix.append(matrix_row)
            time_matrices.append(time_matrix)
            vehicle_index += 1

        vehicle_index = 0
        for matrice in self.blackboard.problem['matrices']:
            vehicle = self.blackboard.problem['vehicles'][vehicle_index]
            distance_matrix = []
            distance_matrix_size = int(math.sqrt(len(matrice['distance'])))
            distanceToWarehouse =[]
            distanceToWarehouse.append(matrice['distance'][vehicle['endIndex'] * distance_matrix_size + vehicle['endIndex']])
            for service in self.blackboard.problem['services']:
                distanceToWarehouse.append(matrice['distance'][vehicle['startIndex'] * distance_matrix_size + service['matrixIndex'] ])
            distance_matrix.append(distanceToWarehouse)
            for serviceFrom in self.blackboard.problem['services']:
                # print(serviceFrom)
                matrix_row = []
                matrix_row.append(matrice['distance'][ serviceFrom['matrixIndex']* distance_matrix_size + vehicle['endIndex'] ])
                for serviceTo in self.blackboard.problem['services']:
                    matrix_row.append(matrice['distance'][serviceFrom['matrixIndex'] * distance_matrix_size + serviceTo['matrixIndex']])
                distance_matrix.append(matrix_row)
            distance_matrices.append(distance_matrix)
            vehicle_index += 1


        # Matrices
        self.blackboard.distance_matrices   = numpy.array(distance_matrices, dtype=numpy.float64)
        self.blackboard.time_matrices       = numpy.array(time_matrices, dtype=numpy.float64)
