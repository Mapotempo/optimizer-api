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

Rake::TestTask.new(:test_structure) do |t|
  $stdout.sync = true
  $stderr.sync = true
  ENV['APP_ENV'] ||= 'test'
  t.test_files = ['test/api/**/*_test.rb', 'test/models/**/*_test.rb']
end

namespace :test do
  task :api do
    ENV['COV'] = 'false'
    ENV['TEST'] ||= 'test/api/**/*_test.rb'
    Rake::Task['test'].invoke
  end

  task :models do
    ENV['COV'] = 'false'
    ENV['TEST'] ||= 'test/models/**/*_test.rb'
    Rake::Task['test'].invoke
  end

  task :structure do
    ENV['COV'] = 'false'
    Rake::Task['test_structure'].invoke
  end

  task :lib do
    ENV['COV'] = 'false'
    ENV['TEST'] ||= 'test/lib/**/*_test.rb'
    Rake::Task['test'].invoke
  end

  task :clustering do
    ENV['COV'] = 'false'
    ENV['TEST'] ||= 'test/**/*clustering*_test.rb'
    Rake::Task['test'].invoke
  end

  task :periodic do
    ENV['COV'] = 'false'
    ENV['TEST'] ||= 'test/**/*scheduling*_test.rb'
    Rake::Task['test'].invoke
  end
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
