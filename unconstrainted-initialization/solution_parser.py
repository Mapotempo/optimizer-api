import numpy
import timeit
import random
import logging
import json
from fastvrpy.core import algorithm
import cProfile
from sklearn.metrics import pairwise_distances
from sklearn.cluster import KMeans, AgglomerativeClustering, OPTICS, SpectralClustering, MiniBatchKMeans, DBSCAN

import localsearch_result_pb2
import math
import numpy
from google.protobuf.json_format import MessageToDict
import sys


def ParseSolution(solution, vrp):
    paths = numpy.asarray(solution.paths)
    result = localsearch_result_pb2.Result()
    routes = []
    relations = []
    for index,path in enumerate(paths):
        services_ids = [ "service" + str(stops-1) for stops in path if stops != -1 ]
        vehicle_id = f"vehic{index}_0"
        dic  = {"vehicle_id": vehicle_id, "mission_ids" : services_ids}
        dic1 = {"type" : "order", "linked_ids" : services_ids}
        routes.append(dic)
        relations.append(dic1)


    with open("result.json", "w") as file:
        json.dump(routes, file, indent=4)
    with open("relations.json", "w") as file:
        json.dump(relations, file, indent=4)


    for path_index,path in enumerate(paths):
        if len(set(path)) > 1 :
            route = result.routes.add()
            store = route.activities.add()
            store.id = "store"
            store.index = -1
            store.start_time = int(solution.vehicle_starts[path_index])
            store.type = "start"
            for stop_index,stop in enumerate(path):
                if stop != -1 :
                    activity = route.activities.add()
                    activity.id = "service" + str(stop-1)
                    activity.index = stop-1
                    activity.start_time = int(solution.starts[path_index, stop_index+1])
                    activity.type = "service"
            store_return = route.activities.add()
            store_return.id = "store"
            store_return.index = -1
            store_return.start_time = int(solution.vehicle_ends[path_index])
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

    return result
