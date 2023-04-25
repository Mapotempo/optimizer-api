import logging as log
log = log.getLogger("controller")

class Controller(object):
    """Controller that handles calling the knowledge sources

    CAUTION : The user does not need to make any changes in this file. 

    Attributes
    ----------
        balckboard (Blackboard): blackboard containing data and the knowledge sources
    """
    
    def __init__(self, blackboard):
        self.blackboard = blackboard

    def run_knowledge_sources(self):
        """For every knowledge source, run the Verify and Process methods
        """
        for knowledge_source in self.blackboard.knowledge_sources:
            ks_name = type(knowledge_source).__name__
            log.info(f"Running knowledge source {ks_name}")

            # Verify that the knowledge source can be executed
            assert knowledge_source.verify()
            log.info(f"Verify {ks_name} : OK -> start processing")

            # Execute the knowledge source
            knowledge_source.process()
            log.info(f"End Processing {ks_name}")