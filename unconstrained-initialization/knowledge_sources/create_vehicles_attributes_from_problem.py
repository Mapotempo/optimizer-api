#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
import numpy

class CreateVehiclesAttributesFromProblem(AbstractKnowledgeSource):
    """
    Create all vehicles attributes from problem
    """

    def verify(self):

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to create vehicles attributes")
        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create vehicles attributes")

        return True

    def process(self):
        
        problem = self.blackboard.problem
        # Vehicle attributes
        self.blackboard.num_vehicles = len(problem['vehicles'])
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
                vehicles_overload_multiplier.append(0)
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

        # Vehicles attributes
        self.blackboard.cost_time_multiplier         = numpy.array(cost_time_multiplier,     dtype=numpy.float64)
        self.blackboard.cost_distance_multiplier     = numpy.array(cost_distance_multiplier, dtype=numpy.float64)
        self.blackboard.vehicle_capacity             = numpy.array(vehicles_capacity,        dtype=numpy.float64)
        self.blackboard.vehicles_TW_starts           = numpy.array(vehicles_TW_starts,       dtype=numpy.float64)
        self.blackboard.vehicles_TW_ends             = numpy.array(vehicles_TW_ends,         dtype=numpy.float64)
        self.blackboard.vehicles_distance_max        = numpy.array(vehicles_distance_max,    dtype=numpy.float64)
        self.blackboard.vehicles_fixed_costs         = numpy.array(vehicles_fixed_costs,    dtype=numpy.float64)
        self.blackboard.vehicles_overload_multiplier = numpy.array(vehicles_overload_multiplier,    dtype=numpy.float64)

