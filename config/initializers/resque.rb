require 'resque'

Resque.inline = ENV['APP_ENV'] == 'test'
