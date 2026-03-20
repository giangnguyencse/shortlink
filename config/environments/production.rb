# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = true
  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true

  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Redis Cache Store with connection pool
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'),
    # pool_size: ENV.fetch('RAILS_MAX_THREADS', 5).to_i,
    # pool_timeout: 5,
    namespace: 'shortlink',
    expires_in: 24.hours,
    reconnect_attempts: 1,
    error_handler: lambda { |method:, returning:, exception:|
      Rails.logger.error(
        "[RedisCache] #{method} failed: #{exception.class}: #{exception.message}"
      )
    }
  }

  config.log_level = ENV.fetch('LOG_LEVEL', 'info').to_sym
  config.log_tags = [:request_id]

  if ENV['RAILS_LOG_TO_STDOUT'].present?
    logger = ActiveSupport::Logger.new($stdout)
    logger.formatter = config.log_formatter
    config.logger = ActiveSupport::TaggedLogging.new(logger)
  end

  config.active_record.dump_schema_after_migration = false

  # Force SSL in production
  config.force_ssl = ENV.fetch('FORCE_SSL', 'true') == 'true'
end
