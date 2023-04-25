#base imports
from knowledge_sources.abstract_knowledge_source import AbstractKnowledgeSource
import logging as log
from pathlib import Path
log = log.getLogger(Path(__file__).stem)

#KS imports
import numpy

def tw_select(solution, service, start):
    tw_index_selected = 0
    for tw_index,tw in enumerate(solution.start_time_windows[service]):
        if (solution.end_time_windows[service][tw_index] >= start) and (solution.start_time_windows[service][tw_index] <= start):
            tw_index_selected = tw_index
            break
    return tw_index_selected

def service_is_late(solution, service, start):
    tw_index_selected = tw_select(solution, service, start)
    return start > solution.end_time_windows[service][tw_index_selected]

def service_is_early(solution, service, start):
    check_if_service_is_early = lambda tw_start : tw_start > start
    early = all(check_if_service_is_early(tw_start) for tw_start in solution.start_time_windows[service])
    return early

class PrintKpis(AbstractKnowledgeSource):
    """
    Create all services attributes from problem
    """

    def verify(self):

        if self.blackboard.solution is None:
            raise AttributeError("No solution... Can't print KPIS of nothing")

        return True

    def process(self):
        solution = self.blackboard.solution
        early = 0
        lates = 0
        cumul = 0
        max_late = 0
        overloads = [0 for i in range(solution.num_units)]
        vehicle_late = 0
        vehicle_late_time = 0
        vehicle_over_distance = 0
        total_travel_distance = 0
        total_travel_time = 0

        for vehicle in range(solution.num_vehicles):
            total_travel_distance += solution.distances[vehicle]
            total_travel_time += solution.travel_times[vehicle]
            if solution.vehicle_max_distance[vehicle] > -1 and solution.distances[vehicle] > solution.vehicle_max_distance[vehicle] :
                vehicle_over_distance += 1
            for unit_index in range(solution.num_units):
                if solution.vehicle_capacities[vehicle,unit_index] > -1 and solution.vehicle_occupancies[vehicle, unit_index] > solution.vehicle_capacities[vehicle, unit_index]:
                    overloads[unit_index] += 1
            if solution.vehicle_end_time_window[vehicle] > -1 and solution.vehicle_ends[vehicle] > solution.vehicle_end_time_window[vehicle]:
                vehicle_late += 1
                vehicle_late_time += solution.vehicle_ends[vehicle] - solution.vehicle_end_time_window[vehicle]

            for point in range(solution.vehicle_num_services[vehicle]):
                start = solution.starts[vehicle][point+1]
                service = solution.paths[vehicle][point]


                s_tw = solution.start_time_windows[service,0]
                e_tw = solution.max_end_time_windows[service]

                if start < s_tw :
                    early += 1
                    cumul +=  s_tw - start
                elif e_tw > -1 and start > e_tw:
                    #print(start, s_tw, e_tw, vehicle, point)
                    lates += 1
                    cumul += start - e_tw
                    if start - e_tw > max_late:
                        max_late = start - e_tw

        vehicle_mean_late = vehicle_late_time/60/vehicle_late if vehicle_late > 0 else 0

        log.info(f"Print KPIs")
        log.info(f"SOLUTION COST {solution.total_cost}" )
        log.info(f"Travel distance : {total_travel_distance/1000} kilometers" )
        log.info(f"Travel time : {total_travel_time/3600} hours" )
        log.debug(f"Partial costs \n {numpy.array(solution.costs)}")
        log.debug(f"Number services \n {numpy.array(solution.vehicle_num_services)}")
        log.info(f"Vehicle distance violations {vehicle_over_distance}")
        log.info(f"Vehicle overloads {overloads}")
        log.info(f"{vehicle_late} vehicles with working hours overflow (mean {vehicle_mean_late} minutes)" )
        log.info(f"Too early (MUST be 0 by construction) {early}")
        log.info(f"Too lates {lates}" )
        log.info(f"Total late {cumul}")
        log.info(f"Worse late {max_late/60}")
