#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
from google.protobuf.json_format import MessageToDict
import localsearch_vrp_pb2

class DeserializeProblem(AbstractKnowledgeSource):
    """
    Deserialization of the problem dictionnary
    """

    def verify(self):

        if self.blackboard.instance is None:
            raise AttributeError("Instance is None, not possible to create the problem")

        return True

    def process(self):
        instance = self.blackboard.instance

        with open(instance, 'rb') as f:
            self.blackboard.problem = localsearch_vrp_pb2.Problem()
            self.blackboard.problem.ParseFromString(f.read())
            self.blackboard.problem = MessageToDict(self.blackboard.problem, including_default_value_fields=True)


