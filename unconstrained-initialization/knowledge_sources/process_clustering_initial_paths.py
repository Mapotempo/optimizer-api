#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
from sklearn.cluster import AgglomerativeClustering
import numpy

class ProcessClusteringInitialPaths(AbstractKnowledgeSource):
    """
    Create all vehicles attributes from problem
    """

    def verify(self):

        if self.blackboard.num_vehicle is None:
            raise AttributeError("num_vehicle not specified can't initilaize paths")

        if self.blackboard.time_matrices is None:
            raise AttributeError("No distance matrix can't initialize paths")

        if self.blackboard.time_matrices[0].shape[0] != self.blackboard.time_matrices[0].shape[1]:
            raise AttributeError("time_matrices must be a square matrices")

        return True

    def process(self):

        log.info("Process Initial Solution")
        log.debug("-- Clustering")
        num_vehicle = self.blackboard.num_vehicle
        # recalculate matrix for AgglomerativeClustering
        # TODO : use custom metric 'precomputed'

        matrix = []

        time_matrix = self.blackboard.problem["matrices"][0]["time"]
        matrix_size = self.blackboard.problem["matrices"][0]["size"]
        problem     = self.blackboard.problem

        routes = problem.get("routes", [])

        log.info(f" routes : {routes}")
        log.info(f"vehicle_id_index {self.blackboard.vehicle_id_index}")

        if len(routes) > 0:
            service_id_to_index = {value: key for key, value in self.blackboard.service_index_to_id.items()}
            self.blackboard.unassigned_services = numpy.full(self.blackboard.num_services + 1, -1, dtype=numpy.int32)
            self.blackboard.paths = numpy.full((num_vehicle, self.blackboard.num_services + 1), -1, dtype=numpy.int32)
            for route in routes:
                vehicle_id = route.get("vehicleId")
                vehicle_index = self.blackboard.vehicle_id_index[vehicle_id]
                for service_index_in_route, service_id in enumerate(route.get("serviceIds")):
                    service_index = service_id_to_index[service_id]
                    self.blackboard.paths[vehicle_index, service_index_in_route] = service_index
            for service_index in range (self.blackboard.num_services):
                if not numpy.any(numpy.isin(self.blackboard.paths, service_index)):
                    self.blackboard.unassigned_services[service_index] = service_index
            mask = self.blackboard.unassigned_services == -1

            self.blackboard.unassigned_services = numpy.concatenate((self.blackboard.unassigned_services[~mask], self.blackboard.unassigned_services[mask]))


        else :
            self.blackboard.unassigned_services = numpy.full(self.blackboard.num_services + 1, -1, dtype=numpy.int32)
            for serviceFrom in problem["services"]:
                matrix_row = []
                for serviceTo in problem["services"]:
                    matrix_row.append(time_matrix[serviceFrom["matrixIndex"] * matrix_size + serviceTo["matrixIndex"]])
                matrix.append(matrix_row)

            matrix = numpy.array(matrix)

            cluster = AgglomerativeClustering(n_clusters=min(num_vehicle, matrix.shape[0]), metric='precomputed', linkage='complete').fit(matrix)
            log.debug("-- Compute initial solution")
            num_services = numpy.zeros(num_vehicle, dtype=int)
            for i in range(0, cluster.labels_.size):
                vehicle = cluster.labels_[i]
                num_services[vehicle] += 1

            max_capacity = numpy.max(num_services) + 10 #Add margin to let algorithm the possibility to optimize something
            num_services = numpy.zeros(num_vehicle, dtype=int)
            self.blackboard.paths = numpy.full((num_vehicle, self.blackboard.num_services + 1), -1, dtype=numpy.int32)
            for i in range(0, cluster.labels_.size):
                vehicle = cluster.labels_[i]
                position = num_services[vehicle]
                self.blackboard.paths[vehicle][position] = i
                num_services[vehicle] += 1

            reverse_services_dict = {}
            for index, service_id in self.blackboard.service_index_to_id.items():
                reverse_services_dict[service_id] = index

            for rest in self.blackboard.rests:
                vehicle = rest[1]
                index = reverse_services_dict[rest[0].get("id")]
                self.blackboard.paths[vehicle][num_services[vehicle]] = index
                num_services[vehicle] += 1
