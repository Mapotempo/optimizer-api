
from blackboard.blackboard import Blackboard
from controller.controller import Controller
import traceback
import os, sys
import logging as log

def main():
    """Main function to run the model
    """
    log.info("----------Start working------------")
    log_config()

    try:
        # Initialize the blackboard
        blackboard = Blackboard()

        # Add the knowledge sources

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