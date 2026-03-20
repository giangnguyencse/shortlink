# frozen_string_literal: true

# ============================================================
# KeyGenerationService — Standalone KGS implementation
# ============================================================
class KeyGenerationService
  REDIS_KEY = 'shortlink:kgs:available_keys'
  LOCK_KEY  = 'shortlink:kgs:replenish_lock'
  BATCH_SIZE = ENV.fetch('KGS_BATCH_SIZE', 20000).to_i
  THRESHOLD  = ENV.fetch('KGS_THRESHOLD', 5000).to_i

  class << self
    def pop_key
      key = REDIS_POOL.with { |redis| redis.lpop(REDIS_KEY) }

      if key
        # Nếu lấy thành công, ta âm thầm kiểm tra xem có cần bơm thêm không
        # Đẩy việc kiểm tra vào một thread ngầm để KHÔNG BLOCK request của user
        replenish_async_if_needed
      else
        # Fallback khẩn cấp: Giỏ thực sự cạn (rất hiếm khi xảy ra nếu async chạy tốt)
        generate_batch!
        key = REDIS_POOL.with { |redis| redis.lpop(REDIS_KEY) }
      end

      key
    end

    def pool_size
      REDIS_POOL.with { |redis| redis.llen(REDIS_KEY) }
    end

    private

    def replenish_async_if_needed
      # Gọi LLEN là O(1) nên rất nhẹ, nhưng ta vẫn ném nó vào Thread để tách biệt
      Thread.new do
        begin
          if pool_size < THRESHOLD
            # Dùng tính năng SET NX (Set if Not eXists) của Redis làm Khóa.
            # Khóa này tự động bay màu sau 10 giây (để phòng hờ server đang bơm bị sập).
            lock_acquired = REDIS_POOL.with do |redis|
              redis.set(LOCK_KEY, 'locked', nx: true, ex: 10)
            end

            # Chỉ server nào giật được Khóa mới được phép đi gọi Database
            if lock_acquired
              Rails.logger.info("[KGS] Pool running low. Replenishing in background...")
              generate_batch!
              
              # Bơm xong thì thả khóa ra cho lần sau
              REDIS_POOL.with { |redis| redis.del(LOCK_KEY) }
            end
          end
        rescue StandardError => e
          Rails.logger.error("[KGS] Async replenish error: #{e.message}")
        end
      end
    end

    def generate_batch!
      result = ActiveRecord::Base.connection.execute(<<~SQL)
        SELECT nextval('short_url_counter') 
        FROM generate_series(1, #{BATCH_SIZE});
      SQL

      new_keys = result.map do |row|
        Base62Encoder.encode(row['nextval'].to_i)
      end.shuffle

      REDIS_POOL.with { |redis| redis.rpush(REDIS_KEY, new_keys) }
    end
  end
end