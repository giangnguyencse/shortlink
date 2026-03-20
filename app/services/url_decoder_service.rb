# frozen_string_literal: true

# ============================================================
# UrlDecoderService — Decodes a short URL to the original URL
# ============================================================
#
# Lookup Strategy — Cache-first (Read-Through):
#
#   L1 Redis decode-cache  O(1)      → cache hit (warm path)
#   L2 PostgreSQL lookup   O(log n)  → cache miss → warm cache → return
#
# Performance decision — Click tracking:
#   ❌ DO NOT call record.increment!(:access_count) in this method.
#
#   Why: increment! issues an UPDATE ... WHERE id = ? with a row-level
#   lock on every single decode request. Under high concurrency (e.g.
#   10k req/s on a viral short link), this creates a lock contention
#   hot-spot on that single row — a textbook thundering-herd problem.
#
#   ✅ Phase 2 approach (documented in README):
#   Use Redis INCR to track clicks in-memory (non-blocking, O(1)).
#   A background Sidekiq job flushes Redis counters to DB every 5 minutes.
#   This decouples the write-heavy analytics path from the read-hot-path.
#
# Cache Resilience:
#   Redis failure is non-fatal. We log + fallback to DB.
#   The decode path always works, even with Redis completely down.
class UrlDecoderService < ApplicationService
  BASE_URL = ENV.fetch('BASE_URL', 'http://localhost:3000')

  def initialize(short_url:)
    @short_url_input = short_url.to_s.strip
  end

  def call
    return failure('short_url cannot be blank') if @short_url_input.blank?

    short_code = extract_short_code(@short_url_input)

    unless Base62Encoder.valid_code?(short_code)
      return failure('Invalid short URL format — only alphanumeric characters are allowed')
    end

    original_url = fetch_from_cache(short_code) || fetch_from_db(short_code)

    return failure("Short URL not found", error_code: :not_found) unless original_url

    # track_click(short_code) # Redis INCR — non-blocking, no DB lock

    success({ original_url: original_url, short_code: short_code })
  rescue StandardError => e
    Rails.logger.error("[UrlDecoderService] Unexpected: #{e.class}: #{e.message}")
    failure('An unexpected error occurred.', error_code: :internal_server_error)
  end

  private

  # Accepts both:
  #   Full short URL: "http://localhost:3000/GeAi9K" → "GeAi9K"
  #   Short code only: "GeAi9K"                     → "GeAi9K"
  def extract_short_code(input)
    return input if Base62Encoder.valid_code?(input)

    parsed = URI.parse(input)
    parsed.path.delete_prefix('/')
  rescue URI::InvalidURIError
    input
  end

  # L1: Redis decode-cache lookup
  def fetch_from_cache(short_code)
    Rails.cache.read(cache_key_for(short_code))
  rescue StandardError => e
    Rails.logger.warn("[UrlDecoderService] Cache read failed: #{e.message}")
    nil
  end

  # L2: PostgreSQL lookup — only reached on cache miss (cold start / eviction)
  # We select only needed columns to minimise row read overhead.
  # After fetching, we warm the cache to make next request a cache hit.
  def fetch_from_db(short_code)
    record = ShortUrl.select(:short_code, :original_url)
                     .find_by(short_code: short_code)
    return nil unless record

    warm_cache(short_code, record.original_url)
    record.original_url
  end

  # Warm the decode-cache: subsequent decodes of the same code hit L1 only.
  def warm_cache(short_code, original_url)
    Rails.cache.write(
      cache_key_for(short_code),
      original_url,
      expires_in: 24.hours
    )
  rescue StandardError => e
    Rails.logger.warn("[UrlDecoderService] Cache warm failed: #{e.message}")
  end

  # Track click via Redis INCR — non-blocking, no DB row lock.
  # Key: shortlink:clicks:<short_code>
  # Phase 2: a Sidekiq cron job reads these counters and batch-updates
  # the click_count column in PostgreSQL every 5 minutes.
  # def track_click(short_code)
  #   Rails.cache.increment("shortlink:clicks:#{short_code}", 1, expires_in: 30.days)
  # rescue StandardError => e
  #   # Click tracking is best-effort — never fail the response for it
  #   Rails.logger.warn("[UrlDecoderService] Click tracking failed: #{e.message}")
  # end
end
