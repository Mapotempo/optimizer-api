#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy

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

        # Services attributes
        services_TW_starts        = []
        services_TW_ends          = []
        services_duration         = []
        services_setup_duration   = []
        services_quantities       = [[] for i in problem['services']]
        for service_index, service in enumerate(problem['services']):
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
                for quantity in service['quantities']:
                    services_quantities[service_index].append(quantity)
            else :
                services_quantities[service_index].append(0)

        # Services attributes
        self.blackboard.start_tw            = numpy.array(services_TW_starts, dtype=numpy.float64)
        self.blackboard.end_tw              = numpy.array(services_TW_ends, dtype=numpy.float64)
        self.blackboard.durations           = numpy.array(services_duration, dtype=numpy.float64)
        self.blackboard.setup_durations     = numpy.array(services_setup_duration, dtype=numpy.float64)
        self.blackboard.services_volumes    = numpy.array(services_quantities, dtype=numpy.float64)
        self.blackboard.size                = len(problem['services'])
        self.blackboard.num_units           = num_units