require 'rubygems'
require 'bundler/setup'
require 'rakeup'
require 'resque/tasks'

RakeUp::ServerTask.new do |t|
  t.port = 1791
  t.pid_file = 'tmp/server.pid'
  t.server = :puma
end

require 'rake/testtask'
Rake::TestTask.new do |t|
  t.pattern = "test/**/*_test.rb"
end

task :environment do
  require './environment'
end
