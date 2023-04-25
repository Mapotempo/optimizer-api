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
            self.blackboard.service_index_to_id[service_index] = service["id"]

        # Services attributes
        self.blackboard.service_index_to_id = {}
        self.blackboard.service_id_to_index_in_problem = {}
        total_visit_number = 0

        for service_index, service in enumerate(problem['services']):
            visits_number = 1
            id = service["id"]
            if "visitsNumber" in service :
                visits_number = service["visitsNumber"]
            for visit in range(visits_number):
                if visits_number > 1 :
                    self.blackboard.service_id_to_index_in_problem[id] = service_index
                    self.blackboard.service_index_to_id[total_visit_number] = f"{id}_{visit}"
                    total_visit_number += 1
                else :
                    self.blackboard.service_id_to_index_in_problem[id] = service_index
                    self.blackboard.service_index_to_id[total_visit_number] = f"{id}"
                    total_visit_number += 1

        for rest_index, rest in enumerate(self.blackboard.rests):
            self.blackboard.service_index_to_id[total_visit_number + rest_index] = rest[0].get("id", f"rest_{rest_index}")
        # Services attributes
        self.blackboard.service_index_in_paths_to_pb_index = {}
        total_visit_number = 0
        num_depot = 0
