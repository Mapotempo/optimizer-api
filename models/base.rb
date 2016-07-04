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
require 'active_hash'
require 'active_model/validations/numericality'


module Models
  def self.delete_all
    Base.descendants.each(&:delete_all)
  end

  class Base < ActiveHash::Base
    include ActiveModel::Validations
    include ActiveModel::Validations::HelperMethods

    include ActiveHash::Associations

    def initialize(hash)
      super(hash.inject({}) { |memo, (k, v)|
        memo[k.to_sym] = v
        memo
      })
    end

    def self.has_many(name, options = {})
      super(name, options)

      define_method(name) do
        self[name] || []
      end

      define_method("#{name}=") do |vals|
        self[name] = (vals && vals.collect{ |val|
          c = class_from_string(options[:class_name])
          if val.is_a?(c)
            val
          else
            c.create(val)
          end
        }) || []
      end
    end

    private

    def class_from_string(str)
      str.split('::').inject(Object) do |mod, class_name|
        mod.const_get(class_name)
      end
    end
  end
end
