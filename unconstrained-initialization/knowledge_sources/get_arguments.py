#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import sys

class GetArguments(AbstractKnowledgeSource):
    """
    Get input file (instance of the problem) and output file of the algorithm
    """

    def verify(self):

        # Check arguments exists
        needed_arguments = [
            "-time_limit_in_ms",
            "-instance_file",
            "-solution_file",
        ]
        args = sys.argv[1:]

        for needed_argument in needed_arguments:
            if needed_argument not in args:
                raise AttributeError(f"{needed_argument} nor specified")

        return True

    def process(self):
        #Get arguments
        args = sys.argv[1:]

        #Get time limit
        index = args.index("-time_limit_in_ms")
        self.blackboard.time_limit = int(args[index + 1]) / 1000

        index = args.index("-instance_file")
        self.blackboard.instance = args[index + 1]

        index = args.index("-solution_file")
        self.blackboard.output_file = args[index + 1]
        print("output_file : ",  self.blackboard.output_file)
