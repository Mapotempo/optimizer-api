# Copyright © Mapotempo, 2019
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

# Implementation of
# CONCAVE HULL: A K-NEAREST NEIGHBOURS APPROACH FOR THE COMPUTATION OF THE REGION OCCUPIED BY A SET OF POINTS
# By Adriano Moreira and Maribel Yasmina Santos

module Hull
  def self.get_hull(vector)
    concave_hull(vector, 5) || convex_hull(vector)
  end

  # vector of unique points
  def self.concave_hull(vector, k = 3)
    if vector.size <= 3
      vector
    else
      k = [k, vector.size - 1].min
      self.concave_hull_(vector, k)
    end
  end

  def self.concave_hull_(vector, k = 3)
    if k == vector.size
      log 'ConcaveHull build fail'
      return nil
    end
    kk = [[k, 3].max, vector.size - 1].min # make sure k>=3 and k neighbours can be found
    first_point = vector.min_by{ |i| i[1] } # find min y point
    hull = [first_point] # initialize the hull with the first point
    current_point = first_point
    dataset = vector - [first_point]
    previous_angle = 0
    while (current_point != first_point || hull.size == 1) && !dataset.empty?
      if hull.size == 3
        dataset += [first_point] # add the firstPoint again
      end
      k_nearest_points = nearestpoints(dataset, current_point, kk) # find the nearest neighbours
      # sort the candidates (neighbours) in descending order of right-hand turn
      c_points = k_nearest_points.sort_by{ |point| -angle(point, current_point, previous_angle) }
      its = true
      i = -1
      while its && i < c_points.size - 1 # select the first candidate that does not intersects any of the polygon edges
        i += 1
        last_point = (c_points[i] == first_point) ? 1 : 0
        j = 1
        its = false
        while !its && j < hull.size - last_point
          its = intersect?(hull[-1], c_points[i], hull[-j - 1], hull[-j])
          j += 1
        end
      end
      # since all candidates intersect at least one edge, try again with a higher number of neighbours
      if its
        return concave_hull_(vector, kk + 1)
      end

      previous_angle = angle(c_points[i], current_point)
      current_point = c_points[i]
      hull << current_point # a valid candidate was found
      dataset -= [current_point]
    end

    # check if all the given points are inside the computed polygon
    dataset.size.times{ |i|
      inside = point_in_polygon(dataset[i], hull)
      if !inside
        # since at least one point is out of the computed polygon, try again with a higher number of neighbours
        return concave_hull_(vector, kk + 1)
      end
    }

    hull
  end

  def self.convex_hull(vector)
    log 'Perform Convex hull'
    vector.sort!{ |a, b| a.last <=> b.last || a.first <=> b.first }.uniq!
    return vector if vector.size <= 3

    lower = []
    vector.each{ |point|
      lower.pop while lower.size > 1 && cross(lower[-2], lower[-1], point) <= 0
      lower << point
    }
    upper = []
    vector.reverse_each{ |point|
      upper.pop while upper.size > 1 && cross(upper[-2], upper[-1], point) <= 0
      upper << point
    }
    lower + upper
  end

  def self.nearestpoints(dataset, current_point, kk)
    dataset.sort_by { |d|
      (d[0] - current_point[0])**2 + (d[1] - current_point[1])**2
    }[0..kk]
  end

  def self.angle(point, current_point, previous_angle = 0)
    (Math.atan2(point[1] - current_point[1], point[0] - current_point[0]) - previous_angle) % (Math::PI * 2) - Math::PI
  end

  def self.intersect?(s1p1, s1p2, s2p1, s2p2)
    p0_x, p0_y = s1p1
    p1_x, p1_y = s1p2
    p2_x, p2_y = s2p1
    p3_x, p3_y = s2p2

    s10_x = p1_x - p0_x
    s10_y = p1_y - p0_y
    s32_x = p3_x - p2_x
    s32_y = p3_y - p2_y

    denom = s10_x * s32_y - s32_x * s10_y
    if denom.zero?
      return false
    end

    denom_positive = denom > 0

    s02_x = p0_x - p2_x
    s02_y = p0_y - p2_y
    s_numer = s10_x * s02_y - s10_y * s02_x
    if (s_numer < 0) == denom_positive
      return false
    end

    t_numer = s32_x * s02_y - s32_y * s02_x
    if (t_numer < 0) == denom_positive
      return false
    end

    if ((s_numer > denom) == denom_positive) || ((t_numer > denom) == denom_positive)
      return false
    end

    t = t_numer / denom
    x = p0_x + (t * s10_x)
    y = p0_y + (t * s10_y)

    if [s1p1, s1p2, s2p1, s2p2].include?([x, y])
      return false
    end

    true
  end

  def self.point_in_polygon(point, polygon)
    inside = false
    size = polygon.size
    size.times.each{ |i|
      min, max = [polygon[i][0], polygon[(i + 1) % size][0]].minmax
      next if min >= point[0] || point[0] > max

      # vertical ray, could return non homogenous result with a point on a vertical edge
      p = (polygon[i][1] - polygon[(i + 1) % size][1])
      q = (polygon[i][0] - polygon[(i + 1) % size][0])
      point_y = (point[0] - polygon[i][0]) * p / q + polygon[i][1]
      if point_y > point[1]
        inside = !inside
      end
    }
    inside
  end

  def self.cross(o, a, b)
    oy, ox = o
    ay, ax = a
    by, bx = b
    (ax - ox) * (by - oy) - (ay - oy) * (bx - ox)
  end
end
