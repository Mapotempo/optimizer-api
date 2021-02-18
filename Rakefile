require 'rubygems'
require 'bundler/setup'
require 'resque/tasks'

# Clean the jobs which are interrupted by restarting queues which left in working status
# TODO: eventually instead of removing these jobs, we can just re-queue them
namespace :resque do
  task prune_dead_workers: :environment do
    # Clear the resque workers who were killed off without unregistering
    Resque.workers.each(&:prune_dead_workers)
  end

  task clean_working_job_ids: :prune_dead_workers do
    puts "#{Time.now} Cleaning existing jobs with #{Resque::Plugins::Status::STATUS_WORKING} status..."

    Resque::Plugins::Status::Hash.statuses.each{ |job|
      next unless job.status == Resque::Plugins::Status::STATUS_WORKING

      # Protect the jobs running on other queues
      running_job_ids = Resque.workers.map{ |w|
        j = w.job(false)
        j['payload'] && j['payload']['args'].first
      }
      next if running_job_ids.include?(job.uuid)

      puts "#{Time.now} #{job.uuid} removed because it is interrupted by restarting queues"
      Resque::Plugins::Status::Hash.remove(job.uuid)
    }
  end

  # Add job cleaning as a pre-requisite
  task work: :clean_working_job_ids
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  $stdout.sync = true
  $stderr.sync = true
  ENV['APP_ENV'] ||= 'test'
  t.pattern = 'test/**/*_test.rb'
end

desc 'Dump all necessary fixture files'
task :test_dump_vrp do
  require './test/test_helper'
  old_test_dump_vrp = ENV['TEST_DUMP_VRP']
  old_logger_level = OptimizerLogger.level
  OptimizerLogger.level = :fatal
  ENV['TEST_DUMP_VRP'] = 'true'
  folder = 'test/fixtures/'
  extention = 'json'
  puts 'Dumping fixture files:'
  Dir["#{folder}*.#{extention}"].sort.each{ |filename|
    puts "\t#{filename}"
    begin
      TestHelper.load_vrp(self, fixture_file: filename[folder.size..-extention.size - 2])
    rescue TypeError
      TestHelper.load_vrps(self, fixture_file: filename[folder.size..-extention.size - 2])
    end
  }
ensure
  OptimizerLogger.level = old_logger_level if old_logger_level
  ENV['TEST_DUMP_VRP'] = old_test_dump_vrp # no condition it can be nil
end

task clean_tmp_dir: :environment do
  require './environment'
  OptimizerWrapper.tmp_vrp_dir.cleanup
end

task clean_dump_dir: :environment do
  require './environment'
  OptimizerWrapper.dump_vrp_dir.cleanup
end

task :environment do
  require './environment'
end
