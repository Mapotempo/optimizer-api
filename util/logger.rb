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

require 'logger'

class OptimizerLogger
  @@log_device = ENV['LOG_DEVICE'] || STDOUT
  @@level = :info
  @@level_map = {
    debug: Logger::DEBUG,
    info: Logger::INFO,
    warn: Logger::WARN,
    error: Logger::ERROR,
    fatal: Logger::FATAL
  }

  # :absolute || :relative || :filename || nil
  # :absolute => display full file path and line number of log function call
  # :relative => display relative file path and line number of log function call
  # :filename => display file name and line number of log function call
  # nil => Do not display any caller location information
  @@caller_location = nil

  @@logger = Logger.new(@@log_device)
  @@logger.level = @@level_map[@@level]

  @@logger.formatter = proc do |severity, datetime, progname, msg|
    datetime = OptimizerLogger::with_datetime ? "[#{datetime}]" : nil
    job_id = OptimizerWrapper::Job.current_job_id ? "#{OptimizerWrapper::Job.current_job_id} -" : nil
    progname = progname.empty? ? nil : "- #{progname}"

    [datetime, job_id, severity, progname].compact.join(' ') + ": #{msg}\n"
  end

  def self.define_progname(progname)
    location = nil
    if @@caller_location
      call_obj = caller_locations.second.base_label == 'log' ? caller_locations.third : caller_locations.second

      file =  case @@caller_location
              when :filename
                call_obj.path.scan(/(\w+).rb/)[0][0]
              when :absolute
                call_obj.absolute_path
              when :relative
                ".#{call_obj.path.scan(/optimizer-api(.*\.rb)/)[0][0]}"
              else
                raise NotImplementedError, "Unknown option (#{@@caller_location}) OptimizerLogger.caller_location parameter -- :absolute || :relative || :filename || nil"
              end

      lineno = call_obj.lineno

      location = "#{file}:#{lineno}"
    end
    [progname, location].compact.join(' - ')
  end

  def self.caller_location
    @@caller_location
  end

  def self.caller_location=(value)
    @@caller_location = value
  end

  def self.with_datetime
    @@with_datetime
  end

  def self.with_datetime=(value)
    @@with_datetime = value
  end

  def self.level
    @@level
  end

  def self.level=(level)
    @@level = level
    @@logger.level = @@level_map[level]
  end

  def self.log_device
    @@log_device
  end

  def self.log_device=(logdev)
    @@log_device = logdev
    @@logger.reopen logdev
  end

  def self.formatter=(formatter)
    @@logger.formatter = formatter
  end

  def self.log(msg, level: :info, progname: nil)
    progname = define_progname(progname)

    @@logger
      .method(level)
      .call(progname) { msg }
  end

  private_class_method :define_progname
end

module OptimizerLoggerMethods
  private

  def log(msg, level: :info, progname: nil)
    OptimizerLogger.log(msg, level: level, progname: progname)
  end
end

class Object < BasicObject
  include OptimizerLoggerMethods
end
