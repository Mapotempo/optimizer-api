require 'resque'
require 'resque-status'

Resque.inline = ENV['APP_ENV'] == 'test'
Resque.redis = Redis.new(
  host: ENV['REDIS_RESQUE_HOST'] || ENV['REDIS_HOST'] || 'localhost',
  timeout: 300.0
)
Resque::Plugins::Status::Hash.expire_in = (30 * 24 * 60 * 60) # In seconds, a too small value remove working or queuing jobs
