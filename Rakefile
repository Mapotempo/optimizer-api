require 'rubygems'
require 'bundler/setup'
require 'resque/tasks'
require './environment.rb'

require 'rake/testtask'
Rake::TestTask.new do |t|
  ENV['APP_ENV'] ||= 'test'
  t.pattern = "test/**/*_test.rb"
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
