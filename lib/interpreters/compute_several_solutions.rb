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
      matrix
    end

    def self.generate_matrix(vrp)
      matrix = (0..vrp.matrices[0][:time].size - 1).collect{ |i|
        (0..vrp.matrices[0][:time][i].size - 1).collect{ |j|
          vrp.matrices[0][:time][i][j] + (rand(3).zero? ? -1 : 1) * vrp.matrices[0][:time][i][j] * rand(vrp.resolution_variation_ratio) / 100
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
      vrp.compute_matrix if vrp.matrices.empty?

      if i.zero? || !service_vrp[:vrp].resolution_variation_ratio
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
      service_vrp[:vrp].resolution_several_solutions = 1

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

        heuristic_list =
          if vrp[:vehicles].any?{ |vehicle| vehicle[:force_start] || vehicle[:shift_preference].to_s == 'force_start' }
            [mandatory_heuristic, verified('local_cheapest_insertion'), verified('global_cheapest_arc')]
          elsif mandatory_heuristic == 'savings'
            [mandatory_heuristic, verified('global_cheapest_arc'), verified('local_cheapest_insertion')]
          elsif mandatory_heuristic == 'parallel_cheapest_insertion'
            [mandatory_heuristic, verified('global_cheapest_arc'), verified('local_cheapest_insertion')]
          else
            [mandatory_heuristic]
          end

        heuristic_list |= ['savings'] if vrp.vehicles.collect{ |vehicle| vehicle[:rests].to_a.size }.sum.positive? # while waiting for self_selection improve
        heuristic_list
      else
        first_solution_strategy
      end
    end

    def self.expand_several_solutions(service_vrps)
      several_solutions(service_vrps).flat_map{ |each_service_vrps|
        if service_vrps[0][:vrp].resolution_batch_heuristic
          batch_heuristic(each_service_vrps)
        else
          [each_service_vrps]
        end
      }
    end

    def self.expand_repeat(service_vrp)
      return [service_vrp] if service_vrp[:vrp].resolution_repetition < 1

      repeated_service_vrp = [service_vrp]

      (service_vrp[:vrp].resolution_repetition - 1).times{
        sub_vrp = Marshal.load(Marshal.dump(service_vrp))
        sub_vrp[:vrp].resolution_repetition = 1
        sub_vrp[:vrp].preprocessing_partitions.each{ |partition| partition[:restarts] = [partition[:restarts], 5].compact.min } # change restarts ?
        repeated_service_vrp << sub_vrp
      }

      repeated_service_vrp
    end

    def self.custom_heuristics(service, vrp, block = nil)
      service_vrp = { vrp: vrp, service: service }

      preprocessing_fss = vrp.preprocessing_first_solution_strategy

      return service_vrp if service == :vroom ||
                            preprocessing_fss.empty? ||
                            preprocessing_fss.include?('periodic') ||
                            (preprocessing_fss.size == 1 && preprocessing_fss != ['self_selection'])

      block&.call(nil, nil, nil, "process heuristic choice : #{preprocessing_fss}", nil, nil, nil)

      find_best_heuristic(service_vrp)
    end

    def self.batch_heuristic(service_vrps, custom_heuristics = nil)
      (custom_heuristics || OptimizerWrapper::HEURISTICS).collect{ |heuristic|
        service_vrps.collect{ |service_vrp|
          edit_service_vrp(Marshal.load(Marshal.dump(service_vrp)), heuristic)
        }
      }
    end

    def self.several_solutions(service_vrps)
      several_service_vrps = [service_vrps] # First one is the original vrp

      (service_vrps[0][:vrp].resolution_several_solutions - 1).times{ |i|
        several_service_vrps << service_vrps.collect{ |service_vrp|
          variate_service_vrp(Marshal.load(Marshal.dump(service_vrp)), i)
        }
      }

      several_service_vrps
    end

    def self.find_best_heuristic(service_vrp)
      vrp = service_vrp[:vrp]
      custom_heuristics = collect_heuristics(vrp, vrp.preprocessing_first_solution_strategy)
      if custom_heuristics.size > 1
        log '---> find_best_heuristic'
        tic = Time.now
        percent_allocated_to_heur_selection = 0.3 # spend at most 30% of the total time for heuristic selection
        total_time_allocated_for_heuristic_selection = service_vrp[:vrp].resolution_duration.to_f * percent_allocated_to_heur_selection
        time_for_each_heuristic = (total_time_allocated_for_heuristic_selection / custom_heuristics.size).to_i

        times = []
        first_results = custom_heuristics.collect{ |heuristic|
          s_vrp = Marshal.load(Marshal.dump(service_vrp))
          s_vrp[:vrp].preprocessing_first_solution_strategy = [verified(heuristic)]
          s_vrp[:vrp].restitution_allow_empty_result = true
          s_vrp[:vrp].resolution_batch_heuristic = true
          s_vrp[:vrp].resolution_initial_time_out = nil
          s_vrp[:vrp].resolution_minimum_duration = nil
          s_vrp[:vrp].resolution_duration = [time_for_each_heuristic, 300000].min # no more than 5 min for single heur
          heuristic_solution = OptimizerWrapper.solve(s_vrp)
          times << (heuristic_solution && heuristic_solution[:elapsed] || 0)
          heuristic_solution
        }

        raise RuntimeError, 'No solution found during heuristic selection' if first_results.all?(&:nil?)

        synthesis = []
        first_results.each_with_index{ |result, i|
          synthesis << {
            heuristic: custom_heuristics[i],
            quality: result.nil? ? nil : result[:cost].to_i + (times[i] / 1000).to_i,
            used: false,
            cost: result ? result[:cost] : nil,
            time_spent: times[i],
            solution: result
          }
        }
        sorted_heuristics = synthesis.sort_by{ |element| element[:quality].nil? ? synthesis.collect{ |data| data[:quality] }.compact.max * 10 : element[:quality] }

        best_heuristic = sorted_heuristics[0][:heuristic]

        synthesis.find{ |heur| heur[:heuristic] == best_heuristic }[:used] = true

        vrp.preprocessing_heuristic_result = synthesis.find{ |heur| heur[:heuristic] == best_heuristic }[:solution]
        vrp.preprocessing_heuristic_result[:solvers].each{ |solver|
          solver = 'preprocessing_' + solver
        }
        synthesis.each{ |synth| synth.delete(:solution) }
        vrp.resolution_batch_heuristic = nil
        vrp.preprocessing_first_solution_strategy = [best_heuristic]
        vrp.preprocessing_heuristic_synthesis = synthesis
        vrp.resolution_duration = vrp.resolution_duration ? [(vrp.resolution_duration.to_f * (1 - percent_allocated_to_heur_selection)).round, 1000].max : nil
        log "<--- find_best_heuristic elapsed: #{Time.now - tic}sec selected heuristic: #{best_heuristic}"
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
          start_point = vehicle.start_point
          end_point = vehicle.end_point

          vehicle.start_point_id == vehicle.end_point_id ||
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
      elsif vehicles.size == 1 && size_rest.positive? || !shipments.empty? || size_mtws > 0
        verified('local_cheapest_insertion')
      elsif loop_route && unique_configuration && vehicles.size < 10 && vehicles.none?{ |vehicle| vehicle[:duration] }
        verified('savings')
      elsif size_rest.positive? || unique_configuration || loop_route
        verified('parallel_cheapest_insertion')
      else
        verified('parallel_cheapest_insertion')
      end
    end

    def self.verified(heuristic)
      if OptimizerWrapper::HEURISTICS.include?(heuristic)
        heuristic
      else
        log "Unknown heuristic #{heuristic}", level: :fatal
        raise StandardError, 'Unconsistent first solution strategy used internally'
      end
    end
  end
end
