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
    include ActiveModel::Serializers::JSON
    include ActiveModel::Validations
    include ActiveModel::Validations::HelperMethods

    include ActiveHash::Associations

    def initialize(hash)
      super(hash.each_with_object({}){ |(k, v), memo|
        memo[k.to_sym] = v
      })

      # Make sure default values are not the same object for all
      self.attributes.each{ |k, v|
        # If the key doesn't exist in the hash and its relevant substructures then it must be a default value
        next if hash.has_key?(k) ||
                !v.duplicable? ||
                ["#{k}_id", "#{k[0..-2]}_ids", "#{k[0..-4]}y_ids"].any?{ |key| hash.has_key?(key.to_sym) } ||
                hash[:configuration] && [:preprocessing, :restitution, :schedule, :resolution].any?{ |symbol|
                  hash[:configuration][symbol]&.has_key?(k[symbol.size + 1..-1]&.to_sym)
                }

        self[k] = v.dup # dup to make sure they are different objects
      }
    end

    def self.has_many(name, options = {})
      super

      define_method(name) do
        self[name] || []
      end

      define_method("#{name}=") do |vals|
        self[name] = vals&.collect{ |val|
          c = class_from_string(options[:class_name])
          if val.is_a?(c)
            val
          else
            c.create(val) if !val.empty?
          end
        }&.compact || []
      end

      define_method("#{name}+=") do |vals|
        self[name] = [] if !self[name]
        self[name] += vals&.collect{ |val|
          c = class_from_string(options[:class_name])
          if val.is_a?(c)
            val
          else
            c.create(val) if !val.empty?
          end
        }&.compact || []
      end

      define_method("#{name[0..-2]}_ids=") do |vals|
        c = class_from_string(options[:class_name])
        self[name] = vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
      end

      define_method("#{name[0..-2]}_ids+=") do |vals|
        c = class_from_string(options[:class_name])
        if self[name]
          self[name] += vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        else
          self[name] = vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        end
      end

      define_method("#{name[0..-4]}y_ids=") do |vals|
        c = class_from_string(options[:class_name])
        if self[name]
          self[name] += vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        else
          self[name] = vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        end
      end

      define_method("#{name[0..-4]}y_ids+=") do |vals|
        c = class_from_string(options[:class_name])
        if self[name]
          self[name] += vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        else
          self[name] = vals && vals.split(',').collect{ |val_id| c.find(val_id) }.flatten.compact
        end
      end
    end

    def self.belongs_to(name, options = {})
      super

      define_method(name) do
        self[name]
      end

      define_method("#{name}=") do |val|
        c = class_from_string(options[:class_name])
        self[name] = val && (val.is_a?(Hash) ? c.create(val) : val)
      end

      define_method("#{name}_id") do
        self[name]&.id
      end

      define_method("#{name}_id=") do |val_id|
        c = class_from_string(options[:class_name])
        self[name] = c.find(val_id)
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
