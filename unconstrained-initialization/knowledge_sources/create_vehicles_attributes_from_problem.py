#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy

class CreateVehiclesAttributesFromProblem(AbstractKnowledgeSource):
    """
    Create all vehicles attributes from problem
    """

    def verify(self):

        problem = self.blackboard.problem
        if problem is None:
            raise AttributeError("Problem is None, not possible to create vehicles attributes")
        if not isinstance(problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create vehicles attributes")

        if not "vehicles" in problem:
            raise AttributeError("There is no vehicle in the problem, not possible to run")

        for vehicle in problem["vehicles"]:
            if not "id" in vehicle:
                raise AttributeError("At least one vehicle doesn't have an Id, not possible to create vehicle attributes")

        return True

    def process(self):

        problem = self.blackboard.problem
        # Vehicle attributes
        self.blackboard.num_vehicle     = len(problem['vehicles'])
        num_services                    = len(problem['services'])
        cost_distance_multiplier        = []
        cost_time_multiplier            = []
        vehicles_capacities             = [[] for i in range (self.blackboard.num_vehicle) ]
        vehicles_TW_starts              = []
        vehicles_TW_ends                = []
        vehicles_distance_max           = []
        vehicles_fixed_costs            = []
        vehicles_overload_multiplier    = [[] for i in range (self.blackboard.num_vehicle) ]
        vehicle_matrix_index            = []
        vehicle_start_index             = []
        vehicle_end_index               = []
        force_start                     = []
        vehicle_id_index                = {}
        previous_vehicle = problem['vehicles'][0]

        for vehicle_index,vehicle in enumerate(problem['vehicles']) :
            vehicle_id_index[vehicle['id']] = vehicle_index
            vehicle_matrix_index.append(vehicle["matrixIndex"])

            vehicle_start_index.append(vehicle["startIndex"])

            vehicle_end_index.append(vehicle["endIndex"])

            if "shiftPreference" in vehicle:
                if vehicle["shiftPreference"] == "force_start":
                    force_start.append(1)
                else :
                    force_start.append(0)
            else :
                force_start.append(0)

            if "costFixed" in vehicle:
                vehicles_fixed_costs.append(vehicle["costFixed"])
            else:
                vehicles_fixed_costs.append(0)
            if 'capacities' in vehicle:
                if len(vehicle['capacities']) > 0:
                    for capacity in vehicle['capacities']:
                        vehicles_capacities[vehicle_index].append(capacity['limit'])
                        if "overloadMultiplier" in capacity:
                            vehicles_overload_multiplier[vehicle_index].append(capacity["overloadMultiplier"])
                        else:
                            vehicles_overload_multiplier[vehicle_index].append(0)
                else :
                    vehicles_capacities[vehicle_index].append(-1)
                    vehicles_overload_multiplier[vehicle_index].append(0)
            if 'costDistanceMultiplier' in vehicle:
                cost_distance_multiplier.append(vehicle['costDistanceMultiplier'])
            else :
                cost_distance_multiplier.append(0)
            if 'costTimeMultiplier' in vehicle:
                cost_time_multiplier.append(vehicle['costTimeMultiplier'])
            else :
                cost_time_multiplier.append(0)
            if "timeWindow" in vehicle:
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
            if "distance" in vehicle:
                if vehicle["distance"]==0:
                    vehicles_distance_max.append(-1)
                else :
                    vehicles_distance_max.append(vehicle['distance'])
            else :
                vehicles_distance_max.append(-1)
            previous_vehicle = vehicle
        if 'capacities' in problem['vehicles'][0] and len(problem['vehicles'][0]['capacities']) > 0:
            self.blackboard.max_capacity = int(problem['vehicles'][0]['capacities'][0]['limit'])
        else:
            self.blackboard.max_capacity = 2**30


        # Vehicles attributes
        self.blackboard.cost_time_multiplier         = numpy.array(cost_time_multiplier,         dtype=numpy.float64)
        self.blackboard.cost_distance_multiplier     = numpy.array(cost_distance_multiplier,     dtype=numpy.float64)
        self.blackboard.vehicle_capacities           = numpy.array(vehicles_capacities,          dtype=numpy.float64)
        self.blackboard.vehicles_TW_starts           = numpy.array(vehicles_TW_starts,           dtype=numpy.float64)
        self.blackboard.vehicles_TW_ends             = numpy.array(vehicles_TW_ends,             dtype=numpy.float64)
        self.blackboard.vehicles_distance_max        = numpy.array(vehicles_distance_max,        dtype=numpy.float64)
        self.blackboard.vehicles_fixed_costs         = numpy.array(vehicles_fixed_costs,         dtype=numpy.float64)
        self.blackboard.vehicles_overload_multiplier = numpy.array(vehicles_overload_multiplier, dtype=numpy.float64)
        self.blackboard.vehicles_matrix_index        = numpy.array(vehicle_matrix_index,         dtype=numpy.int32)
        self.blackboard.force_start                  = numpy.array(force_start,         dtype=numpy.int32)

        self.blackboard.vehicle_end_index            = numpy.array(vehicle_end_index, dtype=numpy.int32)
        self.blackboard.vehicle_start_index          = numpy.array(vehicle_start_index, dtype=numpy.int32)
        self.blackboard.previous_vehicle = numpy.array([ -1 for _ in range(self.blackboard.num_vehicle)], dtype= numpy.int32)
        if "relations" in problem :
            for relation in problem['relations']:
                if relation['type'] == "vehicle_trips":
                    size = len(relation['linkedVehicleIds'])
                    for i in range(size):
                        if i == 0 :
                            self.blackboard.previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = -1
                        else :
                            self.blackboard.previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = vehicle_id_index[relation['linkedVehicleIds'][i-1]]
