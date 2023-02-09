#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
log = log.getLogger(__file__)

#KS imports
import numpy
from marshmallow import fields, validate
from schema import Schema, And, Use, Optional, SchemaError, Or

class CheckResolution(AbstractKnowledgeSource):
    """
    Create all services attributes from problem
    """

    def verify(self):

        problem = self.blackboard.problem

        if self.blackboard.problem is None:
            raise AttributeError("Problem is None, not possible to check if the possible")

        if not isinstance(self.blackboard.problem, dict):
            raise AttributeError("Problem is not of type dict, not possible to create the dictionnary")

        if "relations" in problem :
            for relation in problem["relations"]:
                if relation["type"] in ["order", "sequence"]:
                    raise NotImplementedError("This algorithm can't handle with sequence or order relations")
                if relation["type"] in ["never_first", "never_last", "always_first", "always_last"]:
                    raise NotImplementedError("Can't handle positions for services")


        for vehicle in problem["vehicles"]:
            if "shiftPreference" in vehicle:
                if vehicle["shiftPreference"] in ["force_start", "force_end"]:
                    raise NotImplementedError("This algorithm can't handle with vehicles shift_preferences for now")

        for service in problem["services"]:
            if "activity" in service:
                if "position" in service["activity"]:
                    if service["activity"]["position"] in ["always_first", "always_last", "never_first"]:
                        raise NotImplementedError("This algorithm can't handle with services positions for now")
            elif "activities" in service:
                for activity in service["activities"]:
                    if activity["positions"] in ["always_first", "always_last", "never_first"]:
                        raise NotImplementedError("This algorithm can't handle with services positions for now")





        problem_schema = Schema(
            {
                "matrices" : [{
                    "time":[Or(float, int)],
                    "distance":[Or(float, int)]
                }],
                "vehicles" : [{
                    'endIndex': int,
                    'startIndex': int,
                    'matrixIndex': int
                }],
                "services" :
                [
                    {
                        'matrixIndex':int,
                        'id' : str,
                        Optional('priority'):int,
                        Optional("activity") :{
                            'timeWindows':Or([{
                                "start": Or(int,float),
                                "end": Or(int,float),
                                "maximumLateness": Or(int, float)
                            }],[])},
                        Optional("activities"):
                            [{
                                'timeWindows':Or([{
                                    "start": Or(int,float),
                                    "end": Or(int,float),
                                    "maximumLateness": Or(int, float)
                                }],[])
                            }]
                    }
                ]
            },
            ignore_extra_keys=True
        )
        problem_schema.validate(self.blackboard.problem)

        return True

    def process(self):
        return None
