# frozen_string_literal: true

# This file is copied to spec/ when you run 'rails generate rspec:install'
require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
ENV['DATABASE_CLEANER_ALLOW_REMOTE_DATABASE_URL'] = 'true'

require_relative '../config/environment'

# Prevent database truncation if the environment is production
abort('The Rails environment is running in production mode!') if Rails.env.production?

require 'rspec/rails'
require 'shoulda/matchers'
require 'database_cleaner/active_record'
require 'webmock/rspec'
require 'factory_bot_rails'

# Add additional requires below this line. Rails is not loaded until this point!

Dir[Rails.root.join('spec/support/**/*.rb')].each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  # ── Factory Bot ──────────────────────────────────────────
  config.include FactoryBot::Syntax::Methods

  config.before(:each, type: :request) do
    host! 'localhost'
  end

  config.before(:each) do
    Rails.cache.clear
  end
  # ── Database Cleaner ─────────────────────────────────────
  config.before(:suite) do
    Rack::Attack.enabled = false
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end


  config.around(:each) do |example|
    DatabaseCleaner.cleaning { example.run }
  end

  config.around(:each, :rack_attack) do |example|
    Rack::Attack.enabled = true
    example.run
    Rack::Attack.enabled = false
  end

  # ── RSpec Rails ──────────────────────────────────────────
  config.fixture_paths = ["#{::Rails.root}/spec/fixtures"]
  config.use_transactional_fixtures = false
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!
end

# ── Shoulda Matchers (Đã được đưa ra ngoài RSpec.configure) ──
Shoulda::Matchers.configure do |shoulda_config|
  shoulda_config.integrate do |with|
    with.test_framework :rspec
    with.library :rails
  end
end