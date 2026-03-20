# frozen_string_literal: true

# ============================================================
# Redis connection pool initializer
# ============================================================
# We use ConnectionPool to safely share Redis connections
# across threads (important for Puma multi-threaded server).

REDIS_POOL = ConnectionPool.new(
  size:    ENV.fetch('REDIS_POOL_SIZE', 5).to_i,
  timeout: ENV.fetch('REDIS_POOL_TIMEOUT', 3).to_i
) do
  Redis.new(
    url:            ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'),
    connect_timeout: 1,
    read_timeout:   0.5,
    write_timeout:  0.5,
    reconnect_attempts: 2
  )
end

# Also configure Rails.cache to use the same Redis URL
# (already set in config/application.rb and environments)
Rails.logger.info("[Redis] Connection pool initialized (size=#{ENV.fetch('REDIS_POOL_SIZE', 5)})")
