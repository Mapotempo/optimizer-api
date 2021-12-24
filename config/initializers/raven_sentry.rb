# frozen_string_literal: true

require 'raven'

if ENV['SENTRY_DSN'] || ENV['RAVEN_DSN']
  Raven.configure { |config|
    config.dsn = ENV['SENTRY_DSN'] || ENV['RAVEN_DSN']
  }
elsif ENV['APP_ENV'] == 'production'
  puts 'WARNING: Sentry DSN should be defined for production'
end
# Raven.tags_context release: 'vXX'
