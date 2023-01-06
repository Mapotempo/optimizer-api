#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
import numpy

class CreateDictionnaryIndexId(AbstractKnowledgeSource):
    """
    Create all services attributes from problem
    """

    def verify(self):

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to create the dictionnary")
        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create the dictionnary")

        for service in self.blackboard.problem["services"]:
            if not 'id' in service:
                raise AttributeError("At least one service has no Id, not possible to create the dictionnary")

        return True

    def process(self):

        problem = self.blackboard.problem

        # Services attributes
        self.blackboard.service_index_to_id = {}
        for service_index, service in enumerate(problem['services']):
            self.blackboard.service_index_to_id[service_index + 1] = service["id"]
