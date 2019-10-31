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

  @@logger = Logger.new(ENV['LOG_DEV'] || STDOUT)
  @@logger.level = Logger::INFO

  @@logger.formatter = proc do |severity, datetime, progname, msg|
    job_id = OptimizerWrapper::Job.current_job_id
    job_id = job_id.nil? ? '' : "#{job_id} - "
    "[#{datetime}] #{job_id}#{severity} : #{msg}\n"
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

  def self.log(msg, options = { level: :info, progname: '' })

    if options[:progname].empty?
      call_obj = caller_locations.first
      file = call_obj.path.scan(/(\w+).rb/)[0][0]
      caller_name = call_obj.base_label
      lineno = call_obj.lineno

      options[:progname] = "#{file}.#{caller_name}:#{lineno}"
    end

    @@logger
      .method(options[:level].nil? ? :info : options[:level])
      .call(options[:progname]) { msg }
  end
end

module OptimizerLoggerMethods
  private
  def log(msg, level: :info, progname: '')
    if progname.empty?
      call_obj = caller_locations.first
      file = call_obj.path.scan(/(\w+).rb/)[0][0]
      caller_name = call_obj.base_label
      lineno = call_obj.lineno

      progname = "#{file}.#{caller_name}:#{lineno}"
    end

    OptimizerLogger.log(msg, level: level, progname: progname)
  end
end

class Object < BasicObject
  include OptimizerLoggerMethods
end
