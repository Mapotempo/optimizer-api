
import abc

class AbstractKnowledgeSource(object):
    """Abstract class/interface to ensure that all KnowledgeSource classes have the same methods to be invoked

    CAUTION : The user does not need to make any changes in this file.

    Attributes
    ----------
        balckboard (Blackboard): blackboard containing data and the knowledge sources

    Raises
    ------
        NotImplementedError: error raised if the Verify method has not been implemented in the subclass
        NotImplementedError: error raised if the Process method has not been implemented in the subclass
    """
    __metaclass__ = abc.ABCMeta

    def __init__(self, blackboard):
        self.blackboard = blackboard
 
    
    @abc.abstractmethod
    def verify(self) -> bool:
        """Verify that the blackboard has all the data needed to run this knowledge source

        Returns
        ------
            bool : True if the knowledge source can be applied, else False

        Raises
        ------
            NotImplementedError: error raised if the Verify method has not been implemented in the subclass
            Any Other Exception: to descripbe why the knowledge source can't run
        """
        raise NotImplementedError('Must provide implementation in subclass.')

    @abc.abstractmethod
    def process(self) -> None:
        """Run the process the method on the blackboard

        Raises
        ------
            NotImplementedError: error raised if the Process method has not been implemented in the subclass
        """
        raise NotImplementedError('Must provide implementation in subclass.')