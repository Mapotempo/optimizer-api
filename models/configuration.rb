# Copyright © Mapotempo, 2021
#
# This file is part of Mapotempo.
#
# Mapotempo is free software. You can redistribute it and/or
# modify since you respect the terms of the GNU Affero General
# Public License as published by the Free Software Foundation,
# either version 3 of the License, or (at your option) any later version.
#
# Mapotempo is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the Licenses for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with Mapotempo. If not, see:
# <http://www.gnu.org/licenses/agpl.html>
#
require './models/base'

module Models
  class Configuration < Base
    belongs_to :preprocessing, class_name: 'Models::Preprocessing'
    belongs_to :resolution, class_name: 'Models::Resolution'
    belongs_to :restitution, class_name: 'Models::Restitution'
    belongs_to :schedule, class_name: 'Models::Schedule'
  end

  class Preprocessing < Base
    field :force_cluster, default: false
    field :max_split_size, default: nil
    field :partition_method, default: nil
    field :partition_metric, default: nil
    field :kmeans_centroids, default: nil
    field :cluster_threshold, default: nil
    field :prefer_short_segment, default: false
    field :neighbourhood_size, default: nil
    field :first_solution_strategy, default: []
    field :heuristic_result, default: {} # TODO: do we really need heuristic result inside config ?
    field :heuristic_synthesis, default: nil # TODO: do we really need heuristic synthesis inside config ?
    has_many :partitions, class_name: 'Models::Partition'
  end

  class Resolution < Base
    # The following 7 variables are used for dicho development
    # TODO: Wait for the dev to finish to expose the dicho parameters
    # The last one is on the api in a hidden way
    field :dicho_level_coeff, default: 1.1 # This variable is calculated inside dicho by default (TODO: check if it is really necessary)
    field :dicho_algorithm_vehicle_limit, default: 10
    field :dicho_division_service_limit, default: 100 # This variable needs to corrected using the average number of services per vehicle.
    field :dicho_division_vehicle_limit, default: 3
    field :dicho_exclusion_scaling_angle, default: 38
    field :dicho_exclusion_rate, default: 0.6
    field :dicho_algorithm_service_limit, default: 500 # This variable is exposed in a hidden way for studies

    field :duration, default: nil
    field :total_duration, default: nil
    field :iterations, default: nil
    field :iterations_without_improvment, default: nil
    field :stable_iterations, default: nil
    field :stable_coefficient, default: nil
    field :minimum_duration, default: nil
    field :init_duration, default: nil
    field :time_out_multiplier, default: nil
    field :vehicle_limit, default: nil
    field :solver, default: true
    field :same_point_day, default: false
    field :minimize_days_worked, default: false
    field :allow_partial_assignment, default: true
    field :evaluate_only, default: false
    field :split_number, default: 1
    field :total_split_number, default: 2
    field :several_solutions, default: 1
    field :variation_ratio, default: nil
    field :batch_heuristic, default: false
    field :repetition, default: nil
  end

  class Restitution < Base
    field :geometry, default: []
    field :intermediate_solutions, default: true
    field :csv, default: false
    field :allow_empty_result, default: false
  end

  class Schedule < Base
    field :range_indices, default: nil # extends schedule_range_date
    field :start_date, default: nil
    field :unavailable_days, default: Set[] # extends unavailable_date
    field :months_indices, default: []
  end
end
