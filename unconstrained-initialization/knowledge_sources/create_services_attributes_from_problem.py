#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy


def fill_every_services_tw(tw_array):
    # find the number of TW needed
    max_length = max(len(l) for l in tw_array)

    # add -1 to arrays that are not large enough
    padded_list = [numpy.pad(l, (0, max_length - len(l)), 'constant', constant_values=-1) for l in tw_array]

    final_array = numpy.array(padded_list, dtype=numpy.float64)

    return final_array


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

        num_units   = max(len(problem['vehicles'][0]['capacities']),1)

        num_depots  = len(list(set([vehicle['startIndex'] for vehicle in problem['vehicles']])))

        num_services = len(problem["services"])

        # Services attributes
        services_TW_starts        = [[] for _ in problem["services"]]
        services_TW_ends          = [[] for _ in problem["services"]]
        services_max_lateness     = [[] for _ in problem["services"]]
        services_duration         = numpy.full(num_services,0,dtype=numpy.float64)
        services_setup_duration   = numpy.full(num_services,0,dtype=numpy.float64)
        services_quantities       = [[] for _ in problem["services"]]
        services_matrix_index     = numpy.full(num_services, -1,dtype=numpy.int32)
        services_sticky_vehicles  = {}

        for service_index, service in enumerate(problem['services']):
            services_sticky_vehicles[service_index] = numpy.array(service.get("vehicleIndices", []), dtype=numpy.int32)
            services_matrix_index[service_index] = (service.get("matrixIndex", 0))
            timeWindow = service.get('timeWindows', [])
            if len(timeWindow) > 0:
                for tw in timeWindow :
                    services_TW_starts[service_index].append(tw.get('start',0))
                    if service.get('lateMultiplier', 0) > 0:
                        maxLateness = tw.get("maximumLateness", 0)
                    else :
                        maxLateness = 0
                    services_max_lateness[service_index].append(maxLateness)
                    services_TW_ends[service_index].append(tw.get('end',-1))
            else :
                services_TW_starts[service_index].append(0)
                services_TW_ends[service_index].append(-1)
            services_duration[service_index] = (service.get('duration', 0))
            services_setup_duration[service_index] = (service.get('setupDuration',0))
            if len(service['quantities']) > 0 :
                for quantity in service['quantities']:
                    services_quantities[service_index].append(quantity)
            else :
                services_quantities[service_index].append(0)
        num_services = len(problem['services'])


        services_TW_starts  = fill_every_services_tw(services_TW_starts)
        services_TW_ends    = fill_every_services_tw(services_TW_ends)

        # Services attributes
        self.blackboard.service_matrix_index = services_matrix_index
        self.blackboard.start_tw            = services_TW_starts
        self.blackboard.end_tw              = services_TW_ends
        self.blackboard.services_max_lateness  = numpy.array(services_max_lateness, dtype=numpy.float64)
        self.blackboard.durations           = services_duration
        self.blackboard.setup_durations     = services_setup_duration
        self.blackboard.services_volumes    = numpy.array(services_quantities, dtype=numpy.float64)
        self.blackboard.size                = num_services + len(list(set([vehicle['startIndex'] for vehicle in problem['vehicles']])))
        self.blackboard.num_units           = num_units
        self.blackboard.num_services        = num_services
        self.blackboard.service_sticky_vehicles = services_sticky_vehicles
