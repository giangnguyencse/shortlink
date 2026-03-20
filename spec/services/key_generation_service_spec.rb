# frozen_string_literal: true

require 'rails_helper'

RSpec.describe KeyGenerationService, type: :service do
  let(:redis_mock) { instance_double(Redis) }
  let(:db_connection) { ActiveRecord::Base.connection }

  before do
    # 1. Chặn không cho gọi tới Redis thật, thay bằng redis_mock
    allow(REDIS_POOL).to receive(:with).and_yield(redis_mock)
    
    # 2. Ép Thread chạy đồng bộ (synchronous) ngay lập tức trong lúc test
    # Thay vì sinh ra luồng mới chạy ngầm, rspec sẽ chạy thẳng code bên trong
    allow(Thread).to receive(:new).and_yield
  end

  describe '.pop_key' do
    context 'when the pool is completely empty (Cold Start / Critical Fallback)' do
      before do
        # Lần lpop đầu tiên trả về nil (cạn đáy), lần thứ 2 trả về key sau khi đã bơm
        allow(redis_mock).to receive(:lpop).with(KeyGenerationService::REDIS_KEY).and_return(nil, 'FallBck')
        allow(KeyGenerationService).to receive(:generate_batch!)
      end

      it 'synchronously generates a batch and returns the new key' do
        result = KeyGenerationService.pop_key

        expect(result).to eq('FallBck')
        expect(KeyGenerationService).to have_received(:generate_batch!).once
      end
    end

    context 'when the pool has keys but is BELOW the threshold' do
      before do
        allow(redis_mock).to receive(:lpop).with(KeyGenerationService::REDIS_KEY).and_return('LowPoolKey')
        allow(redis_mock).to receive(:llen).with(KeyGenerationService::REDIS_KEY).and_return(KeyGenerationService::THRESHOLD - 1)
        allow(KeyGenerationService).to receive(:generate_batch!)
      end

      it 'triggers async replenishment if it successfully acquires the Redis lock' do
        # Giả lập giật được khóa thành công
        allow(redis_mock).to receive(:set).with(KeyGenerationService::LOCK_KEY, 'locked', nx: true, ex: 10).and_return(true)
        allow(redis_mock).to receive(:del).with(KeyGenerationService::LOCK_KEY)

        result = KeyGenerationService.pop_key

        expect(result).to eq('LowPoolKey')
        expect(KeyGenerationService).to have_received(:generate_batch!).once
        expect(redis_mock).to have_received(:del).with(KeyGenerationService::LOCK_KEY).once
      end

      it 'does NOT replenish if the lock is already held by another worker' do
        # Giả lập khóa đang bị worker khác giữ (trả về false)
        allow(redis_mock).to receive(:set).with(KeyGenerationService::LOCK_KEY, 'locked', nx: true, ex: 10).and_return(false)

        result = KeyGenerationService.pop_key

        expect(result).to eq('LowPoolKey')
        # Không được phép gọi db để sinh thêm key
        expect(KeyGenerationService).not_to have_received(:generate_batch!)
      end
    end

    context 'when the pool is healthy (ABOVE threshold)' do
      before do
        allow(redis_mock).to receive(:lpop).with(KeyGenerationService::REDIS_KEY).and_return('HealthyKey')
        allow(redis_mock).to receive(:llen).with(KeyGenerationService::REDIS_KEY).and_return(KeyGenerationService::THRESHOLD + 100)
        allow(KeyGenerationService).to receive(:generate_batch!)
      end

      it 'returns the key instantly and does nothing else' do
        result = KeyGenerationService.pop_key

        expect(result).to eq('HealthyKey')
        expect(KeyGenerationService).not_to have_received(:generate_batch!)
      end
    end
  end

  describe '.pool_size' do
    it 'returns the current length of the Redis list' do
      allow(redis_mock).to receive(:llen).with(KeyGenerationService::REDIS_KEY).and_return(1234)
      expect(KeyGenerationService.pool_size).to eq(1234)
    end
  end

  describe '.generate_batch! (Private Mechanism)' do
    it 'fetches sequences from PostgreSQL, encodes to Base62, and pushes to Redis' do
      # 1. Giả lập Database trả về 2 kết quả
      mock_db_result = [{ 'nextval' => 1000 }, { 'nextval' => 1001 }]
      allow(db_connection).to receive(:execute).with(/SELECT nextval/).and_return(mock_db_result)

      # 2. Giả lập thuật toán Base62
      allow(Base62Encoder).to receive(:encode).with(1000).and_return('aBc')
      allow(Base62Encoder).to receive(:encode).with(1001).and_return('xYz')

      # 3. Theo dõi lệnh gọi Redis RPUSH
      allow(redis_mock).to receive(:rpush)

      # Gọi hàm private (trong test dùng send để gọi)
      KeyGenerationService.send(:generate_batch!)

      # Verify Database được gọi đúng lệnh
      expect(db_connection).to have_received(:execute).with(/generate_series/)
      
      # Verify Redis RPUSH nhận được mảng chứa 2 key đã mã hóa (bỏ qua thứ tự do hàm shuffle)
      expect(redis_mock).to have_received(:rpush).with(
        KeyGenerationService::REDIS_KEY,
        array_including('aBc', 'xYz')
      )
    end
  end
end
