import numpy
import timeit
import random
import logging as log
from fastvrpy.core import algorithm
import cProfile
from sklearn.metrics import pairwise_distances
from sklearn.cluster import KMeans, AgglomerativeClustering, OPTICS, SpectralClustering, MiniBatchKMeans, DBSCAN
from fastvrpy.utils import *
import localsearch_vrp_pb2
import math
import numpy
from google.protobuf.json_format import MessageToDict
import sys
import json
from fastvrpy import solver
from solution_parser import ParseSolution

log_config()
root_log = log.getLogger("root")
root_log.setLevel(log.INFO)
wrapper_log = log.getLogger("wrapper")
wrapper_log.setLevel(log.INFO)

args = sys.argv[1:]

index = args.index("-time_limit_in_ms")
duration = int(args[index + 1]) / 1000

for arg in sys.argv :
    if "optimize-or-tools-input" in arg:
        instance = arg
    if "optimize-or-tools-output" in arg:
        solution_file = arg

log.info("Start Initial Solution")

with open(instance, 'rb') as f:
    problem = localsearch_vrp_pb2.Problem()
    problem.ParseFromString(f.read())
    problem = MessageToDict(problem, including_default_value_fields=True)

    # Vehicle attributes
    num_vehicles = len(problem['vehicles'])
    cost_distance_multiplier     = []
    cost_time_multiplier         = []
    vehicles_capacity            = []
    vehicles_TW_starts           = []
    vehicles_TW_ends             = []
    vehicles_distance_max        = []
    vehicles_fixed_costs         = []
    vehicles_overload_multiplier = []
    for vehicle in problem['vehicles'] :
        if vehicle["costFixed"]:
            vehicles_fixed_costs.append(vehicle["costFixed"])
        else:
            vehicles_fixed_costs.append(0)
        if len(vehicle['capacities']) > 0:
            vehicles_capacity.append(vehicle['capacities'][0]['limit'])
            if vehicle['capacities'][0]["overloadMultiplier"]:
                vehicles_overload_multiplier.append(vehicle['capacities'][0]["overloadMultiplier"])
            else:
                vehicles_overload_multiplier.append(0)
        else :
            vehicles_capacity.append(-1)
        if vehicle['costDistanceMultiplier']:
            cost_distance_multiplier.append(vehicle['costDistanceMultiplier'])
        else :
            cost_distance_multiplier.append(0)
        if vehicle['costTimeMultiplier']:
            cost_time_multiplier.append(vehicle['costTimeMultiplier'])
        else :
            cost_time_multiplier.append(0)
        if vehicle['timeWindow']:
            if 'start' in vehicle['timeWindow']:
                vehicles_TW_starts.append(vehicle['timeWindow']["start"])
            else :
                vehicles_TW_starts.append(0)
            if 'maximumLateness' in vehicle['timeWindow']:
                vehicles_TW_ends.append(vehicle['timeWindow']["end"] + vehicle['timeWindow']["maximumLateness"])
            else :
                vehicles_TW_ends.append(vehicle['timeWindow']["end"])
        else :
            vehicles_TW_starts.append(0)
            vehicles_TW_ends.append(-1)
        if vehicle['distance']:
            vehicles_distance_max.append(vehicle['distance'])
        else :
            vehicles_distance_max.append(-1)

    # # Build Matrices :
    time_matrices     = []
    distance_matrices = []
    vehicle_index     = 0
    for matrice in problem['matrices']:
        vehicle = problem['vehicles'][vehicle_index]
        time_matrix = []
        time_matrix_size = int(math.sqrt(len(matrice['time'])))
        timeToWarehouse =[]
        timeToWarehouse.append(matrice['time'][vehicle['endIndex'] * time_matrix_size + vehicle['endIndex']])
        for service in problem['services']:
            timeToWarehouse.append(matrice['time'][vehicle['startIndex'] * time_matrix_size + service['matrixIndex'] ])
        time_matrix.append(timeToWarehouse)
        for serviceFrom in problem['services']:
            # print(serviceFrom)
            matrix_row = []
            matrix_row.append(matrice['time'][ serviceFrom['matrixIndex']* time_matrix_size + vehicle['endIndex'] ])
            for serviceTo in problem['services']:
                matrix_row.append(matrice['time'][serviceFrom['matrixIndex'] * time_matrix_size + serviceTo['matrixIndex']])
            time_matrix.append(matrix_row)
        time_matrices.append(time_matrix)
        vehicle_index += 1

    vehicle_index = 0
    for matrice in problem['matrices']:
        vehicle = problem['vehicles'][vehicle_index]
        distance_matrix = []
        distance_matrix_size = int(math.sqrt(len(matrice['distance'])))
        distanceToWarehouse =[]
        distanceToWarehouse.append(matrice['distance'][vehicle['endIndex'] * distance_matrix_size + vehicle['endIndex']])
        for service in problem['services']:
            distanceToWarehouse.append(matrice['distance'][vehicle['startIndex'] * distance_matrix_size + service['matrixIndex'] ])
        distance_matrix.append(distanceToWarehouse)
        for serviceFrom in problem['services']:
            # print(serviceFrom)
            matrix_row = []
            matrix_row.append(matrice['distance'][ serviceFrom['matrixIndex']* distance_matrix_size + vehicle['endIndex'] ])
            for serviceTo in problem['services']:
                matrix_row.append(matrice['distance'][serviceFrom['matrixIndex'] * distance_matrix_size + serviceTo['matrixIndex']])
            distance_matrix.append(matrix_row)
        distance_matrices.append(distance_matrix)
        vehicle_index += 1

    # Services attributes
    services_TW_starts        = [0]
    services_TW_ends          = [200000]
    services_duration         = [0]
    services_setup_duration   = [0]
    services_quantities       = [0]
    for service in problem['services']:
        if len(service['timeWindows']) > 0:
            services_TW_starts.append(service['timeWindows'][0]['start'])
            if "maximumLateness" in service['timeWindows'][0] and service['lateMultiplier'] > 0:
                maxLateness = service['timeWindows'][0]["maximumLateness"]
            else :
                maxLateness = 0
            services_TW_ends.append(service['timeWindows'][0]['end'] + maxLateness)
        else :
            services_TW_starts.append(0)
            services_TW_ends.append(-1)
        services_duration.append(service['duration'])
        if "setupDuration" in service:
            services_setup_duration.append(service['setupDuration'])
        else :
            services_setup_duration.append(0)
        if len(service['quantities']) > 0 :
            services_quantities.append(service['quantities'][0])
        else :
            services_quantities.append(0)


    # Services attributes
    start_tw            = numpy.array(services_TW_starts, dtype=numpy.float64)
    end_tw              = numpy.array(services_TW_ends, dtype=numpy.float64)
    durations           = numpy.array(services_duration, dtype=numpy.float64)
    setup_durations     = numpy.array(services_setup_duration, dtype=numpy.float64)
    services_quantities = numpy.array(services_quantities, dtype=numpy.int32)

    # Vehicles attributes
    cost_time_multiplier     = numpy.array(cost_time_multiplier,     dtype=numpy.float64)
    cost_distance_multiplier = numpy.array(cost_distance_multiplier, dtype=numpy.float64)
    vehicle_capacity         = numpy.array(vehicles_capacity,        dtype=numpy.float64)
    vehicles_TW_starts       = numpy.array(vehicles_TW_starts,       dtype=numpy.float64)
    vehicles_TW_ends         = numpy.array(vehicles_TW_ends,         dtype=numpy.float64)
    vehicles_distance_max    = numpy.array(vehicles_distance_max,    dtype=numpy.float64)
    vehicles_fixed_costs     = numpy.array(vehicles_fixed_costs,    dtype=numpy.float64)
    vehicles_overload_multiplier = numpy.array(vehicles_overload_multiplier,    dtype=numpy.float64)

    # Matrices
    distance_matrix   = numpy.array(distance_matrices, dtype=numpy.float64)
    time_matrix       = numpy.array(time_matrices, dtype=numpy.float64)

    # numpy.savetxt("distance_matrix.txt", json.dumps(list(distance_matrix)))
    # numpy.savetxt("time_matrix.txt",     json.dumps(list(time_matrix)))

    SIZE = len(problem['services'])
    NUM_VEHICLE = len(problem['vehicles'])
    if 'capacities' in problem['vehicles'][0] and len(problem['vehicles'][0]['capacities']) > 0:
        MAX_CAPACITY = int(problem['vehicles'][0]['capacities'][0]['limit'])
    else:
        MAX_CAPACITY = 2**30



    # #Cost factors
    previous_vehicle = numpy.array([ -1 for _ in range(NUM_VEHICLE)], dtype= numpy.int32)
    vehicle_id_index = {}
    vehicle_index = 0
    for vehicle in problem['vehicles']:
        vehicle_id_index[vehicle['id']] = vehicle_index
        vehicle_index += 1

    for relation in problem['relations']:
        if relation['type'] == "vehicle_trips":
            size = len(relation['linkedVehicleIds'])
            for i in range(size):
                if i == 0 :
                    previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = -1
                else :
                    previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = vehicle_id_index[relation['linkedVehicleIds'][i-1]]


    log.info("Init parameters")
    # path_init = list(range(1,SIZE+1))

    random.seed(22021993)
    numpy.random.seed(22021993)


    cost_matrix = 0.3 * distance_matrix + 15 * time_matrix

    services_volume = numpy.array(services_quantities, dtype=numpy.float64)

    paths = process_initial_solution(NUM_VEHICLE, time_matrix[0])



    solution = algorithm.Solution(
        paths,
        distance_matrix,
        time_matrix,
        start_tw,
        end_tw,
        durations,
        setup_durations,
        services_volume,
        cost_distance_multiplier,
        cost_time_multiplier,
        vehicle_capacity,
        previous_vehicle,
        vehicles_distance_max,
        vehicles_fixed_costs,
        vehicles_overload_multiplier,
        vehicles_TW_starts,
        vehicles_TW_ends
        )

    solver.optimize(
        solution = solution,
        max_execution_time=int(duration/2),
        problem=problem,
        groups_max_capacity = MAX_CAPACITY
    )
    parsed_solution = ParseSolution(solution, problem)
    f = open(solution_file, "wb")
    f.write(parsed_solution.SerializeToString())
    f.close()

    print_kpis(solution)
