# frozen_string_literal: true

require 'rails_helper'

RSpec.describe UrlDecoderService do
  let!(:short_url_record) do
    create(:short_url,
           short_code:   'GeAi9K',
           original_url: 'https://codesubmit.io/library/react')
  end

  # ── Cache Hit (L1 — hot path) ─────────────────────────────

  context 'with a cache hit' do
    before { Rails.cache.write('shortlink:decode:GeAi9K', 'https://cached.com') }

    subject(:result) { described_class.call(short_url: 'GeAi9K') }

    it 'returns the cached original URL' do
      expect(result).to be_success
      expect(result.value[:original_url]).to eq('https://cached.com')
    end

    it 'does NOT hit the database' do
      expect(ShortUrl).not_to receive(:select)
      result
    end
  end

  # ── Cache Miss → DB Hit (L2) ──────────────────────────────

  context 'with a cache miss (cold cache → DB lookup)' do
    before { Rails.cache.clear }

    subject(:result) { described_class.call(short_url: 'GeAi9K') }

    it 'returns success' do
      expect(result).to be_success
    end

    it 'returns the original URL from DB' do
      expect(result.value[:original_url]).to eq('https://codesubmit.io/library/react')
    end

    it 'returns the short_code' do
      expect(result.value[:short_code]).to eq('GeAi9K')
    end

    it 'warms the cache after DB lookup (next request is L1 hit)' do
      result
      expect(Rails.cache.read('shortlink:decode:GeAi9K')).to eq('https://codesubmit.io/library/react')
    end
  end

  # ── Full Short URL Input ──────────────────────────────────

  context 'with a full short URL (not just code)' do
    before { Rails.cache.clear }

    subject(:result) { described_class.call(short_url: 'http://localhost:3000/GeAi9K') }

    it 'extracts the code and decodes correctly' do
      expect(result).to be_success
      expect(result.value[:original_url]).to eq('https://codesubmit.io/library/react')
    end
  end

  # ── Persistence After Restart ─────────────────────────────

  context 'after simulated server restart (Redis cleared)' do
    before { Rails.cache.clear } # clear all caches = "restart" scenario

    subject(:result) { described_class.call(short_url: 'GeAi9K') }

    it 'still decodes correctly from the database' do
      expect(result).to be_success
      expect(result.value[:original_url]).to eq('https://codesubmit.io/library/react')
    end
  end

  # ── Redis Resilience ─────────────────────────────────────

  context 'when Redis is completely unavailable' do
    before do
      allow(Rails.cache).to receive(:read).and_raise(Redis::CannotConnectError)
    end

    subject(:result) { described_class.call(short_url: 'GeAi9K') }

    it 'falls back to DB and succeeds' do
      expect(result).to be_success
      expect(result.value[:original_url]).to eq('https://codesubmit.io/library/react')
    end
  end

  # ── Failure Cases ─────────────────────────────────────────

  context 'with a non-existent short code' do
    subject(:result) { described_class.call(short_url: 'XXXXX') }

    it 'returns failure' do
      expect(result).to be_failure
    end

    it 'returns :not_found error code' do
      expect(result.error_code).to eq(:not_found)
    end
  end

  context 'with a blank short_url' do
    subject(:result) { described_class.call(short_url: '') }

    it { expect(result).to be_failure }
  end

  context 'with invalid characters in short_url (injection attempt)' do
    subject(:result) { described_class.call(short_url: "'; DROP TABLE short_urls; --") }

    it 'returns failure without hitting the DB' do
      expect(ShortUrl).not_to receive(:select)
      expect(result).to be_failure
    end
  end
end
