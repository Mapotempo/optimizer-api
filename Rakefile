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
    next if ENV['APP_ENV'] == 'production'

    puts "#{Time.now} Cleaning existing jobs with #{Resque::Plugins::Status::STATUS_WORKING} status..."

    Resque::Plugins::Status::Hash.statuses.each{ |job|
      next unless job.status == Resque::Plugins::Status::STATUS_WORKING && job.time < Time.now - 10.seconds

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
  t.pattern = 'test/**/*_test.rb'
end

namespace :test do
  Rake::TestTask.new(:api){ |t| t.pattern = 'test/api/**/*_test.rb' }

  Rake::TestTask.new(:model){ |t| t.pattern = 'test/models/**/*_test.rb' }

  Rake::TestTask.new(:structure){ |t| t.test_files = ['test/api/**/*_test.rb', 'test/models/**/*_test.rb'] }

  Rake::TestTask.new(:lib){ |t| t.pattern = 'test/lib/**/*_test.rb' }

  Rake::TestTask.new(:clustering){ |t| t.pattern = 'test/**/*clustering*_test.rb' }

  Rake::TestTask.new(:periodic){ |t| t.pattern = 'test/**/*scheduling*_test.rb' }
end

task clean_tmp_dir: :environment do
  OptimizerWrapper.tmp_vrp_dir.cleanup
end

task clean_dump_dir: :environment do
  OptimizerWrapper.dump_vrp_dir.cleanup
end

task :environment do
  require './environment'
end
