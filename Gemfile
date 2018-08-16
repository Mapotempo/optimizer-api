source 'https://rubygems.org'

gem 'require_all'

gem 'rack'
gem 'rakeup'
gem 'puma'
gem 'thin'
gem 'rack-cors'

gem 'grape', '<0.19.0' # Waiting Ruby 2.2
gem 'grape_logging'
gem 'grape-entity'
gem 'grape-swagger', '<0.26.0' # Waiting Ruby 2.2
gem 'grape-swagger-entity', '<0.1.6' # Waiting Ruby 2.2

gem 'i18n'
gem 'rack-contrib'
gem 'rest-client'
gem 'activemodel', '<5' # Waiting Ruby 2.2
gem 'active_hash', github: 'Mapotempo/active_hash'
gem 'nokogiri'
gem 'resque'
gem 'resque-status'
gem 'redis', '<4' # Waiting Ruby 2.2 (dependency from resque)

gem 'ai4r'
gem 'sim_annealing'

gem 'rgeo'
gem 'rgeo-geojson'
gem 'polylines'

gem 'google-protobuf', '>=3'

group :test do
  gem 'rack-test', '<0.8' # Waiting Ruby 2.2
  gem 'minitest'
  gem 'minitest-reporters'
  gem 'minitest-stub_any_instance'
  gem 'simplecov', require: false
end

group :production do
  gem 'redis-activesupport'
end
