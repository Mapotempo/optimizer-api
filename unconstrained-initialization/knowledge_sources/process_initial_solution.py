#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy
from sklearn.cluster import KMeans, AgglomerativeClustering, OPTICS, SpectralClustering, MiniBatchKMeans, DBSCAN
from fastvrpy.core.solutions import cvrptw



class ProcessInitialSolution(AbstractKnowledgeSource):
    """
    Process initial solution
    """
    def verify(self):

        if self.blackboard.paths is None:
            raise AttributeError("Paths are None, not possible to initialize a solution")
        if not isinstance(self.blackboard.paths, numpy.ndarray):
            raise AttributeError("Paths are not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.cost_time_multiplier is None:
            raise AttributeError("Cost time multiplier vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.cost_time_multiplier, numpy.ndarray):
            raise AttributeError("Cost time multplier vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.cost_time_multiplier.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of cost time multiplier vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.cost_distance_multiplier is None:
            raise AttributeError("Cost distance multiplier vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.cost_distance_multiplier, numpy.ndarray):
            raise AttributeError("Cost distance multiplier vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.cost_distance_multiplier.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of cost distance multiplier vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicle_capacities is None:
            raise AttributeError("Capacity vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicle_capacities, numpy.ndarray):
            raise AttributeError("Capacity vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicle_capacities.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of Capacity vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicles_TW_starts is None:
            raise AttributeError("Vehicle TW_Starts vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicles_TW_starts, numpy.ndarray):
            raise AttributeError("Vehicle TW_Starts vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicles_TW_starts.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of Vehicle TW_Starts vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicles_TW_ends is None:
            raise AttributeError("Vehicle TW_Ends vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicles_TW_ends, numpy.ndarray):
            raise AttributeError("Vehicle TW_Ends vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicles_TW_ends.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of Vehicle TW_Ends vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicles_distance_max is None:
            raise AttributeError("vehicles_distance_max vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicles_distance_max, numpy.ndarray):
            raise AttributeError("vehicles_distance_max vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicles_distance_max.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of vehicles_distance_max vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicles_fixed_costs is None:
            raise AttributeError("vehicles_fixed_costs vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicles_fixed_costs, numpy.ndarray):
            raise AttributeError("vehicles_fixed_costs vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicles_fixed_costs.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of vehicles_fixed_costs vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.vehicles_overload_multiplier is None:
            raise AttributeError("vehicles_overload_multiplier vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.vehicles_overload_multiplier, numpy.ndarray):
            raise AttributeError("vehicles_overload_multiplier vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.vehicles_overload_multiplier.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of vehicles_overload_multiplier vector is not equal to the number of vehicles, not possible to initialize a solution")
        if self.blackboard.previous_vehicle is None:
            raise AttributeError("previous_vehicle vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.previous_vehicle, numpy.ndarray):
            raise AttributeError("previous_vehicle vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.previous_vehicle.shape[0] != self.blackboard.num_vehicle :
            raise AttributeError("Lengh of previous_vehicle vector is not equal to the number of vehicles, not possible to initialize a solution")

        if self.blackboard.start_tw is None:
            raise AttributeError("start_tw vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.start_tw, numpy.ndarray):
            raise AttributeError("start_tw vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.start_tw.shape[0] != self.blackboard.size :
            raise AttributeError("Lengh of start_tw vector is not equal to the number of services, not possible to initialize a solution")

        if self.blackboard.end_tw is None:
            raise AttributeError("end_tw vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.end_tw, numpy.ndarray):
            raise AttributeError("end_tw vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.end_tw.shape[0] != self.blackboard.size :
            raise AttributeError("Lengh of end_tw vector is not equal to the number of services, not possible to initialize a solution")

        if self.blackboard.durations is None:
            raise AttributeError("durations vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.durations, numpy.ndarray):
            raise AttributeError("durations vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.durations.shape[0] != self.blackboard.size :
            raise AttributeError("Lengh of durations vector is not equal to the number of services, not possible to initialize a solution")

        if self.blackboard.setup_durations is None:
            raise AttributeError("setup_durations vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.setup_durations, numpy.ndarray):
            raise AttributeError("setup_durations vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.setup_durations.shape[0] != self.blackboard.size :
            raise AttributeError("Lengh of setup_durations vector is not equal to the number of services, not possible to initialize a solution")

        if self.blackboard.services_volumes is None:
            raise AttributeError("services_volume vector is None, not possible to initialize a solution")
        if not isinstance(self.blackboard.services_volumes, numpy.ndarray):
            raise AttributeError("services_volume vector is not of type numpy.array, not possible to initialize a solution")
        if self.blackboard.services_volumes.shape[0] != self.blackboard.size :
            raise AttributeError("Lengh of services_volume vector is not equal to the number of services, not possible to initialize a solution")

        return True

    def process(self):
        self.blackboard.solution = cvrptw.CVRPTW(
            self.blackboard.paths,
            self.blackboard.distance_matrices,
            self.blackboard.time_matrices,
            self.blackboard.start_tw,
            self.blackboard.end_tw,
            self.blackboard.durations,
            self.blackboard.setup_durations,
            self.blackboard.services_volumes,
            self.blackboard.cost_distance_multiplier,
            self.blackboard.cost_time_multiplier,
            self.blackboard.vehicle_capacities,
            self.blackboard.previous_vehicle,
            self.blackboard.vehicles_distance_max,
            self.blackboard.vehicles_fixed_costs,
            self.blackboard.vehicles_overload_multiplier,
            self.blackboard.vehicles_TW_starts,
            self.blackboard.vehicles_TW_ends,
            self.blackboard.vehicles_matrix_index,
            self.blackboard.vehicle_start_index,
            self.blackboard.vehicle_end_index,
            None,
            self.blackboard.num_units
        )
