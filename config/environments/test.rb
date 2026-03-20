# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = true
  config.eager_load = false

  config.public_file_server.enabled = true
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{1.hour.to_i}"
  }

  config.consider_all_requests_local = true
  config.action_controller.perform_caching = false

  # Use null cache store in test to avoid Redis dependency
  config.cache_store = :null_store

  config.active_record.maintain_test_schema = true

  config.log_level = :warn
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))

  # ActionMailer
  config.action_mailer.delivery_method = :test
end
