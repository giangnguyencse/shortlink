# frozen_string_literal: true

# ============================================================
# UrlEncoderService — Encodes a long URL to a short URL
# ============================================================
#
# Lookup Strategy — 3 levels, fast path first:
#
#   L1 Redis encode-cache  O(1)      → same URL? return instantly, zero DB
#   L2 PostgreSQL lookup   O(log n)  → cache miss but URL exists → warm L1
#   L3 Insert new record   O(log n)  → new URL → SEQUENCE → persist → warm both caches
#
# Why 3-level not 2-level?
#   The encode endpoint is called repeatedly for the same popular URLs (e.g.
#   social share buttons calling /encode on the same link thousands of times).
#   Without L1, each call hits PostgreSQL even though the answer never changes.
#   The encode-cache mapping (digest → short_code) is IMMUTABLE once created,
#   so a 7-day TTL is safe with zero risk of stale data.
#
# Collision Strategy:
#   PostgreSQL SEQUENCE (atomic, monotonically increasing).
#   No retry loops needed. No birthday paradox to worry about.
#
# Concurrency / Race Condition:
#   Two threads encoding the same URL simultaneously both pass the L1+L2 miss
#   checks before either inserts. The UNIQUE index on url_digest causes the
#   second INSERT to raise RecordNotUnique. We rescue and return the winner.
class UrlEncoderService < ApplicationService
  BASE_URL = ENV.fetch('BASE_URL', 'http://localhost:3000')

  def initialize(original_url:)
    @original_url = original_url.to_s.strip
  end

  def call
    return failure('URL cannot be blank') if @original_url.blank?

    digest = compute_digest(@original_url)

    # ── L1: Redis encode-cache (hot path, zero DB traffic) ────────
    # Key:   shortlink:encode:digest:<sha256_hex>
    # Value: { 'short_code' => ..., 'original_url' => ... }
    cached = fetch_encode_cache(digest)
    return success(build_response_from_cache(cached)) if cached

    # ── L2: DB lookup — handles restarts / cold cache scenarios ───
    existing = ShortUrl.find_by(url_digest: digest)
    if existing
      warm_encode_cache(digest, existing) # prime L1 for next call
      return success(serialize(existing))
    end

    # ── L3: New URL — allocate unique ID, persist, warm both caches
    short_url = build_and_save(digest)

    if short_url.persisted?
      warm_encode_cache(digest, short_url)  # L1: idempotency cache
      warm_decode_cache(short_url)          # L1: decode hot-path cache
      success(serialize(short_url))
    else
      failure(short_url.errors.full_messages)
    end
  rescue ActiveRecord::RecordNotUnique
    # Race condition: concurrent encodes of the same URL both passed
    # L1+L2 miss checks. DB UNIQUE index on url_digest rejected the loser.
    # Safe to read the winner — result is identical for both callers.
    Rails.logger.warn("[UrlEncoderService] RecordNotUnique — concurrent encode for digest: #{digest}")
    winner = ShortUrl.find_by!(url_digest: digest)
    warm_encode_cache(digest, winner)
    success(serialize(winner))
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error("[UrlEncoderService] DB error: #{e.message}")
    failure('Database error. Please try again.', error_code: :service_unavailable)
  rescue StandardError => e
    Rails.logger.error("[UrlEncoderService] Unexpected: #{e.class}: #{e.message}")
    failure('An unexpected error occurred.', error_code: :internal_server_error)
  end

  private

  def compute_digest(url)
    Digest::SHA256.hexdigest(url.downcase)
  end

  def build_and_save(digest)
    short_code = KeyGenerationService.pop_key
    ShortUrl.create(
      original_url: @original_url,
      url_digest:   digest,
      short_code:   short_code
    )
  end

  # Atomic, collision-free ID from PostgreSQL sequence.
  # Thread-safe: nextval() is never returned twice, even under concurrency.
  # def next_sequence_value
  #   result = ActiveRecord::Base.connection.execute("SELECT nextval('short_url_counter')")
  #   result.first['nextval'].to_i
  # end


  def fetch_encode_cache(digest)
    Rails.cache.read(encode_cache_key(digest))
  rescue StandardError => e
    Rails.logger.warn("[UrlEncoderService] Encode-cache read failed: #{e.message}")
    nil
  end

  # Encode-idempotency cache: digest → { short_code, original_url }
  # Mapping is immutable once created → long TTL (7 days) is safe.
  def warm_encode_cache(digest, short_url)
    Rails.cache.write(
      encode_cache_key(digest),
      { 'short_code' => short_url.short_code, 'original_url' => short_url.original_url },
      expires_in: 7.days
    )
  rescue StandardError => e
    Rails.logger.warn("[UrlEncoderService] Encode-cache write failed: #{e.message}")
  end

  # Decode-path cache: short_code → original_url
  # Warmed here so the very first decode after encode is also a cache hit.
  def warm_decode_cache(short_url)
    Rails.cache.write(
      cache_key_for(short_url.short_code),
      short_url.original_url,
      expires_in: 24.hours
    )
  rescue StandardError => e
    Rails.logger.warn("[UrlEncoderService] Decode-cache write failed: #{e.message}")
  end

  def encode_cache_key(digest)
    "shortlink:encode:digest:#{digest}"
  end

  def build_response_from_cache(cached)
    {
      short_url:    "#{BASE_URL}/#{cached['short_code']}",
      short_code:   cached['short_code'],
      original_url: cached['original_url']
    }
  end

  def serialize(short_url)
    ShortUrlSerializer.new(short_url, base_url: BASE_URL).as_json
  end
end
