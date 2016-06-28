# Copyright © Mapotempo, 2016
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

require 'ai4r'

module Ai4r
  module Clusterers
    class CompleteLinkageMaxDistance < CompleteLinkage
      # Monkey patch : limit by inter-cluster distance in place of clusters number
      def build(data_set, max_distance)
        @data_set = data_set

        @index_clusters = create_initial_index_clusters
        create_distance_matrix(data_set)
        while @index_clusters.length > 1
          ci, cj = get_closest_clusters(@index_clusters)
          if read_distance_matrix(ci, cj) > max_distance
            break
          end
          update_distance_matrix(ci, cj)
          merge_clusters(ci, cj, @index_clusters)
        end
        @clusters = build_clusters_from_index_clusters @index_clusters

        self
      end
    end
  end
end
