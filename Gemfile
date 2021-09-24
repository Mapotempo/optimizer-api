source 'https://rubygems.org'
ruby '~> 2.5'

gem 'require_all'

gem 'puma'
gem 'rack', github: 'senhalil/rack', branch: 'improved-asserts' # remove the custom github definition after the following PR commit is on the stable branch https://github.com/rack/rack/commit/1970771c7e01d54cb631dae0bc7618e2561ad1c7
gem 'rack-cors'
gem 'rake'
gem 'thin'

gem 'grape', '>=1.5.3' # Important fix introduced v1.5.3 (see PR #PR2164)
gem 'grape-entity'
gem 'grape-swagger'
gem 'grape-swagger-entity'
gem 'grape_logging'

gem 'actionpack'
gem 'active_hash', github: 'mapotempo/active_hash', branch: 'dev' # waiting for the following PRs to get merged and "released!" https://github.com/zilkey/active_hash/pull/231 and https://github.com/zilkey/active_hash/pull/233
gem 'activemodel'

gem 'charlock_holmes'
gem 'http_accept_language'
gem 'i18n'
gem 'nokogiri'
gem 'rack-contrib'
gem 'redis', '<4'
gem 'resque', '<2'
gem 'resque-status', '>0.4'
gem 'rest-client'

gem 'ai4r'
gem 'balanced_vrp_clustering', github: 'Mapotempo/balanced_vrp_clustering', branch: 'dev'
gem 'sim_annealing'

gem 'polylines'
gem 'rgeo'
gem 'rgeo-geojson'

gem 'google-protobuf', '>=3'

gem 'oj'
gem 'zlib'

group :development, :test do
  gem 'benchmark-ips' # to in-place benchmark of different implementations
  gem 'byebug'

  # For linting and offline code analysis
  gem 'rubocop', '< 0.82'
  gem 'rubocop-minitest', require: false
  gem 'rubocop-performance', require: false
  gem 'solargraph'

  # For creating dependency graphs
  gem 'rubrowser'

  # For debugging memory issues
  gem 'heap-profiler'
  gem 'memory_profiler'

  ## Next gems to use the debuger of vscode directly
  ## but due to a bug in rubyide/vscode-ruby it doesn't
  ## work at the moment with rake::workers
  # gem 'psych', '<3.0.2' # TODO: Waiting Ruby 2.2
  # gem 'ruby-debug-ide'
  # gem 'debase'
end

group :test do
  gem 'minitest'
  gem 'minitest-around' # to create a block around unit tests for initialisation and cleanup
  gem 'minitest-bisect' # useful for identifing randomly failing order-depoendent tests
  gem 'minitest-focus'
  gem 'minitest-reporters'
  gem 'minitest-retry' # relaunches selected methods when they fail
  gem 'minitest-stub_any_instance'
  gem 'rack-test'
  gem 'simplecov', require: false
  gem 'webmock'
end

group :production do
  gem 'redis-activesupport'
end
