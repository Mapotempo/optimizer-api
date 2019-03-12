source 'https://rubygems.org'

gem 'require_all'

gem 'rack'
gem 'rakeup'
gem 'puma'
gem 'thin'
gem 'rack-cors'

gem 'grape', '<0.19.0' # TODO: Waiting Ruby 2.2
gem 'grape_logging'
gem 'grape-entity'
gem 'grape-swagger', '<0.26.0' # TODO: Waiting Ruby 2.2
gem 'grape-swagger-entity', '<0.1.6' # TODO: Waiting Ruby 2.2

gem 'i18n'
gem 'rack-contrib'
gem 'rest-client'
gem 'activemodel', '<5' # TODO: Waiting Ruby 2.2
gem 'active_hash', github: 'Mapotempo/active_hash'
gem 'nokogiri'
gem 'resque'
gem 'resque-status'
gem 'redis', '<4' # TODO: Waiting Ruby 2.2 (dependency from resque)

gem 'ai4r'
gem 'sim_annealing'

gem 'rgeo'
gem 'rgeo-geojson'
gem 'polylines'

gem 'google-protobuf', '>=3'

group :development, :test do
  gem 'byebug'

  # For linting and offline code analysis in vscode
  gem 'rubocop', '<0.58' # TODO: Waiting Ruby 2.2
  gem 'solargraph'

  ## Next gems to use the debuger of vscode directly
  ## but due to a bug in rubyide/vscode-ruby it doesn't
  ## work at the moment with rake::workers
  # gem 'psych', '<3.0.2' # TODO: Waiting Ruby 2.2
  # gem 'ruby-debug-ide'
  # gem 'debase'
end

group :test do
  gem 'rack-test', '<0.8' # TODO: Waiting Ruby 2.2
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'minitest-stub_any_instance'
  gem 'minitest-focus'
  gem 'simplecov', require: false
end

group :production do
  gem 'redis-activesupport'
end
