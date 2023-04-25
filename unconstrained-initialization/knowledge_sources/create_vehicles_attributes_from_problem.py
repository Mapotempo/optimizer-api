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
        vehicles_TW_margin              = []
        vehicles_distance_max           = []
        vehicles_duration_max           = []
        vehicles_fixed_costs            = []
        vehicles_overload_multiplier    = [[] for i in range (self.blackboard.num_vehicle) ]
        vehicle_matrix_index            = []
        vehicle_start_index             = []
        vehicle_end_index               = []
        force_start                     = []
        free_approach                   = []
        free_return                     = []
        vehicle_id_index                = {}
        previous_vehicle = problem['vehicles'][0]

        for vehicle_index,vehicle in enumerate(problem['vehicles']) :
            vehicle_id_index[vehicle['id']] = vehicle_index
            vehicle_matrix_index.append(vehicle.get("matrixIndex",0))

            vehicle_start_index.append(vehicle.get("startIndex", 0))

            vehicle_end_index.append(vehicle.get("endIndex", 0))
            free_approach.append(vehicle.get("free_approach", 0))
            free_approach.append(vehicle.get("free_return", 0))
            shift_preference = vehicle.get("shiftPreference","")
            if shift_preference == "force_start":
                force_start.append(2)
            else :
                force_start.append(1)

            vehicles_fixed_costs.append(vehicle.get("costFixed", 0))
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
            cost_distance_multiplier.append(vehicle.get('costDistanceMultiplier',0))
            cost_time_multiplier.append(vehicle.get('costTimeMultiplier'))
            vehicles_TW_starts.append(vehicle["timeWindow"].get("start",0))
            vehicles_TW_ends.append(vehicle["timeWindow"].get("end",-1))
            if vehicle.get("costLateMultiplier", 0) > 0:
                vehicles_TW_margin.append(vehicle.get("maximumLateness", 0))
            else :
                vehicles_TW_margin.append(0)
            distance_max = vehicle.get("distance",0)
            if distance_max==0:
                vehicles_distance_max.append(-1)
            else :
                vehicles_distance_max.append(distance_max)
            duration_max = vehicle.get("duration",0)
            if duration_max == 0 :
                vehicles_duration_max.append(-1)
            else:
                vehicles_duration_max.append(duration_max)
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
        self.blackboard.vehicle_time_window_margin   = numpy.array(vehicles_TW_margin,           dtype=numpy.float64)
        self.blackboard.vehicles_distance_max        = numpy.array(vehicles_distance_max,        dtype=numpy.float64)
        self.blackboard.vehicles_duration_max        = numpy.array(vehicles_duration_max,        dtype=numpy.float64)
        self.blackboard.vehicles_fixed_costs         = numpy.array(vehicles_fixed_costs,         dtype=numpy.float64)
        self.blackboard.vehicles_overload_multiplier = numpy.array(vehicles_overload_multiplier, dtype=numpy.float64)
        self.blackboard.vehicles_matrix_index        = numpy.array(vehicle_matrix_index,         dtype=numpy.int32)
        self.blackboard.force_start                  = numpy.array(force_start,         dtype=numpy.int32)
        self.blackboard.free_approach                = numpy.array(free_approach,        dtype=numpy.int32)
        self.blackboard.free_return                  = numpy.array(free_return,         dtype=numpy.int32)

        self.blackboard.vehicle_end_index            = numpy.array(vehicle_end_index, dtype=numpy.int32)
        self.blackboard.vehicle_start_index          = numpy.array(vehicle_start_index, dtype=numpy.int32)
        self.blackboard.previous_vehicle = numpy.array([ -1 for _ in range(self.blackboard.num_vehicle)], dtype= numpy.int32)

        self.blackboard.vehicle_id_index = vehicle_id_index

        if "relations" in problem :
            for relation in problem['relations']:
                if relation['type'] == "vehicle_trips":
                    size = len(relation['linkedVehicleIds'])
                    for i in range(size):
                        if i == 0 :
                            self.blackboard.previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = -1
                        else :
                            self.blackboard.previous_vehicle[vehicle_id_index[relation['linkedVehicleIds'][i]]] = vehicle_id_index[relation['linkedVehicleIds'][i-1]]
