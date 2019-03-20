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
require './optimizer_wrapper.rb'

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

    def self.variate_service_vrp(service_vrp, i)
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
      service_vrp[:vrp][:restitution_allow_empty_result] = true

      service_vrp
    end

    def self.edit_service_vrp(service_vrp, heuristic)
      service_vrp[:vrp][:preprocessing_first_solution_strategy] = [verified(heuristic)]
      service_vrp[:vrp][:restitution_allow_empty_result] = true

      service_vrp
    end

    def self.collect_heuristics(vrp, first_solution_strategy)
      if first_solution_strategy.first == 'self_selection'
        mandatory_heuristic = select_best_heuristic(vrp)
        if vrp[:vehicles].any?{ |vehicle| vehicle[:force_start] || vehicle[:shift_preference] && vehicle[:shift_preference] == 'force_start' }
          [mandatory_heuristic, verified('local_cheapest_insertion'), verified('global_cheapest_arc')]
        elsif mandatory_heuristic == 'savings'
          [mandatory_heuristic, verified('global_cheapest_arc'), verified('local_cheapest_insertion')]
        elsif mandatory_heuristic == 'parallel_cheapest_insertion'
          [mandatory_heuristic, verified('global_cheapest_arc'), verified('local_cheapest_insertion')]
        else
          [mandatory_heuristic]
        end
      else
        first_solution_strategy
      end
    end

    def self.expand(service_vrps)
      several_service_vrps = several_solutions(service_vrps)
      reduced_service_vrps = service_vrps - service_vrps.select{ |service_vrp| service_vrp[:vrp][:resolution_several_solutions] }.compact
      batched_service_vrps = reduced_service_vrps.collect{ |service_vrp| batch_heuristic(service_vrp) if service_vrp[:vrp][:resolution_batch_heuristic] }.compact
      untouched_service_vrps = service_vrps -
                               service_vrps.select{ |service_vrp| service_vrp[:vrp][:resolution_several_solutions] } -
                               service_vrps.select{ |service_vrp| service_vrp[:vrp][:resolution_batch_heuristic] }
      [untouched_service_vrps, (several_service_vrps + batched_service_vrps) || []]
    end

    def self.custom_heuristics(service, vrp, block)
      service_vrp = { vrp: vrp, service: service }
      if vrp.preprocessing_first_solution_strategy && vrp.preprocessing_first_solution_strategy.include?('assemble_heuristic')
        Interpreters::Assemble.assemble_heuristic([service_vrp], block)
      elsif vrp.preprocessing_first_solution_strategy && !vrp.preprocessing_first_solution_strategy.include?('periodic')
        find_best_heuristic(service_vrp)
      else
        service_vrp
      end
    end

    def self.batch_heuristic(service_vrp, custom_heuristics = nil)
      (custom_heuristics || OptimizerWrapper::HEURISTICS).collect{ |heuristic|
        edit_service_vrp(Marshal::load(Marshal.dump(service_vrp)), heuristic)
      }
    end

    def self.several_solutions(service_vrps)
      service_vrps.select{ |service_vrp| service_vrp[:vrp][:resolution_several_solutions] }.collect{ |service_vrp|
        (0..service_vrp[:vrp][:resolution_several_solutions]).collect{ |i|
          variate_service_vrp(Marshal::load(Marshal.dump(service_vrp)), i)
        }
      }.flatten.compact
    end

    def self.find_best_heuristic(service_vrp)
      vrp = service_vrp[:vrp]
      strategies = vrp.preprocessing_first_solution_strategy
      custom_heuristics = collect_heuristics(vrp, strategies)
      if custom_heuristics.size > 1
        batched_service_vrps = batch_heuristic(service_vrp, custom_heuristics)
        times = []
        first_results = batched_service_vrps.collect{ |s_vrp|
          s_vrp[:vrp][:resolution_batch_heuristic] = true
          s_vrp[:vrp][:resolution_initial_time_out] = nil
          s_vrp[:vrp][:resolution_min_duration] = nil
          s_vrp[:vrp][:resolution_duration] = (service_vrp[:vrp][:resolution_duration].to_f / custom_heuristics.size).floor
          heuristic_solution = OptimizerWrapper.solve([s_vrp])
          times << (heuristic_solution && heuristic_solution[:elapsed] || 0)
          heuristic_solution
        }
        raise RuntimeError.new('No solution found') if first_results.all?{ |res| res.nil? }
        synthesis = []
        first_results.each_with_index{ |result, i|
          synthesis << {
            heuristic: batched_service_vrps[i][:vrp][:preprocessing_first_solution_strategy].first,
            quality: result.nil? ? nil : result[:cost].to_i * Math.sqrt([1, result[:unassigned].size].max),
            finished: !result.nil?,
            used: false,
            cost: result ? result[:cost] : nil,
            time_spent: times[i],
            solution: result
          }
        }
        sorted_heuristics = synthesis.sort_by{ |element| element[:quality].nil? ? synthesis.collect{ |data| data[:quality] }.compact.max * 10 : element[:quality] }
        best_heuristic = if sorted_heuristics[0][:heuristic] == 1 && sorted_heuristics[0][:quality] == sorted_heuristics[1][:quality]
                            sorted_heuristics[1][:heuristic]
                          else
                            sorted_heuristics[0][:heuristic]
                          end

        synthesis.find{ |heur| heur[:heuristic] == best_heuristic }[:used] = true

        vrp.preprocessing_heuristic_result = synthesis.find{ |heur| heur[:heuristic] == best_heuristic }[:solution]
        vrp.preprocessing_heuristic_result[:solvers].each{ |solver|
          solver = 'preprocessing_' + solver
        }
        synthesis.each{ |synth| synth.delete(:solution) }
        vrp.resolution_batch_heuristic = nil
        vrp.preprocessing_first_solution_strategy = [best_heuristic]
        vrp[:preprocessing_heuristic_synthesis] = synthesis
        vrp.resolution_duration = vrp.resolution_duration ? (vrp.resolution_duration - times.sum).floor : nil
      else
        vrp.preprocessing_first_solution_strategy = custom_heuristics
      end
      service_vrp
    end

    def self.select_best_heuristic(vrp)
      vehicles = vrp[:vehicles] || []
      services = vrp[:services] || []
      shipments = vrp[:shipments] || []

      loop_route = vehicles.any?{ |vehicle|
        if (vehicle.start_point_id.nil? || vehicle.end_point_id.nil?) && (vehicle.start_point.nil? || vehicle.end_point.nil?)
          true
        else
          start_point_id = vehicle[:start_point_id]
          start_point = vrp.points.find{ |pt| pt[:id] == start_point_id }
          end_point_id = vehicle[:end_point_id]
          end_point = vrp.points.find{ |pt| pt[:id] == end_point_id }

          start_point_id == end_point_id ||
          start_point[:location] && end_point[:location] && start_point[:location][:lat] == end_point[:location][:lat] && start_point[:location][:lon] == end_point[:location][:lon] ||
          vrp[:matrices] && start_point[:matrix_index] && end_point[:matrix_index] && vrp[:matrices].all?{ |matrix| matrix[:time] && matrix[:time][start_point[:matrix_index]][end_point[:matrix_index]] == 0 }
        end
      }
      size_mtws = services.select{ |service| service[:timewindows].to_a.size > 1 }.size
      size_rest = vehicles.collect{ |vehicle| vehicle[:rests].to_a.size }.sum
      unique_configuration = vehicles.collect{ |vehicle| vehicle[:router_mode] }.uniq.size == 1 && vehicles.collect{ |vehicle| vehicle[:router_dimension] }.uniq.size == 1 &&
                             vehicles.collect{ |vehicle| vehicle[:start_point_id] }.uniq.size == 1 && vehicles.collect{ |vehicle| vehicle[:end_point_id] }.uniq.size == 1

      if vehicles.any?{ |vehicle| vehicle[:overall_duration] }
        verified('christofides')
      elsif vehicles.any?{ |vehicle| vehicle[:force_start] || vehicle[:shift_preference] && vehicle[:shift_preference] == 'force_start' }
        verified('path_cheapest_arc')
      elsif loop_route && unique_configuration &&
            (vehicles.any?{ |vehicle| vehicle[:duration] } && vehicles.size == 1 || size_mtws.to_f / (services.collect{ |service| service[:visits_number] }.sum + shipments.size * 2) > 0.2 && size_rest.zero?)
        verified('global_cheapest_arc')
      elsif vehicles.size == 1 && size_rest > 0 || !shipments.empty? || size_mtws > 0
        verified('local_cheapest_insertion')
      elsif size_rest.zero? && loop_route && unique_configuration && vehicles.size < 10 && vehicles.none?{ |vehicle| vehicle[:duration] }
        verified('savings')
      elsif size_rest > 0 || unique_configuration || loop_route
        verified('parallel_cheapest_insertion')
      else
        verified('first_unbound')
      end
    end

    def self.verified(heuristic)
      if OptimizerWrapper::HEURISTICS.include?(heuristic)
        heuristic
      else
        raise StandardError.new('Unconsistent first solution strategy used internally')
      end
    end
  end
end
