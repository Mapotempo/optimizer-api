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
require './models/base'

module Models
  class Activity < Base
    field :duration, default: 0
    field :setup_duration, default: 0
    field :additional_value, default: 0
    field :late_multiplier, default: nil
    field :position, default: :neutral

    # FIXME: ActiveHash doesn't validate the validator of the associated objects
    # Forced to do the validation in Grape params
    # validates_numericality_of :duration, greater_than_or_equal_to: 0
    # validates_numericality_of :setup_duration
    # validates_numericality_of :late_multiplier, allow_nil: true

    belongs_to :point, class_name: 'Models::Point', as_json: :id
    has_many :timewindows, class_name: 'Models::Timewindow'
    # include ValidateTimewindows # FIXME: <- This is commented out because of the above reason.
                                  # Commenting out would make the ActivityTest::test_timewindows pass; however,
                                  # the code would continue to accept invalid time windows thorugh API because
                                  # vrp.valid? doesn't call the validator of activity
                                  # We need to implement a check inside Api::V01::Vrp and fix the ActivityTest::test_timewindows accordingly

    def vrp_result(options = {})
      hash = super(options)
      hash.delete('late_multiplier')
      hash.delete('position')
      hash.delete('point')
      if self.point # Rest inherits from activity
        hash['lat'] = point.location&.lat
        hash['lon'] = point.location&.lon
      end
      hash
    end
  end
end
