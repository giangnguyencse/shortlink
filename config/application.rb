# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Shortlink
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.1

    # API-only application
    config.api_only = true

    # Time zone
    config.time_zone = 'UTC'

    # Auto-load lib directory (ignore tasks)
    config.autoload_lib(ignore: %w[tasks])

    # Custom autoload paths
    config.autoload_paths += %W[
      #{root}/app/services
      #{root}/app/validators
      #{root}/app/serializers
    ]

    # Use Rack::Attack middleware
    config.middleware.use Rack::Attack

    # Cache store: Redis
    config.cache_store = :redis_cache_store, {
      url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
      pool_size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
      pool_timeout: 5,
      namespace: 'shortlink',
      expires_in: 24.hours,
      error_handler: lambda { |method:, returning:, exception:|
        Rails.logger.error(
          "[RedisCache] Error on #{method}: #{exception.class}: #{exception.message}"
        )
      }
    }

    # Use ActiveSupport::Logger
    config.logger = ActiveSupport::TaggedLogging.new(
      ActiveSupport::Logger.new($stdout)
    )

    # Log level
    config.log_level = ENV.fetch('LOG_LEVEL', 'info').to_sym
  end
end
