source 'https://rubygems.org'
ruby '~> 2.5'

gem 'require_all'

gem 'puma'
# remove the following custom github definition after the following PR commit is merged to the stable branch
# https://github.com/rack/rack/commit/1970771c7e01d54cb631dae0bc7618e2561ad1c7
gem 'rack', github: 'senhalil/rack', branch: 'improved-asserts'
gem 'rack-contrib', require: 'rack/contrib'
gem 'rack-cors', require: 'rack/cors'
gem 'rack-server-pages', '~> 0.1.0'
gem 'rake'
gem 'thin'

# API
gem 'grape', '>=1.5.3' # Important fix introduced v1.5.3 (see PR #PR2164)
gem 'grape-entity'
gem 'grape-swagger'
gem 'grape-swagger-entity'
gem 'grape_logging'

# Models
gem 'actionpack', require: 'action_dispatch'
# waiting for the following PRs to get merged and "released!"
# https://github.com/zilkey/active_hash/pull/231 and https://github.com/zilkey/active_hash/pull/233
gem 'active_hash', github: 'senhalil/active_hash', branch: 'dev'
gem 'activemodel'
gem 'activesupport', require: 'active_support'
gem 'google-protobuf', '>=3', require: 'google/protobuf'
gem 'oj'

# Text
gem 'charlock_holmes'
gem 'http_accept_language'
gem 'i18n'

# Queue
gem 'redis', '<4'
gem 'resque', '<2'
gem 'resque-status', '>0.4'

# Web
gem 'rest-client'

# AI
gem 'ai4r'
gem 'balanced_vrp_clustering', github: 'mapotempo/balanced_vrp_clustering', branch: 'dev'

# Geo
gem 'polylines'
gem 'rgeo'
gem 'rgeo-geojson', require: 'rgeo/geo_json'

gem 'sentry-raven'

group :development, :test do
  gem 'benchmark-ips' # to in-place benchmark of different implementations
  gem 'byebug'

  # Offline code analysis
  gem 'ripper-tags'
  gem 'solargraph'

  # For creating dependency graphs
  # gem 'rubrowser' # active to create graph

  # For debugging memory issues
  # gem 'heap-profiler'   # active to create graph
  # gem 'memory_profiler' # active to create graph

  ## Next gems to use the debuger of vscode directly
  ## but due to a bug in rubyide/vscode-ruby it doesn't
  ## work at the moment with rake::workers
  # gem 'psych', '<3.0.2' # TODO: Waiting Ruby 2.2
  # gem 'ruby-debug-ide'
  # gem 'debase'
end

group :rubocop do
  # Linting
  gem 'mapotempo_rubocop', github: 'Mapotempo/mapotempo_rubocop'
  gem 'rubocop'
end

group :test do
  gem 'minitest', require: 'minitest/autorun'
  gem 'minitest-around' # to create a block around unit tests for initialisation and cleanup
  gem 'minitest-bisect' # useful for identifing randomly failing order-depoendent tests
  gem 'minitest-focus', require: 'minitest/focus'
  gem 'minitest-reporters', require: 'minitest/reporters'
  gem 'minitest-retry', require: 'minitest/retry' # relaunches selected methods when they fail
  gem 'minitest-stub_any_instance', require: 'minitest/stub_any_instance'
  gem 'rack-test', require: 'rack/test'
  gem 'simplecov', require: false
  gem 'webmock', require: 'webmock/minitest'
end

group :production do
  gem 'redis-activesupport'
end
