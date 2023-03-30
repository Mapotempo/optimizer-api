#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy

def list_all_rests(problem):
    rests = []
    for vehicle_index, vehicle in enumerate(problem["vehicles"]):
        vehicle_rests = vehicle.get("rests",[])
        for rest in vehicle_rests:
            rests.append((rest, vehicle_index ))
    return rests



class CreateServicesAttributesFromProblem(AbstractKnowledgeSource):
    """
    Create all services attributes from problem
    """

    def verify(self):

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to create services attributes")
        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create services attributes")

        for service in self.blackboard.problem["services"]:
            if not all(key in service for key in ("matrixIndex", "timeWindows", "id")):
                raise AttributeError("API did not provide any TW for at least one service")

        return True

    def process(self):

        problem     = self.blackboard.problem

        # num_units   = max(len(problem['vehicles'][0]['capacities']),1)
        num_units = max(max(len(vehicle.get("capacities",[])) for vehicle in problem["vehicles"]),1)

        num_depots  = len(list(set([vehicle['startIndex'] for vehicle in problem['vehicles']])))

        num_services = len(problem["services"]) + sum(len(vehicle.get("rests",[])) for vehicle in problem['vehicles'] )

        rests = list_all_rests(problem)

        num_TW        = max(len(service.get('timeWindows',[])) for service in problem['services'])

        # Services attributes
        services_TW_starts        = numpy.full((num_services, num_TW), 0, dtype=numpy.float64)
        services_TW_ends          = numpy.full((num_services, num_TW), 0, dtype=numpy.float64)
        services_max_lateness     = numpy.full((num_services, num_TW), 0, dtype=numpy.float64)
        services_duration         = numpy.full(num_services,0,dtype=numpy.float64)
        services_setup_duration   = numpy.full(num_services,0,dtype=numpy.float64)
        services_quantities       = numpy.full((num_services,num_units),0,dtype=numpy.float64)
        services_matrix_index     = numpy.full(num_services, -1,dtype=numpy.int32)
        services_sticky_vehicles  = {}
        is_break                  = numpy.full(num_services,0,dtype=numpy.int32)

        for service_index, service in enumerate(problem['services']):
            services_sticky_vehicles[service_index] = numpy.array(service.get("vehicleIndices", []), dtype=numpy.int32)
            services_matrix_index[service_index] = (service.get("matrixIndex", 0))
            timeWindows = service.get('timeWindows', [])
            if len(timeWindows) > 0:
                for tw_index, tw in enumerate(timeWindows) :
                    services_TW_starts[service_index, tw_index] = tw.get('start',0)
                    if service.get('lateMultiplier', 0) > 0:
                        maxLateness = tw.get("maximumLateness", 0)
                    else :
                        maxLateness = 0
                    services_max_lateness[service_index, tw_index] = maxLateness
                    services_TW_ends[service_index, tw_index] = tw.get('end',-1)
            else :
                services_TW_starts[service_index,0] = 0
                services_TW_ends[service_index,0] = -1
            services_duration[service_index] = (service.get('duration', 0))
            services_setup_duration[service_index] = (service.get('setupDuration',0))
            quantities = service.get('quantities',[])
            if len(quantities) > 0 :
                for unit_index, quantity in enumerate(quantities):
                    services_quantities[service_index, unit_index] = quantity
            else :
                services_quantities[service_index, 0] = 0

        num_services_without_rests = len(problem['services'])


        for rest_index, rest in enumerate(rests):
            is_break[num_services_without_rests + rest_index] = 1
            services_matrix_index[num_services_without_rests + rest_index] = -1
            tw = rest[0].get('timeWindow', [])
            services_TW_starts[num_services_without_rests + rest_index, tw_index] = tw.get('start',0)
            services_max_lateness[num_services_without_rests + rest_index, tw_index] = 0
            services_TW_ends[num_services_without_rests + rest_index, tw_index] = tw.get('end',-1)
            services_duration[num_services_without_rests + rest_index] = rest[0].get("duration", 0)
            services_setup_duration[num_services_without_rests + rest_index] = rest[0].get("setupDuration", 0)
            services_sticky_vehicles[num_services_without_rests + rest_index] = numpy.array([rest[1]], dtype=numpy.int32)

            for unit_index in range(num_units):
                services_quantities[num_services_without_rests + rest_index, unit_index] = 0



        # Services attributes
        self.blackboard.service_matrix_index    = services_matrix_index
        self.blackboard.start_tw                = services_TW_starts
        self.blackboard.end_tw                  = services_TW_ends
        self.blackboard.services_max_lateness   = services_max_lateness
        self.blackboard.durations               = services_duration
        self.blackboard.setup_durations         = services_setup_duration
        self.blackboard.services_volumes        = services_quantities
        self.blackboard.size                    = num_services
        self.blackboard.num_units               = num_units
        self.blackboard.num_services            = num_services
        self.blackboard.service_sticky_vehicles = services_sticky_vehicles
        self.blackboard.is_break                = is_break
        self.blackboard.rests = rests
