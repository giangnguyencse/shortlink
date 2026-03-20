# frozen_string_literal: true

# ============================================================
# ShortUrl — Core domain model
# ============================================================
#
# Schema (Phase 1):
#   short_code   varchar(20)  UNIQUE NOT NULL  — Base62-encoded ID from PG SEQUENCE
#   original_url varchar(2048) NOT NULL        — target URL (varchar not text for BTREE index)
#   url_digest   varchar(64)  UNIQUE NOT NULL  — SHA256 hex for O(1) idempotency lookup
#   expires_at   datetime     nullable         — Phase 2: TTL for expiring links
#   click_count  integer      default 0        — Phase 2: flushed from Redis by background job
#
# Why varchar(2048) not text for original_url?
#   PostgreSQL cannot create a standard BTREE index on a TEXT column without
#   specifying a length. VARCHAR(2048) allows us to add an index later if needed,
#   and matches the browser URL max-length spec (RFC 7230).
#
# Why is access_count NOT incremented in the hot decode path?
#   increment! issues a row-level UPDATE lock per request.
#   Under high concurrency, this is a thundering-herd bottleneck.
#   Instead, we use Redis INCR (O(1), non-blocking) and batch-flush
#   to click_count via a background job every 5 minutes. (Phase 2)
class ShortUrl < ApplicationRecord
  # ── Validations ───────────────────────────────────────────

  validates :original_url,
            presence: true,
            url: { check_ssrf: false },
            length: { maximum: 2048, message: 'exceeds 2048 character limit' }

  validates :short_code,
            presence: true,
            uniqueness: { case_sensitive: true },
            length: { in: 1..20 },
            format: {
              with: /\A[0-9a-zA-Z]+\z/,
              message: 'must contain only alphanumeric characters (Base62)'
            }

  validates :url_digest,
            presence: true,
            uniqueness: true,
            length: { is: 64 },
            format: {
              with: /\A[a-f0-9]+\z/,
              message: 'must be a valid SHA256 hex string'
            }

  validates :click_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  before_validation :normalize_url

  scope :active, lambda {
    where(expires_at: nil).or(where(arel_table[:expires_at].gt(Time.current)))
  }

  scope :expired, lambda {
    where.not(expires_at: nil).where(arel_table[:expires_at].lteq(Time.current))
  }

  scope :recent, -> { order(created_at: :desc) }

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !expired?
  end

  def short_url(base_url = ENV.fetch('BASE_URL', 'http://localhost:3000'))
    "#{base_url}/#{short_code}"
  end

  private

  def normalize_url
    self.original_url = original_url&.strip
  end
end
