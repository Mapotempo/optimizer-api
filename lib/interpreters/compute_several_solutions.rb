# Copyright © Mapotempo, 2018
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
module Interpreters
  class SeveralSolutions

    def self.check_triangle_inequality(matrix)
      (0..matrix.size - 1).each{ |i|
        (0..matrix.size - 1).each{ |j|
          (0..matrix[i].size - 1).each{ |k|
            matrix[i][j] = [matrix[i][j], matrix[i][k] + matrix[k][j]].min
          }
        }
      }
      return matrix
    end

    def self.generate_matrix(vrp)
      matrix = (0..vrp.matrices[0][:time].size - 1).collect{ |i|
        (0..vrp.matrices[0][:time][i].size - 1).collect{ |j|
          vrp.matrices[0][:time][i][j] + (rand(3) == 0 ? -1 : 1) * vrp.matrices[0][:time][i][j] * rand(vrp.resolution_variation_ratio)/100
        }
      }
      while (0..matrix.size - 1).any?{ |i|
              (0..matrix[i].size - 1).any?{ |j|
                (0..matrix[i].size - 1).any? { |k|
                  matrix[i][j] > matrix[i][k] + matrix[k][j]
                }
              }
            }
        matrix = check_triangle_inequality(matrix)
      end
      vrp.matrices[0][:value] = matrix
      vrp.matrices
    end

    def self.edit_service_vrp(service_vrp, i)
      vrp = service_vrp[:vrp]
      if vrp.matrices.size == 0
        vrp_need_matrix = OptimizerWrapper.compute_vrp_need_matrix(service_vrp[:vrp])
        service_vrp[:vrp] = OptimizerWrapper.compute_need_matrix(vrp, vrp_need_matrix)
      end

      if i == 0
        service_vrp[:vrp].matrices[0][:value] = vrp.matrices[0][:time]
      else
        service_vrp[:vrp].matrices = generate_matrix(vrp)
      end

      (0..service_vrp[:vrp].vehicles.size - 1).each{ |j|
        service_vrp[:vrp].vehicles[j][:cost_time_multiplier] = 0
        service_vrp[:vrp].vehicles[j][:cost_distance_multiplier] = 0
        service_vrp[:vrp].vehicles[j][:cost_value_multiplier] = 1
      }
      service_vrp[:vrp][:name] << '_' << i.to_s if service_vrp[:vrp][:name]

      service_vrp
    end

    def self.expand(service_vrps)
      heuristic_size = 6

      several_service_vrps = service_vrps.select{ |service_vrp| service_vrp[:vrp][:resolution_several_solutions] }.collect{ |service_vrp|
        variate_service_vrp = (0..service_vrp[:vrp][:resolution_several_solutions]).collect{ |i|
          edit_service_vrp(Marshal::load(Marshal.dump(service_vrp)), i)
        }
        variate_service_vrp
      }.flatten.compact

      several_service_vrps
    end

  end
end
