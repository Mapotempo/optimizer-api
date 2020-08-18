require 'rubygems'
require 'bundler/setup'
require 'resque/tasks'
require './environment.rb'

# Clean the jobs which are interrupted by restarting queues which left in working status
# TODO: eventually instead of removing these jobs, we can just re-queue them
namespace :resque do
  task :prune_dead_workers do
    # Clear the resque workers who were killed off without unregistering
    Resque.workers.each(&:prune_dead_workers)
  end

  task :clean_working_job_ids => :prune_dead_workers do
    puts "#{Time.now} Cleaning existing jobs with #{Resque::Plugins::Status::STATUS_WORKING} status..."

    Resque::Plugins::Status::Hash.statuses().each{ |job|
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

  task :workers => :clean_working_job_ids # add job cleaning as a pre-requisite
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  $stdout.sync = true
  $stderr.sync = true
  ENV['APP_ENV'] ||= 'test'
  t.pattern = 'test/**/*_test.rb'
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
