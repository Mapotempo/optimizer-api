# Copyright © Mapotempo, 2021
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

# Extracted and adapted from activemodel/lib/active_model/serializers/json.rb
module Serializers
  module JSONResult
    extend ActiveSupport::Concern
    include ActiveModel::Serialization

    included do
      extend ActiveModel::Naming

      class_attribute :include_root_in_json, instance_writer: false, default: false
    end

    def vrp_result(options = nil)
      root = if options && options.key?(:root)
               options[:root]
             else
               include_root_in_json
             end

      hash = serializable_hash(options).vrp_result(options)
      if root
        root = model_name.element if root == true
        { root => hash }
      else
        hash
      end
    end
  end
end

 # Extracted and adapted from activesupport/lib/active_support/core_ext/object/json.rb
class Module
  def vrp_result(options = nil) #:nodoc:
    name
  end
end

class Object
  def vrp_result(options = nil) #:nodoc:
    if respond_to?(:to_hash)
      to_hash.vrp_result(options)
    else
      instance_values.vrp_result(options)
    end
  end
end

class Struct #:nodoc:
  def vrp_result(options = nil)
    Hash[members.zip(values)].vrp_result(options)
  end
end

class TrueClass
  def vrp_result(options = nil) #:nodoc:
    self
  end
end

class FalseClass
  def vrp_result(options = nil) #:nodoc:
    self
  end
end

class NilClass
  def vrp_result(options = nil) #:nodoc:
    self
  end
end

class String
  def vrp_result(options = nil) #:nodoc:
    self
  end
end

class Symbol
  def vrp_result(options = nil) #:nodoc:
    to_s
  end
end

class Numeric
  def vrp_result(options = nil) #:nodoc:
    self
  end
end

class Float
  # Encoding Infinity or NaN to JSON should return "null". The default returns
  # "Infinity" or "NaN" which are not valid JSON.
  def vrp_result(options = nil) #:nodoc:
    finite? ? self : nil
  end
end

class BigDecimal
  # A BigDecimal would be naturally represented as a JSON number. Most libraries,
  # however, parse non-integer JSON numbers directly as floats. Clients using
  # those libraries would get in general a wrong number and no way to recover
  # other than manually inspecting the string with the JSON code itself.
  #
  # That's why a JSON string is returned. The JSON literal is not numeric, but
  # if the other end knows by contract that the data is supposed to be a
  # BigDecimal, it still has the chance to post-process the string and get the
  # real value.
  def vrp_result(options = nil) #:nodoc:
    finite? ? to_s : nil
  end
end

class Regexp
  def vrp_result(options = nil) #:nodoc:
    to_s
  end
end

module Enumerable
  def vrp_result(options = nil) #:nodoc:
    to_a.vrp_result(options)
  end
end

class IO
  def vrp_result(options = nil) #:nodoc:
    to_s
  end
end

class Range
  def vrp_result(options = nil) #:nodoc:
    to_s
  end
end

class Array
  def vrp_result(options = nil) #:nodoc:
    map { |v| options ? v.vrp_result(options.dup) : v.vrp_result }
  end
end

class Hash
  def vrp_result(options = nil) #:nodoc:
    # create a subset of the hash by applying :only or :except
    subset = if options
      if attrs = options[:only]
        slice(*Array(attrs))
      elsif attrs = options[:except]
        except(*Array(attrs))
      else
        self
      end
    else
      self
    end

    result = {}
    subset.each do |k, v|
      result[k.to_s] = options ? v.vrp_result(options.dup) : v.vrp_result
    end
    result
  end
end

class Time
  def vrp_result(options = nil) #:nodoc:
    if ActiveSupport::JSON::Encoding.use_standard_json_time_format
      xmlschema(ActiveSupport::JSON::Encoding.time_precision)
    else
      %(#{strftime("%Y/%m/%d %H:%M:%S")} #{formatted_offset(false)})
    end
  end
end

class Date
  def vrp_result(options = nil) #:nodoc:
    if ActiveSupport::JSON::Encoding.use_standard_json_time_format
      strftime("%Y-%m-%d")
    else
      strftime("%Y/%m/%d")
    end
  end
end

class DateTime
  def vrp_result(options = nil) #:nodoc:
    if ActiveSupport::JSON::Encoding.use_standard_json_time_format
      xmlschema(ActiveSupport::JSON::Encoding.time_precision)
    else
      strftime("%Y/%m/%d %H:%M:%S %z")
    end
  end
end

class URI::Generic #:nodoc:
  def vrp_result(options = nil)
    to_s
  end
end

class Pathname #:nodoc:
  def vrp_result(options = nil)
    to_s
  end
end

class IPAddr # :nodoc:
  def vrp_result(options = nil)
    to_s
  end
end

class Process::Status #:nodoc:
  def vrp_result(options = nil)
    { exitstatus: exitstatus, pid: pid }
  end
end

class Exception
  def vrp_result(options = nil)
    to_s
  end
end
