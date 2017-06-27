require 'resque'

Resque.inline = ENV['APP_ENV'] == 'test'
Resque.redis = ENV['REDIS_HOST'] || 'localhost'
