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
require './models/concerns/as_json'
require './models/concerns/vrp_result'

module Models
  def self.delete_all
    Base.descendants.each(&:delete_all)
  end

  class Base < ActiveHash::Base
    include ActiveModel::Serializers::JSON
    include ActiveModel::Validations
    include ActiveModel::Validations::HelperMethods
    include Serializers::JSONResult

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
                ["#{k}_id", "#{ActiveSupport::Inflector.singularize(k.to_s)}_ids"].any?{ |key|
                  hash.has_key?(key.to_sym)
                } ||
                hash[:configuration] && [:preprocessing, :restitution, :schedule, :resolution].any?{ |symbol|
                  hash[:configuration][symbol]&.has_key?(k[symbol.size + 1..-1]&.to_sym)
                }

        self[k] = v.dup # dup to make sure they are different objects
      }
    end

    class << self
      def json_fields
        @json_fields ||= []
      end

      def vrp_result_fields
        @vrp_result_fields ||= []
      end
    end

    def to_hash
      as_json
    end

    def to_s
      as_json
    end

    def inspect
      as_json
    end

    def as_json(options = {})
      hash = {}
      self.class.json_fields.each{ |field_name|
        hash[field_name] = self.send(field_name).as_json if self.respond_to?(field_name)
      }
      hash
    end

    def vrp_result(options = {})
      hash = {}
      self.class.vrp_result_fields.each{ |field_name|
        hash[field_name] = self.send(field_name).vrp_result if self.respond_to?(field_name)
      }
      hash
    end

    def self.field(name, options = {})
      case options[:as_json]
      when nil
        json_fields << name.to_s
      when :none
        json_fields
      else
        raise 'Unknown :as_json option'
      end

      case options[:vrp_result]
      when nil
        vrp_result_fields << name.to_s
      when :hide
        vrp_result_fields
      else
        raise 'Unknown :vrp_result option'
      end

      super(name, options)
    end

    def self.has_many(name, options = {})
      field_names << name

      # respect English spelling rules:
      # vehicles -> vehicle_ids | capacities -> capacity_ids | matrices -> matrix_ids
      ids_function_name = "#{ActiveSupport::Inflector.singularize(name.to_s)}_ids".to_sym

      case options[:as_json]
      when :ids
        json_fields << ids_function_name.to_s
      when :none
        json_fields
      when nil
        json_fields << name.to_s
      else
        raise 'Unknown :as_json option'
      end

      case options[:vrp_result]
      when :hide
        vrp_result_fields
      when nil
        vrp_result_fields << name.to_s
      else
        raise 'Unknown :vrp_result option'
      end

      redefine_method(name) do
        self[name] ||= []
      end

      redefine_method("#{name}=") do |vals|
        c = class_from_string(options[:class_name])
        self[name] = vals&.collect{ |val|
          if val.is_a?(c)
            val
          else
            c.create(val) if !val.empty?
          end
        }&.compact || []
        self[ids_function_name] = self[name]&.map(&:id) if c.module_parent == Models
        self[name]
      end

      # Array and other objects that are not based on Models::Base class cannot have id methods
      if options[:class_name]&.start_with? 'Models::'
        redefine_method(ids_function_name) do
          self[ids_function_name] ||= self[name]&.map(&:id) || []
        end

        redefine_method("#{ids_function_name}=") do |vals|
          c = class_from_string(options[:class_name])
          self[name] = vals && vals.split(',').flat_map{ |val_id| c.find(val_id) }
          self[ids_function_name] = self[name]&.map(&:id)
        end
      end
    end

    def self.belongs_to(name, options = {})
      field_names << name

      id_function_name = "#{name}_id".to_sym

      case options[:as_json]
      when :id
        json_fields << id_function_name.to_s
      when :none
        json_fields
      when nil
        json_fields << name.to_s
      else
        raise 'Unknown :as_json option'
      end

      case options[:vrp_result]
      when :hide
        vrp_result_fields
      when nil
        vrp_result_fields << name.to_s
      else
        raise 'Unknown :vrp_result option'
      end

      redefine_method(name) do
        self[name]
      end

      redefine_method("#{name}=") do |val|
        c = class_from_string(options[:class_name])
        self[name] = val && (val.is_a?(Hash) ? c.create(val) : val)
        self[id_function_name] = self[name]&.id if c.module_parent == Models
        self[name]
      end

      # Array and other objects that are not based on Models::Base class cannot have id methods
      if options[:class_name]&.start_with? 'Models::'
        redefine_method(id_function_name) do
          self[id_function_name] ||= self[name]&.id
        end

        redefine_method("#{id_function_name}=") do |val_id|
          c = class_from_string(options[:class_name])
          self[name] = val_id && c.find(val_id)
          self[id_function_name] = self[name]&.id
        end
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
