# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UrlEncoderService do
  subject(:result) { described_class.call(original_url: original_url) }

  let(:original_url) { 'https://codesubmit.io/library/react' }

  before do
    # Stub PostgreSQL sequence call so tests don't need a real sequence
    seq_result = [{ 'nextval' => 1_234_567 }]
    allow(ActiveRecord::Base.connection).to receive(:execute)
      .with("SELECT nextval('short_url_counter')")
      .and_return(seq_result)
  end

  # ── Happy Path ────────────────────────────────────────────

  context 'with a valid URL (first encode — cold cache)' do
    it 'returns a successful result' do
      expect(result).to be_success
    end

    it 'creates a ShortUrl record in the DB' do
      expect { result }.to change(ShortUrl, :count).by(1)
    end

    it 'returns short_url, short_code, and original_url' do
      expect(result.value).to include(:short_url, :short_code, :original_url)
    end

    it 'returns the original_url unchanged' do
      expect(result.value[:original_url]).to eq(original_url)
    end

    it 'returns a valid Base62 short_code' do
      expect(result.value[:short_code]).to match(/\A[0-9a-zA-Z]+\z/)
    end
  end

  # ── 3-Level Cache: Idempotency ────────────────────────────

  context 'when encoding the same URL twice (L1 cache hit on second call)' do
    it 'returns the same short_code for both calls' do
      first  = described_class.call(original_url: original_url)
      second = described_class.call(original_url: original_url)
      expect(first.value[:short_code]).to eq(second.value[:short_code])
    end

    it 'creates only ONE DB record' do
      described_class.call(original_url: original_url)
      expect { described_class.call(original_url: original_url) }
        .not_to change(ShortUrl, :count)
    end

    it 'does NOT call nextval on the second encode (L1 cache hit)' do
      described_class.call(original_url: original_url) # primes L1 cache
      # Second call should hit Redis and never need the sequence
      expect(ActiveRecord::Base.connection).not_to receive(:execute)
        .with("SELECT nextval('short_url_counter')")
      described_class.call(original_url: original_url)
    end
  end

  context 'cold cache + DB has record (L2 hit — e.g. after restart)' do
    let!(:existing) { create(:short_url, url_digest: Digest::SHA256.hexdigest(original_url.downcase)) }

    before { Rails.cache.clear } # simulate cold cache

    it 'finds the existing record from DB' do
      expect(result).to be_success
      expect(result.value[:short_code]).to eq(existing.short_code)
    end

    it 'does not create a duplicate DB record' do
      expect { result }.not_to change(ShortUrl, :count)
    end

    it 'warms the L1 cache after DB lookup' do
      result
      digest = Digest::SHA256.hexdigest(original_url.downcase)
      cached = Rails.cache.read("shortlink:encode:digest:#{digest}")
      expect(cached).to include('short_code' => existing.short_code)
    end
  end

  # ── Decode Cache Warming ─────────────────────────────────

  context 'after encoding a new URL' do
    it 'warms the decode-cache for the new short_code' do
      result
      short_code = result.value[:short_code]
      expect(Rails.cache.read("shortlink:decode:#{short_code}")).to eq(original_url)
    end
  end

  # ── Redis Resilience ─────────────────────────────────────

  context 'when Redis is unavailable' do
    before { allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError) }

    it 'still succeeds by falling through to DB (graceful degradation)' do
      expect(result).to be_success
    end

    it 'still persists the record to DB' do
      expect { result }.to change(ShortUrl, :count).by(1)
    end
  end

  # ── Concurrent Race Condition ─────────────────────────────

  context 'when a RecordNotUnique is raised (concurrent encode race)' do
    let!(:existing) { create(:short_url, url_digest: Digest::SHA256.hexdigest(original_url.downcase)) }

    before do
      allow(Rails.cache).to receive(:read).and_return(nil) # simulate cold cache
      call_count = 0
      allow(ShortUrl).to receive(:find_by).and_wrap_original do |m, *args|
        call_count += 1
        call_count == 1 ? nil : m.call(*args) # first check returns nil, then insert raises
      end
      allow(ShortUrl).to receive(:create).and_raise(ActiveRecord::RecordNotUnique)
    end

    it 'recovers and returns the winning record' do
      expect(result).to be_success
      expect(result.value[:short_code]).to eq(existing.short_code)
    end
  end

  # ── Failure Cases ────────────────────────────────────────

  context 'with a blank URL' do
    let(:original_url) { '' }

    it 'returns failure' do
      expect(result).to be_failure
    end

    it 'does not create a DB record' do
      expect { result }.not_to change(ShortUrl, :count)
    end
  end

  context 'with an FTP URL' do
    let(:original_url) { 'ftp://files.example.com' }
    it { expect(result).to be_failure }
  end

  context 'with a URL exceeding 2048 characters' do
    let(:original_url) { "https://example.com/#{'a' * 2050}" }
    it { expect(result).to be_failure }
  end
end
