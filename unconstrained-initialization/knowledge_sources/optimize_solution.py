#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
from fastvrpy import solver

class OptimizeSolution(AbstractKnowledgeSource):
    """
    Create all vehicles attributes from problem
    """

    def verify(self):

        if self.blackboard.solution is None:
            raise AttributeError("No solution specified... can't optimize nothing !")

        if self.blackboard.time_limit is None:
            raise AttributeError("No time limit for optimization")

        if self.blackboard.problem is None:
            raise AttributeError("No problem (it's a problem) must be specified to optimize")

        if self.blackboard.max_capacity is None:
            raise AttributeError("No max_capacity, must be specified to optimize")

        return True

    def process(self):

        solver.optimize(
                solution = self.blackboard.solution,
                max_execution_time=int(self.blackboard.time_limit/2),
                problem=self.blackboard.problem,
                groups_max_capacity = self.blackboard.max_capacity
        )

