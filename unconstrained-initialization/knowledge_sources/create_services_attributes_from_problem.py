#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy


def fill_every_services_tw(tw_array):
    # trouver la longueur maximale des listes dans le tableau
    max_length = max(len(l) for l in tw_array)

    # ajouter des valeurs de remplissage aux listes plus courtes
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

        # Services attributes
        services_TW_starts        = [[] for service in problem["services"]]
        services_TW_ends          = [[] for service in problem["services"]]
        services_duration         = []
        services_setup_duration   = []
        services_quantities       = [[] for service in problem['services']]
        services_matrix_index     = []
        services_sticky_vehicles  = {}

        for service_index, service in enumerate(problem['services']):
            if "vehicleIndices" in service:
                services_sticky_vehicles[service_index] = numpy.array(service["vehicleIndices"], dtype=numpy.int32)
            services_matrix_index.append(service["matrixIndex"])
            if len(service['timeWindows']) > 0:
                for timeWindow in service['timeWindows'] :
                    services_TW_starts[service_index].append(timeWindow['start'])
                    if "maximumLateness" in timeWindow and service['lateMultiplier'] > 0:
                        maxLateness = timeWindow["maximumLateness"]
                    else :
                        maxLateness = 0
                    services_TW_ends[service_index].append(timeWindow['end'] + maxLateness)
            else :
                services_TW_starts[service_index].append(0)
                services_TW_ends[service_index].append(-1)
            services_duration.append(service['duration'])
            if "setupDuration" in service:
                services_setup_duration.append(service['setupDuration'])
            else :
                services_setup_duration.append(0)
            if len(service['quantities']) > 0 :
                for quantity in service['quantities']:
                    services_quantities[service_index].append(quantity)
            else :
                services_quantities[service_index].append(0)
        num_services = len(problem['services'])


        services_TW_starts  = fill_every_services_tw(services_TW_starts)
        services_TW_ends    = fill_every_services_tw(services_TW_ends)

        # Services attributes
        self.blackboard.service_matrix_index = numpy.array(services_matrix_index, dtype=numpy.int32)
        self.blackboard.start_tw            = services_TW_starts
        self.blackboard.end_tw              = services_TW_ends
        self.blackboard.durations           = numpy.array(services_duration, dtype=numpy.float64)
        self.blackboard.setup_durations     = numpy.array(services_setup_duration, dtype=numpy.float64)
        self.blackboard.services_volumes    = numpy.array(services_quantities, dtype=numpy.float64)
        self.blackboard.size                = num_services + len(list(set([vehicle['startIndex'] for vehicle in problem['vehicles']])))
        self.blackboard.num_units           = num_units
        self.blackboard.num_services        = num_services
        self.blackboard.service_sticky_vehicles = services_sticky_vehicles

        log.info(f"service matrix index : {self.blackboard.service_matrix_index}")
