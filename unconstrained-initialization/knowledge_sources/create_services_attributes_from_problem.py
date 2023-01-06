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

        return True

    def process(self):
        
        problem = self.blackboard.problem

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
        self.blackboard.start_tw            = numpy.array(services_TW_starts, dtype=numpy.float64)
        self.blackboard.end_tw              = numpy.array(services_TW_ends, dtype=numpy.float64)
        self.blackboard.durations           = numpy.array(services_duration, dtype=numpy.float64)
        self.blackboard.setup_durations     = numpy.array(services_setup_duration, dtype=numpy.float64)
        self.blackboard.services_volume     = numpy.array(services_quantities, dtype=numpy.float64)
        self.blackboard.size = len(problem['services'])

