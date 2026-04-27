# frozen_string_literal: true

source 'https://rubygems.org'

ruby '3.3.0'

# === Core ===
gem 'rails', '~> 7.1'
gem 'pg', '~> 1.5'
gem 'puma', '~> 8.0'

# === Performance & Caching ===
gem 'redis', '~> 5.0'
gem 'connection_pool', '~> 2.4'

# === Security & Rate Limiting ===
gem 'rack-attack', '~> 6.7'

# === Utilities ===
gem 'dotenv-rails', '~> 3.1', groups: %i[development test]
gem 'bootsnap', '>= 1.4.4', require: false

group :development, :test do
  gem 'rspec-rails', '~> 6.1'
  gem 'factory_bot_rails', '~> 6.4'
  gem 'faker', '~> 3.2'
  gem 'pry-rails', '~> 0.3'
  gem 'rubocop', '~> 1.65', require: false
  gem 'rubocop-rails', '~> 2.25', require: false
  gem 'rubocop-rspec', '~> 3.1', require: false
end

group :test do
  gem 'shoulda-matchers', '~> 6.0'
  gem 'database_cleaner-active_record', '~> 2.1'
  gem 'webmock', '~> 3.23'
  gem 'simplecov', '~> 0.22', require: false
  gem 'simplecov-lcov', '~> 0.8', require: false
end
