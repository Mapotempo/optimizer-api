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
            # # Build Matrices : for each matrix (and each type of matrix : time and distance) we need the number of differents starting and ending warehouses,
            # # and we compute a matrix of size (nb_services + nb_starting_warehouses) x (nb_services + nb_ending_warehouses)
        time_matrices       = []
        distance_matrices   = []
        initial_start_indices = list(set([vehicle["startIndex"] for vehicle in self.blackboard.problem['vehicles'] ]))
        initial_end_indices = list(set([vehicle["endIndex"] for vehicle in self.blackboard.problem['vehicles'] ]))

        for matrice in self.blackboard.problem['matrices']:
            time_matrix = []
            time_matrix_size = int(math.sqrt(len(matrice['time'])))
            for serviceFrom in self.blackboard.problem['services']:
                matrix_row = []
                for serviceTo in self.blackboard.problem['services']:
                    matrix_row.append(matrice['time'][serviceFrom['matrixIndex'] * time_matrix_size + serviceTo['matrixIndex']])
                time_matrix.append(matrix_row)


            for vehicle_end_index in initial_end_indices:
                for service_index, serviceFrom in enumerate(self.blackboard.problem["services"]):
                    time_matrix[service_index].append(matrice['time'][serviceFrom['matrixIndex'] * time_matrix_size + vehicle_end_index])
                matrix_row = []
                for serviceTo in self.blackboard.problem["services"]:
                    matrix_row.append(matrice['time'][vehicle_end_index * time_matrix_size + serviceTo['matrixIndex']])
                for vehicle_start_index in initial_start_indices:
                    matrix_row.append(matrice['time'][vehicle_end_index * time_matrix_size + vehicle_start_index])
                time_matrix.append(matrix_row)
            time_matrices.append(time_matrix)

            distance_matrix = []
            distance_matrix_size = int(math.sqrt(len(matrice['distance'])))
            for serviceFrom in self.blackboard.problem['services']:
                matrix_row = []
                for serviceTo in self.blackboard.problem['services']:
                    matrix_row.append(matrice['distance'][serviceFrom['matrixIndex'] * distance_matrix_size + serviceTo['matrixIndex']])
                distance_matrix.append(matrix_row)


            for vehicle_end_index in initial_end_indices:
                for service_index, serviceFrom in enumerate(self.blackboard.problem["services"]):
                    distance_matrix[service_index].append(matrice['distance'][serviceFrom['matrixIndex'] * distance_matrix_size + vehicle_end_index])
                matrix_row = []
                for serviceTo in self.blackboard.problem["services"]:
                    matrix_row.append(matrice['distance'][vehicle_end_index * distance_matrix_size + serviceTo['matrixIndex']])
                for vehicle_start_index in initial_start_indices:
                    matrix_row.append(matrice['distance'][vehicle_end_index * distance_matrix_size + vehicle_start_index])
                distance_matrix.append(matrix_row)
            distance_matrices.append(distance_matrix)

        log.info(f"Taille de la matrice de temps : {len(time_matrices[0])} x {len(time_matrices[0][0])}")
        log.info(f"Taille de la matrice de distance : {len(distance_matrices[0])} x {len(distance_matrices[0][0])}")

        # Matrices
        self.blackboard.distance_matrices   = numpy.array(distance_matrices, dtype=numpy.float64)
        self.blackboard.time_matrices       = numpy.array(time_matrices, dtype=numpy.float64)
