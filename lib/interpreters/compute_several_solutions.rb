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
    def self.duplicate_service_vrp(service_vrp, vrp_hash = nil)
      service_vrp.map{ |key, value|
        if key == :vrp
          vrp_hash ||= JSON.parse(value.to_json, symbolize_names: true)
          value = Models::Vrp.create(vrp_hash)
        end
        [key, value]
      }.to_h
    end

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
          vrp.matrices[0][:time][i][j] + (rand(3).zero? ? -1 : 1) * vrp.matrices[0][:time][i][j] * rand(vrp.configuration.resolution.variation_ratio) / 100
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

      if i.zero? || !service_vrp[:vrp].configuration.resolution.variation_ratio
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
      service_vrp[:vrp].configuration.restitution.allow_empty_result = true
      service_vrp[:vrp].configuration.resolution.several_solutions = 1

      service_vrp
    end

    def self.edit_service_vrp(service_vrp, heuristic)
      service_vrp[:vrp].configuration.preprocessing.first_solution_strategy = [verified(heuristic)]
      service_vrp[:vrp].configuration.restitution.allow_empty_result = true

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
            [mandatory_heuristic, verified('global_cheapest_arc')]
          end

        heuristic_list |= ['savings'] if vrp.vehicles.collect{ |vehicle| vehicle[:rests].to_a.size }.sum.positive? # while waiting for self_selection improve
        heuristic_list
      else
        first_solution_strategy
      end
    end

    def self.expand_similar_resolutions(service_vrps)
      several_resolutions(service_vrps).flat_map{ |each_service_vrps|
        if each_service_vrps.first[:vrp].configuration.resolution.batch_heuristic
          batch_heuristic(each_service_vrps)
        else
          [each_service_vrps]
        end
      }
    end

    def self.expand_repetitions(service_vrp)
      return [service_vrp] if service_vrp[:vrp].configuration.resolution.repetition.nil? ||
                              service_vrp[:vrp].configuration.resolution.repetition <= 1
      repeated_service_vrps = [service_vrp]
      vrp_hash = JSON.parse(service_vrp[:vrp].to_json, symbolize_names: true)

      (service_vrp[:vrp].configuration.resolution.repetition - 1).times{
        sub_service_vrp = duplicate_service_vrp(service_vrp, vrp_hash)
        sub_service_vrp[:vrp].configuration.resolution.repetition = 1
        sub_service_vrp[:vrp].configuration.preprocessing.partitions.each{ |partition| partition[:restarts] = [partition[:restarts], 5].compact.min } # change restarts ?
        repeated_service_vrps << sub_service_vrp
      }

      repeated_service_vrps
    end

    def self.custom_heuristics(service, vrp, block = nil)
      service_vrp = { vrp: vrp, service: service }

      preprocessing_fss = vrp.configuration.preprocessing.first_solution_strategy

      return service_vrp if service == :vroom ||
                            preprocessing_fss.empty? ||
                            preprocessing_fss.include?('periodic') ||
                            (preprocessing_fss.size == 1 && preprocessing_fss != ['self_selection'])

      block&.call(nil, nil, nil, "process heuristic choice : #{preprocessing_fss}", nil, nil, nil)

      find_best_heuristic(service_vrp)
    end

    def self.batch_heuristic(service_vrps, custom_heuristics = nil)
      vrp_hash = JSON.parse(service_vrp[:vrp].to_json, symbolize_names: true)
      (custom_heuristics || OptimizerWrapper::HEURISTICS).collect{ |heuristic|
        service_vrps.collect{ |service_vrp|
          edit_service_vrp(duplicate_service_vrp(service_vrp, vrp_hash), heuristic)
        }
      }
    end

    def self.several_resolutions(service_vrps)
      several_service_vrps = [service_vrps]

      (service_vrps.first[:vrp].configuration.resolution.several_solutions - 1).times{ |i|
        several_service_vrps << service_vrps.map{ |service_vrp|
          variate_service_vrp(duplicate_service_vrp(service_vrp), i)
        }
      }

      several_service_vrps
    end

    def self.find_best_heuristic(service_vrp)
      vrp = service_vrp[:vrp]
      custom_heuristics = collect_heuristics(vrp, vrp.configuration.preprocessing.first_solution_strategy)
      if custom_heuristics.size > 1
        log '---> find_best_heuristic'
        tic = Time.now
        percent_allocated_to_heur_selection = 0.3 # spend at most 30% of the total time for heuristic selection
        total_time_allocated_for_heuristic_selection = service_vrp[:vrp].configuration.resolution.duration.to_f * percent_allocated_to_heur_selection
        time_for_each_heuristic = (total_time_allocated_for_heuristic_selection / custom_heuristics.size).to_i

        custom_heuristics << 'supplied_initial_routes' if vrp.routes.any?

        times = []
        vrp_hash = JSON.parse(service_vrp[:vrp].to_json, symbolize_names: true)
        first_results = custom_heuristics.collect{ |heuristic|
          s_vrp = duplicate_service_vrp(service_vrp, vrp_hash)
          if heuristic == 'supplied_initial_routes'
            s_vrp[:vrp].configuration.preprocessing.first_solution_strategy = [verified('global_cheapest_arc')] # fastest for fallback
          else
            s_vrp[:vrp].routes = []
            s_vrp[:vrp].configuration.preprocessing.first_solution_strategy = [verified(heuristic)]
          end
          s_vrp[:vrp].configuration.restitution.allow_empty_result = true
          s_vrp[:vrp].configuration.resolution.batch_heuristic = true
          s_vrp[:vrp].configuration.resolution.minimum_duration = nil
          s_vrp[:vrp].configuration.resolution.duration = [time_for_each_heuristic, 300000].min # no more than 5 min for single heur
          heuristic_solution = OptimizerWrapper.config[:services][s_vrp[:service]].solve(s_vrp[:vrp], nil)
          times << (heuristic_solution && heuristic_solution[:elapsed] || 0)
          heuristic_solution
        }

        raise 'No solution found during heuristic selection' if first_results.all?(&:nil?)

        synthesis = []
        first_results.each_with_index{ |solution, i|
          synthesis << {
            heuristic: custom_heuristics[i],
            # If the cost is 0 we might want to set it to Float::MAX because 0 cost is not possible.
            quality: solution.nil? ? [Float::MAX] : [solution.unassigned_stops&.size.to_i, solution.cost.to_i, times[i]],
            used: false,
            cost: solution ? solution.cost : nil,
            time_spent: times[i],
            solution: solution
          }
        }
        best = synthesis.min_by{ |element| element[:quality] }

        if best[:heuristic] != 'supplied_initial_routes'
          # if another heuristic is the best, use its solution as the initial route
          vrp.routes = best[:solution].routes.collect{ |route|
            mission_ids = route.stops.collect(&:service_id).compact
            next if mission_ids.empty?

            Models::Route.create(vehicle: vrp.vehicles.find{ |v| v.id == route.vehicle_id }, mission_ids: mission_ids)
          }.compact
        end

        best[:used] = true

        vrp.configuration.preprocessing.heuristic_result = best[:solution]
        vrp.configuration.preprocessing.heuristic_result[:solvers].map!{ |solver| "configuration.preprocessing.#{solver}".to_sym }
        synthesis.each{ |synth| synth.delete(:solution) }
        vrp.configuration.resolution.batch_heuristic = nil
        vrp.configuration.preprocessing.first_solution_strategy = best[:heuristic] != 'supplied_initial_routes' ? [verified(best[:heuristic])] : []
        vrp.configuration.preprocessing.heuristic_synthesis = synthesis
        vrp.configuration.resolution.duration = vrp.configuration.resolution.duration ? [(vrp.configuration.resolution.duration.to_f * (1 - percent_allocated_to_heur_selection)).round, 1000].max : nil
        log "<--- find_best_heuristic elapsed: #{Time.now - tic}sec selected heuristic: #{best[:heuristic]}"
      else
        vrp.configuration.preprocessing.first_solution_strategy = custom_heuristics
      end

      service_vrp
    end

    def self.select_best_heuristic(vrp)
      vehicles = vrp.vehicles
      services = vrp.services

      loop_route = vehicles.any?{ |vehicle|
        if (vehicle.start_point.nil? || vehicle.end_point.nil?)
          true
        else
          start_point = vehicle.start_point
          end_point = vehicle.end_point

          vehicle.start_point_id == vehicle.end_point_id ||
            start_point.same_location?(end_point) ||
            vrp.matrices && start_point.matrix_index && end_point.matrix_index &&
              vrp.matrices.all?{ |matrix|
                matrix.time && matrix.time[start_point.matrix_index][end_point.matrix_index] == 0
              }
        end
      }
      size_mtws = services.count{ |service| service.activity.timewindows.size > 1 }
      size_rest = vehicles.sum{ |vehicle| vehicle.rests.size }
      unique_configuration = vehicles.uniq(&:router_mode).size == 1 &&
                             vehicles.uniq(&:router_dimension).size == 1 &&
                             vehicles.uniq(&:start_point_id).size == 1 &&
                             vehicles.uniq(&:end_point_id).size == 1

      # TODO: The conditions below should be reworked
      if vehicles.any?(&:overall_duration)
        verified('christofides')
      elsif vehicles.any?{ |vehicle|
              vehicle.force_start ||
              vehicle.shift_preference && vehicle.shift_preference == 'force_start'
            }
        verified('path_cheapest_arc')
      elsif loop_route && unique_configuration &&
            (vehicles.any?(&:duration) && vehicles.size == 1 ||
            size_mtws.to_f / services.map(&:visits_number).sum > 0.2 && size_rest.zero?)
        verified('global_cheapest_arc')
      elsif vehicles.size == 1 && size_rest.positive? || size_mtws > 0
        verified('local_cheapest_insertion')
      elsif loop_route && unique_configuration && vehicles.size < 10 && vehicles.none?(&:duration)
        verified('savings')
      elsif size_rest.positive? || unique_configuration || loop_route
        verified('parallel_cheapest_insertion')
      else
        verified('parallel_cheapest_insertion')
      end
    end

    def self.verified(heuristic)
      unless OptimizerWrapper::HEURISTICS.include?(heuristic)
        raise StandardError.new("Unknown heuristic : #{heuristic}. Inconsistent first solution strategy used internally")
      end

      heuristic
    end
  end
end
