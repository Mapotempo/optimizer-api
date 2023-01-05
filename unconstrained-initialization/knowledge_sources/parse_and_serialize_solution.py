#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
import numpy
from sklearn.cluster import KMeans, AgglomerativeClustering, OPTICS, SpectralClustering, MiniBatchKMeans, DBSCAN
from fastvrpy.core.solutions import cvrptw

from google.protobuf.json_format import MessageToDict
import localsearch_result_pb2
import json



class ParseAndSerializeSolution(AbstractKnowledgeSource):
    """
   Parse and Serialize the founded solution
    """
    def verify(self):

        if self.blackboard.solution is None:
            raise AttributeError("Solution is None, not possible to parse and serialize the solution")

        if self.blackboard.output_file is None:
            raise AttributeError("Output file is None, not possible to parse and serialize the solution")


        return True

    def process(self):
        paths = numpy.asarray(self.blackboard.solution.paths)
        result = localsearch_result_pb2.Result()

        for path_index,path in enumerate(paths):
            if len(set(path)) > 1 :
                route = result.routes.add()
                store = route.activities.add()
                store.id = "store"
                store.index = -1
                store.start_time = int(self.blackboard.solution.vehicle_starts[path_index])
                store.type = "start"
                for stop_index,stop in enumerate(path):
                    if stop != -1 :
                        activity = route.activities.add()
                        activity.id = "service" + str(stop-1)
                        activity.index = stop-1
                        activity.start_time = int(self.blackboard.solution.starts[path_index, stop_index+1])
                        activity.type = "service"
                store_return = route.activities.add()
                store_return.id = "store"
                store_return.index = -1
                store_return.start_time = int(self.blackboard.solution.vehicle_ends[path_index])
                store_return.type = "end"
                cost_details = route.cost_details
                cost_details.fixed = 0
            else:
                route = result.routes.add()
                start_route = route.activities.add()
                start_route.type ="start"
                start_route.index = -1
                start_route.start_time = 0
                end_route = route.activities.add()
                end_route.type ="start"
                end_route.index = -1
                end_route.start_time = 0

        f = open(self.blackboard.output_file, "wb")
        f.write(route.SerializeToString())
        f.close()
