source 'https://rubygems.org'

gem 'require_all'

gem 'rack'
gem 'rakeup'
gem 'puma'
gem 'thin'
gem 'rack-cors'

gem 'grape', '<0.19.0' # TODO: Grape 1.2.4 reduces performances
gem 'grape_logging'
gem 'grape-entity'
gem 'grape-swagger', '<0.26.0' # TODO: Waiting Grape 1+
gem 'grape-swagger-entity', '<0.1.6' # TODO: Waiting Grape 1+

gem 'i18n'
gem 'rack-contrib'
gem 'rest-client'
gem 'activemodel'
gem 'active_hash', github: 'Mapotempo/active_hash'
gem 'nokogiri'
gem 'resque', '<2'
gem 'resque-status', '>0.4'
gem 'redis', '<4'

gem 'ai4r'
gem 'sim_annealing'

gem 'rgeo'
gem 'rgeo-geojson'
gem 'polylines'

gem 'google-protobuf', '>=3'

group :development, :test do
  gem 'byebug'
  gem 'benchmark-ips'
  # For linting and offline code analysis in vscode
  gem 'rubocop'
  gem 'solargraph'

  ## Next gems to use the debuger of vscode directly
  ## but due to a bug in rubyide/vscode-ruby it doesn't
  ## work at the moment with rake::workers
  # gem 'psych', '<3.0.2' # TODO: Waiting Ruby 2.2
  # gem 'ruby-debug-ide'
  # gem 'debase'
end

group :test do
  gem 'rack-test'
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'minitest-stub_any_instance'
  gem 'minitest-focus'
  gem 'simplecov', require: false
end

group :production do
  gem 'redis-activesupport'
end
