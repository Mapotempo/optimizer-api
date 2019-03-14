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
require './test/test_helper'

class HeuristicTest < Minitest::Test

  def test_not_allowing_partial_affectation
    vrp = VRP.scheduling_seq_timewindows
    vrp[:vehicles].first[:sequence_timewindows] = [{
      start: 28800,
      end: 54000,
      day_index: 0
    }, {
      start: 28800,
      end: 54000,
      day_index: 1
    }, {
      start: 28800,
      end: 54000,
      day_index: 3
    }]
    vrp[:services] = [vrp[:services].first]
    vrp[:services].first[:visits_number] = 4
    vrp[:configuration][:resolution][:allow_partial_assignment] = false
    vrp[:configuration][:schedule] = {
      range_indices: {
        start: 0,
        end: 3
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools] }}, FCT.create(vrp), nil)

    assert_equal 4, result[:unassigned].size
    assert result[:unassigned].all?{ |unassigned| unassigned[:reason].include?('Only partial assignment') }
  end

  def test_max_ride_time
    vrp = VRP.scheduling
    vrp[:matrices] = [{
      id: 'matrix_0',
      time: [
        [0, 2, 5, 1],
        [1, 0, 5, 3],
        [5, 5, 0, 5],
        [1, 2, 5, 0]
      ]
    }]
    vrp[:vehicles].first[:maximum_ride_time] = 4

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools]}}, FCT.create(vrp), nil)
    assert result
    assert_equal 2, result[:routes].find{ |route| route[:activities].collect{ |stop| stop[:point_id] }.include?('point_2') }[:activities].size
  end

  def test_max_ride_distance
    vrp = VRP.scheduling
    vrp[:matrices] = [{
      id: 'matrix_0',
      time: [
        [0, 2, 1, 5],
        [1, 0, 3, 5],
        [1, 2, 0, 5],
        [5, 5, 5, 0]
      ],
      distance: [
        [0, 1, 5, 1],
        [1, 0, 5, 1],
        [5, 5, 0, 5],
        [1, 1, 5, 0]
      ]
    }]
    vrp[:vehicles].first[:maximum_ride_distance] = 4

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:ortools]}}, FCT.create(vrp), nil)
    assert result
    assert_equal 2, result[:routes].find{ |route| route[:activities].collect{ |stop| stop[:point_id] }.include?('point_2') }[:activities].size
  end

  def test_duration_with_heuristic
    vrp = VRP.scheduling
    vrp[:vehicles].first[:duration] = 6

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(vrp), nil)
    assert result
    assert result[:routes].none?{ |route| route[:activities].collect{ |stop| stop[:departure_time].to_i - stop[:begin_time].to_i + stop[:travel_time].to_i }.sum > 6 }
  end

  def test_heuristic_called_with_first_sol_param
    vrp = VRP.scheduling
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(vrp), nil)
    assert result[:solvers].include?('heuristic')
  end

  def test_visit_every_day
    problem = VRP.scheduling
    problem[:services].first[:visits_number] = 10
    problem[:services].first[:minimum_lapse] = 1
    problem[:configuration][:schedule] = {
      range_indices: {
        start: 0,
        end: 10
      }
    }

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert result[:routes].none?{ |r| r[:activities].collect{ |a| a[:point_id] }.size > r[:activities].collect{ |a| a[:point_id] }.uniq.size }

    problem[:configuration][:resolution][:allow_partial_assignment] = false
    problem[:configuration][:schedule] = {
      range_indices: {
        start: 0,
        end: 5
      }
    }
    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert_equal 10, result[:unassigned].size
  end

  def test_visits_number_0
    problem = VRP.scheduling
    problem[:services].first[:visits_number] = 0

    result = OptimizerWrapper.wrapper_vrp('demo', {services: {vrp: [:demo]}}, FCT.create(problem), nil)
    assert result[:unassigned].first[:service_id] == 'service_1_0_0'
  end
end
