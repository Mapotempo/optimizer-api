
from blackboard.blackboard import Blackboard
from controller.controller import Controller
import traceback
import os, sys
import logging as log

from knowledge_sources.create_services_attributes_from_problem import CreateServicesAttributesFromProblem
from knowledge_sources.create_vehicles_attributes_from_problem import CreateVehiclesAttributesFromProblem
from knowledge_sources.create_matrices_from_problem import CreateMatricesFromProblem
from knowledge_sources.deserialize_problem import DeserializeProblem
from knowledge_sources.get_arguments import GetArguments
from knowledge_sources.optimize_solution import OptimizeSolution
from knowledge_sources.process_clustering_initial_paths import ProcessClusteringInitialPaths
from knowledge_sources.process_initial_solution import ProcessInitialSolution
from knowledge_sources.create_services_attributes_from_problem import CreateServicesAttributesFromProblem
from knowledge_sources.parse_and_serialize_solution import ParseAndSerializeSolution
from knowledge_sources.print_kpis import PrintKpis
from knowledge_sources.create_dictionnary_index_to_id import CreateDictionnaryIndexId




def main():
    """Main function to run the model
    """
    log_config()
    log.info("----------Start working------------")

    try:
        # Initialize the blackboard
        blackboard = Blackboard()

        # Add the knowledge sources
        blackboard.add_knowledge_source(GetArguments(blackboard))
        blackboard.add_knowledge_source(DeserializeProblem(blackboard))
        blackboard.add_knowledge_source(CreateVehiclesAttributesFromProblem(blackboard))
        blackboard.add_knowledge_source(CreateServicesAttributesFromProblem(blackboard))
        blackboard.add_knowledge_source(CreateDictionnaryIndexId(blackboard))
        blackboard.add_knowledge_source(CreateMatricesFromProblem(blackboard))
        blackboard.add_knowledge_source(ProcessClusteringInitialPaths(blackboard))
        blackboard.add_knowledge_source(ProcessInitialSolution(blackboard))
        blackboard.add_knowledge_source(OptimizeSolution(blackboard))
        blackboard.add_knowledge_source(ParseAndSerializeSolution(blackboard))
        # blackboard.add_knowledge_source(PrintKpis(blackboard))

        # Initialize the controller and run it
        controller = Controller(blackboard)
        controller.run_knowledge_sources()

    except Exception as e:
        exc_type, exc_obj, exc_tb = sys.exc_info()
        error = f"{exc_type.__name__} : {e}\n" + "".join(traceback.format_tb(exc_tb))
        log.critical(error)

    log.info("-----------End working------------")




def log_config():
    """Setup the logger

    The logger will write its output in a new file every day at midnight

    Returns
    -------
    log : logging.getLogger
        Configurated logger to use in all the package

    """

    # Constants
    PATH_TO_LOG = os.path.join(
        os.getcwd(), "init_vrp.log"
    )
    LOG_FORMAT = "%(asctime)s | %(levelname)s\t | %(name)s\t : %(message)s"
    LOGGING_MODE = log.INFO

    #(PATH_TO_LOG, when="midnight", interval=1, encoding="utf8")
    log.basicConfig(filename=PATH_TO_LOG, format=LOG_FORMAT, level=LOGGING_MODE)


if __name__ == '__main__':
    main()
