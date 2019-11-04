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
  @@level_map = {
    debug: Logger::DEBUG,
    info: Logger::INFO,
    warn: Logger::WARN,
    error: Logger::ERROR,
    fatal: Logger::FATAL
  }

  # :full || :partial || nil
  # :full => display file path and line number of log function call
  # :partial => display file name and line number of log function call
  # nil => Do not display any of :partial or :full
  @@msg_location = nil

  @@logger = Logger.new(ENV['LOG_DEVICE'] || STDOUT)
  @@logger.level = Logger::INFO

  @@logger.formatter = proc do |severity, datetime, progname, msg|
    job_id = OptimizerWrapper::Job.current_job_id
    job_id = job_id.nil? ? '' : "#{job_id} - "

    progname = progname.empty? ? ' ' : " - #{progname}"

    "[#{datetime}] #{job_id}#{severity}#{progname}: #{msg}\n"
  end

  def self.define_progname(progname, location_option, caller_loc)
    call_obj = caller_loc.first.base_label != 'log' ? caller_loc.first : caller_loc.first
    file = location_option == :full ? call_obj.absolute_path : call_obj.path.scan(/(\w+).rb/)[0][0]
    lineno = call_obj.lineno

    value = "#{file}:#{lineno}"
    [progname, value].delete_if(&:empty?).join(' - ')
  end

  def self.msg_location_option
    @@msg_location
  end

  def self.msg_location_option=(value)
    @@msg_location = value
  end

  def self.level=(level)
    @@logger.level = @@lvl_map[level]
  end

  def self.log_device=(file)
    @@logger.reopen file
  end

  def self.formatter=(formatter)
    @@logger.formatter = formatter
  end

  def self.log(msg, level: :info, progname: '')
    progname = OptimizerLogger.define_progname(progname, @@msg_location, caller_locations) if @@msg_location

    @@logger
      .method(level)
      .call(progname) { msg }
  end
end

module OptimizerLoggerMethods
  private

  def log(msg, level: :info, progname: '')
    OptimizerLogger.log(msg, level: level, progname: progname)
  end
end

class Object < BasicObject
  include OptimizerLoggerMethods
end
