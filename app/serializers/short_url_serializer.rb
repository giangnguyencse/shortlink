# frozen_string_literal: true

# ============================================================
# ShortUrlSerializer — Formats ShortUrl response data
# ============================================================
# PORO (Plain Old Ruby Object) — no gem dependency.
# Explicit JSON shape: we control exactly what fields are exposed.
#
# click_count is intentionally excluded from the API response
# (it's a Phase 2 internal analytics metric, not a client-facing field).
class ShortUrlSerializer
  def initialize(short_url, base_url: nil)
    @short_url = short_url
    @base_url  = base_url || ENV.fetch('BASE_URL', 'http://localhost:3000')
  end

  def as_json(*)
    {
      short_url:    "#{@base_url}/#{@short_url.short_code}",
      short_code:   @short_url.short_code,
      original_url: @short_url.original_url,
      created_at:   @short_url.created_at&.iso8601
    }.compact
  end
end
