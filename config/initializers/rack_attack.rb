# frozen_string_literal: true

# ============================================================
# Rack::Attack — Rate limiting & security middleware
# ============================================================
# Protects against:
#   - Brute force URL enumeration
#   - Spam encoding (DoS)
#   - Abusive clients

class Rack::Attack
  # ── Throttles (Rate Limiting) ─────────────────────────────

  # Encode: max 10 requests per minute per IP
  throttle('encode/ip', limit: ENV.fetch('ENCODE_RATE_LIMIT', 10).to_i,
                        period: ENV.fetch('THROTTLE_PERIOD', 60).to_i.seconds) do |req|
    req.ip if req.path == '/api/v1/encode' && req.post?
  end

  # Decode: max 30 requests per minute per IP
  throttle('decode/ip', limit: ENV.fetch('DECODE_RATE_LIMIT', 30).to_i,
                        period: ENV.fetch('THROTTLE_PERIOD', 60).to_i.seconds) do |req|
    req.ip if req.path == '/api/v1/decode' && req.post?
  end

  # Global: max 100 any requests per minute per IP (safety net)
  throttle('global/ip', limit: 100, period: 1.minute) do |req|
    req.ip unless req.path == '/health'
  end

  # ── Blocklist: Suspicious Patterns ───────────────────────

  # Block requests with obviously malicious User-Agents
  BLOCKLISTED_UA = /sqlmap|nikto|nmap|masscan|nuclei/i

  blocklist('block/suspicious_ua') do |req|
    req.user_agent&.match?(BLOCKLISTED_UA)
  end

  # ── Custom Response (JSON instead of plain text) ─────────

  self.throttled_responder = lambda do |request|
    retry_after = (request.env['rack.attack.match_data'] || {})[:period]
    [
      429,
      {
        'Content-Type' => 'application/json',
        'Retry-After'  => retry_after.to_s
      },
      [
        {
          errors: ['Rate limit exceeded. Please slow down.'],
          meta: { retry_after: retry_after }
        }.to_json
      ]
    ]
  end

  # ── Logging ───────────────────────────────────────────────

  ActiveSupport::Notifications.subscribe('throttle.rack_attack') do |_name, _start, _finish, _id, payload|
    req = payload[:request]
    Rails.logger.warn(
      "[Rack::Attack] Throttled #{req.ip} → #{req.path} | " \
      "match_type=#{req.env['rack.attack.match_type']} " \
      "match_key=#{req.env['rack.attack.match_key']}"
    )
  end
end
