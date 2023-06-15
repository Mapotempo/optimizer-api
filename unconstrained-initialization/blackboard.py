

# Result class that stores all results for futher calculations
class Blackboard(object):
    """Blackboard class that stores data and knowledge sources

    The knowledge sources will always be stored in a list that should not be altered by the user.
    The user should however add the specific data structures needed by the model to run in the constructor.

    Attributes
    ----------
        knowledge_sources: List of knowledge sources
    """
    def __init__(self):

        # Do not alter this line
        self.knowledge_sources = []

        # Specific data structures needed by the model to be completed by the user
        #...


    def add_knowledge_source(self, knowledge_source):
        """Adds a new knowlegde source to the blackboard

        CAUTION : The user does not need to make any changes in this function.

        Attributes
        ----------
            knowledge_source (knowledge source): knowledge source to be added
        """
        self.knowledge_sources.append(knowledge_source)