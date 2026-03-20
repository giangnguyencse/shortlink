# frozen_string_literal: true

class CreateShortUrls < ActiveRecord::Migration[7.1]
  def up
    # ──────────────────────────────────────────────────────────────
    # PostgreSQL Sequence for collision-free short code generation
    # ──────────────────────────────────────────────────────────────
    # Using a DB sequence (instead of random generation) guarantees:
    #   1. No collision — every nextval() is unique and atomic
    #   2. No retry loop needed
    #   3. Thread-safe and multi-process safe
    #
    # We start at 56800235584 so Base62 codes are always 7+ chars.
    # Scaling: each distributed node can own a range of the sequence.
    execute <<-SQL
      CREATE SEQUENCE IF NOT EXISTS short_url_counter START 56800235584 INCREMENT 1 NO CYCLE;
    SQL
    create_table :short_urls do |t|
      # Base62-encoded short code (e.g., "GeAi9K")
      t.string  :short_code,   null: false, limit: 20

      # Original long URL (max 2048 chars — browser URL limit)
      # VARCHAR(2048) allows B-Tree index vs TEXT which does not
      t.string  :original_url, null: false, limit: 2048

      # SHA256 hex digest of the normalized original_url.
      # Used for O(1) idempotency check — same URL → same record.
      # Avoids full-text varchar scan.
      t.string  :url_digest,   null: false, limit: 64

      # ── Phase 2 / SaaS Features (columns reserved, not active) ─
      #
      # expires_at: TTL for expiring links (TinyURL premium feature).
      # Not active in Phase 1 — no expiry logic written yet.
      # Cleanup via background job (e.g., Sidekiq cron) in Phase 2.
      t.datetime :expires_at

      # click_count: Intentionally NOT incremented on the hot decode
      # path to avoid per-request row-level locks under concurrency.
      # Phase 2 plan: Redis INCR on each decode → batch-flush to DB
      # via a scheduled job (e.g., every 5 minutes).
      t.integer  :click_count, null: false, default: 0

      t.timestamps null: false
    end

    # ── Indexes ──────────────────────────────────────────────────

    # Hot read path: short_code → original_url (BTREE, O(log n))
    add_index :short_urls, :short_code, unique: true, name: 'idx_short_urls_short_code'

    # Idempotency check: url_digest → existing record (BTREE, O(log n))
    # Fixed-length SHA256 hex (64 chars) → highly efficient index
    add_index :short_urls, :url_digest, unique: true, name: 'idx_short_urls_url_digest'

    # Partial index for Phase 2 expiry cleanup queries.
    # Only indexes rows that actually have an expiry set.
    add_index :short_urls, :expires_at,
              name:  'idx_short_urls_expires_at',
              where: 'expires_at IS NOT NULL'

  end

  def down
    execute "DROP SEQUENCE short_url_counter;"
    drop_table :short_urls
  end
end
