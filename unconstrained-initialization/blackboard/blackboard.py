

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
        self.solution = None
        self.time_limit = None
        self.instance = None
        self.output_file = None
        self.problem = None
        self.max_capacity = None
        self.distance_matrices = None
        self.time_matrices = None
        self.start_tw = None
        self.end_tw = None
        self.durations = None
        self.setup_durations = None
        self.services_volume = None
        self.size = None
        self.num_vehicle = None
        self.max_capacity = None
        self.cost_time_multiplier = None
        self.cost_distance_multiplier = None
        self.vehicle_capacities = None
        self.vehicles_TW_starts = None
        self.vehicles_TW_ends = None
        self.vehicles_distance_max = None
        self.vehicles_fixed_costs = None
        self.vehicles_overload_multiplier = None
        self.previous_vehicle = None
        self.paths = None
        self.vehicle_start_index = None
        self.vehicle_end_index = None
        self.service_matrix_index = None
        self.num_service = None
        self.service_id_to_index_in_problem = None
        self.service_sticky_vehicles = None
        self.force_start = None

    def add_knowledge_source(self, knowledge_source):
        """Adds a new knowlegde source to the blackboard

        CAUTION : The user does not need to make any changes in this function.

        Attributes
        ----------
            knowledge_source (knowledge source): knowledge source to be added
        """
        self.knowledge_sources.append(knowledge_source)
