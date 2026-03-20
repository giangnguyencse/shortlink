# frozen_string_literal: true

# Rails.application.configure do
#   config.cache_classes = false
#   config.eager_load = false
#   config.consider_all_requests_local = true

#   if Rails.root.join('tmp/caching-dev.txt').exist?
#     config.action_controller.perform_caching = true
#     config.action_controller.enable_fragment_cache_logging = true
#     config.cache_store = :redis_cache_store, {
#       url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
#       namespace: 'shortlink_dev'
#     }
#     config.public_file_server.headers = {
#       'Cache-Control' => "public, max-age=#{2.days.to_i}"
#     }
#   else
#     config.action_controller.perform_caching = false
#     config.cache_store = :null_store
#   end

#   config.active_record.migration_error = :page_load
#   config.active_record.verbose_query_logs = true

#   config.log_level = :debug
#   config.log_tags = [:request_id]
#   config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
# end


# frozen_string_literal: true

Rails.application.configure do
  config.cache_classes = false
  config.eager_load = false
  config.consider_all_requests_local = true

  # ── ÉP BẬT CACHING TRONG DEVELOPMENT ĐỂ TEST REDIS ──
  config.action_controller.perform_caching = true
  config.action_controller.enable_fragment_cache_logging = true
  
  # Cấu hình Redis Cache Store
  # Lưu ý: Fallback URL dùng host 'redis' thay vì 'localhost' để chạy mượt trên Docker
  config.cache_store = :redis_cache_store, {
    url: ENV.fetch('REDIS_URL', 'redis://redis:6379/0'),
    namespace: 'shortlink_dev'
  }
  
  config.public_file_server.headers = {
    'Cache-Control' => "public, max-age=#{2.days.to_i}"
  }
  # ────────────────────────────────────────────────────

  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true

  config.log_level = :debug
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.new(ActiveSupport::Logger.new($stdout))
end