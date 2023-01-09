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
        self.blackboard.num_vehicle = len(problem['vehicles'])
        cost_distance_multiplier     = []
        cost_time_multiplier         = []
        vehicles_capacity            = []
        vehicles_TW_starts           = []
        vehicles_TW_ends             = []
        vehicles_distance_max        = []
        vehicles_fixed_costs         = []
        vehicles_overload_multiplier = []
        for vehicle in problem['vehicles'] :
            if "costFixed" in vehicle:
                vehicles_fixed_costs.append(vehicle["costFixed"])
            else:
                vehicles_fixed_costs.append(0)
            if 'capacities' in vehicle:
                if len(vehicle['capacities']) > 0:
                    vehicles_capacity.append(vehicle['capacities'][0]['limit'])
                    if "overloadMultiplier" in vehicle['capacities'][0]:
                        vehicles_overload_multiplier.append(vehicle['capacities'][0]["overloadMultiplier"])
                    else:
                        vehicles_overload_multiplier.append(0)
            else :
                vehicles_capacity.append(-1)
                vehicles_overload_multiplier.append(0)
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
                vehicles_distance_max.append(vehicle['distance'])
            else :
                vehicles_distance_max.append(-1)

        if 'capacities' in problem['vehicles'][0] and len(problem['vehicles'][0]['capacities']) > 0:
            self.blackboard.max_capacity = int(problem['vehicles'][0]['capacities'][0]['limit'])
        else:
            self.blackboard.max_capacity = 2**30

        # Vehicles attributes
        self.blackboard.cost_time_multiplier         = numpy.array(cost_time_multiplier,         dtype=numpy.float64)
        self.blackboard.cost_distance_multiplier     = numpy.array(cost_distance_multiplier,     dtype=numpy.float64)
        self.blackboard.vehicle_capacity             = numpy.array(vehicles_capacity,            dtype=numpy.float64)
        self.blackboard.vehicles_TW_starts           = numpy.array(vehicles_TW_starts,           dtype=numpy.float64)
        self.blackboard.vehicles_TW_ends             = numpy.array(vehicles_TW_ends,             dtype=numpy.float64)
        self.blackboard.vehicles_distance_max        = numpy.array(vehicles_distance_max,        dtype=numpy.float64)
        self.blackboard.vehicles_fixed_costs         = numpy.array(vehicles_fixed_costs,         dtype=numpy.float64)
        self.blackboard.vehicles_overload_multiplier = numpy.array(vehicles_overload_multiplier, dtype=numpy.float64)

        vehicle_id_index = {}
        vehicle_index = 0
        for vehicle in problem['vehicles']:
            vehicle_id_index[vehicle['id']] = vehicle_index
            vehicle_index += 1

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
