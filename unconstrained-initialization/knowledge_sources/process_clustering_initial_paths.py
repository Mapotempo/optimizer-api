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

        if self.blackboard.time_matrices.shape[1] != self.blackboard.distance_matrices.shape[2]:
            raise AttributeError("time_matrices must be a square matrices")

        return True

    def process(self):

        log.info("Process Initial Solution")
        log.debug("-- Clustering")
        num_vehicle = self.blackboard.num_vehicle
        matrix = self.blackboard.time_matrices[0]
        cluster = AgglomerativeClustering(n_clusters=min(num_vehicle, matrix.shape[0]), metric='precomputed', linkage='complete').fit(matrix)

        log.debug("-- Compute initial solution")
        num_services = numpy.zeros(num_vehicle, dtype=int)
        for i in range(1, cluster.labels_.size):
            vehicle = cluster.labels_[i]
            num_services[vehicle] += 1

        max_capacity = numpy.max(num_services) + 10 #Add margin to let algorithm the possibility to optimize something
        num_services = numpy.zeros(num_vehicle, dtype=int)

        self.blackboard.paths = numpy.full((num_vehicle, max_capacity), -1, dtype=numpy.int32)

        for i in range(1, cluster.labels_.size):
            vehicle = cluster.labels_[i]
            position = num_services[vehicle]
            self.blackboard.paths[vehicle][position] = i
            num_services[vehicle] += 1
