# ShortLink — URL Shortening Service

A production-grade URL shortening service built with **Ruby on Rails 7.1 API-only**,
demonstrating senior engineering practices: clean architecture, performance, security, and scalability.

## Quick Start

```bash
git clone <repo-url> && cd shortlink
cp .env.example .env
docker-compose up -d         # Starts PostgreSQL + Redis
bundle install
rails db:create db:migrate
rails server -p 3000
```

## API Reference

### `POST /api/v1/encode` — Encode a URL

**Request:**

```bash
{
  "url": "https://github.com/resources/articles?topic=software-development"
}
```


```bash
curl -X POST http://localhost:3000/api/v1/encode \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/resources/articles?topic=software-development"}'
```

**Response `201 Created`:**
```json
{
  "data": {
    "short_url": "http://localhost:3000/Kmmm1ZE",
    "short_code": "Kmmm1ZE",
    "original_url": "https://github.com/resources/articles?topic=software-development",
    "created_at": "2026-03-20T03:47:53Z"
  },
  "meta": { "request_id": "8eea66d8-7be9-41f6-832f-29ed5a586662" }
}
```

---

### `POST /api/v1/decode` — Decode a short URL

**Request** (accepts full URL **or** just the code):
```bash
curl -X POST http://localhost:3000/api/v1/decode \
  -H "Content-Type: application/json" \
  -d '{"short_url": "http://localhost:3000/4c92"}'
```

**Response `200 OK`:**
```json
{
  "data": {
    "original_url": "https://codesubmit.io/library/react",
    "short_code": "4c92"
  },
  "meta": { "request_id": "550e8400-..." }
}
```

---

## Architecture

### Design Patterns

| Layer | Pattern | Rationale |
|---|---|---|
| **Service** | Service Object | Thin controllers, single-responsibility business logic |
| **Result** | Result Monad (`ServiceResult`) | No exception-driven control flow, explicit success/failure |
| **Encoding** | Pure Module (`Base62Encoder`) | Zero side effects, fully unit-testable |
| **Validation** | Custom Validator (`UrlValidator`) | Decoupled from model, reusable, testable in isolation |
| **Serializer** | PORO Serializer | Explicit JSON shape, zero gem dependency |

### Encoding Algorithm: Counter-based Base62

**How it works:**

1. Compute `SHA256(normalized_url)` → check for existing record (idempotency)
2. If new URL: call `SELECT nextval('short_url_counter')` — PostgreSQL atomic counter
3. Base62-encode the counter value → `short_code`
4. Persist to DB, write Redis cache (write-through)

**Why counter-based instead of random?**

| Approach | Collision Risk | Complexity | Thread Safety |
|---|---|---|---|
| Random (`SecureRandom`) | Grows with DB size (~birthday paradox) | Requires retry loop | ✅ with UNIQUE index |
| **Counter (PostgreSQL SEQUENCE)** | **Zero — monotonically increasing** | **No retry needed** | **✅ Atomic at DB level** |
| UUID | Zero | Short codes too long | ✅ |

**Alphabet:** `0-9 a-z A-Z` (62 chars)
**Code length:** starts at 4 chars (`nextval` starts at 1,000,000), grows logarithmically
**Capacity:** 62^7 ≈ **3.5 billion** unique URLs

---

## Security Analysis

### Attack Vectors & Mitigations

#### 1. Server-Side Request Forgery (SSRF)
**Threat:** Attacker encodes `http://169.254.169.254/latest/meta-data` (AWS metadata) or `http://192.168.1.1/admin` to probe internal infrastructure.

**Mitigation:**
- `UrlValidator` resolves hostname via DNS and blocks requests to:
  - `127.0.0.0/8` (loopback)
  - `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` (RFC 1918 private)
  - `169.254.0.0/16` (link-local — AWS/GCP metadata endpoints!)
  - `::1/128`, `fc00::/7`, `fe80::/10` (IPv6 private)
- Only `http` and `https` schemes accepted (blocks `file://`, `gopher://`, `dict://`)

#### 2. DoS via URL Spam / Flooding
**Threat:** Attacker floods `/encode` with millions of unique URLs, bloating the database.

**Mitigation:**
- Rack::Attack throttle: `10 req/min` per IP on `/encode`
- Max URL length: 2048 characters
- Global fallback throttle: 100 req/min per IP

#### 3. Brute Force Short Code Enumeration
**Threat:** Attacker iterates through all possible short codes to harvest encoded URLs.

**Mitigation:**
- Rack::Attack throttle: `30 req/min` per IP on `/decode`
- 62^7 ≈ 3.5 billion possible codes — makes enumeration impractical
- `access_count` monitoring can trigger alerts for unusual decode velocity

#### 4. Open Redirect Abuse
**Threat:** Service used to create deceptive short URLs for phishing (e.g., `short.url/XYZ` → `http://evil-phishing.com`).

**Mitigation:**
- API returns JSON only; it does NOT perform HTTP redirects
- No `302 Found` response — clients must explicitly decode
- **Future improvement:** Integrate [Google Safe Browsing API](https://developers.google.com/safe-browsing) to block known malicious URLs

#### 5. SQL Injection
**Threat:** Malicious input in `url` or `short_url` parameters.

**Mitigation:**
- All DB queries use ActiveRecord parameterized queries (no raw SQL with user input)
- `PostgreSQL SEQUENCE` call does not include user input
- Input validated and length-limited before any DB interaction

#### 6. Mass Assignment / Parameter Tampering
**Threat:** Attacker injects unexpected parameters to manipulate internal state.

**Mitigation:**
- Strong parameters (`params.permit(:url)`) in controller
- Model-level `validates` reject unexpected attributes

#### 7. Rate Limiting Bypass via IP Rotation
**Threat:** Attacker rotates IPs to bypass per-IP throttling.

**Mitigation (current):** Rack::Attack per-IP throttle
**Mitigation (production):** Combine with API key auth + per-key rate limits

#### 8. Suspicious User-Agent Blocklist
**Mitigation:** Rack::Attack blocklist blocks known scanner UAs (`sqlmap`, `nikto`, `nmap`, `nuclei`)

---

## Scalability Analysis

### Current Architecture Limitations

This is a single-node architecture. For a production system at scale, the following would need to evolve:

### Problem 1: Database as Single Point of Failure

**Current:** Single PostgreSQL node with SEQUENCE.

**Scale-up path:**
1. **Read replicas** for decode queries (reads far outnumber writes)
2. **PgBouncer** connection pooling (config already in `production.rb`: `prepared_statements: false`)
3. **Partitioning** by `short_code` prefix for very large tables

### Problem 2: Counter Bottleneck in Distributed Setup

In a multi-node deployment, all nodes share one PostgreSQL SEQUENCE. This is fine until:
- DB write latency becomes a bottleneck for encode throughput

**Solutions (in order of complexity):**

| Strategy | Description | Tradeoff |
|---|---|---|
| **Batch allocation** | Each node pre-allocates N IDs (`SEQUENCE INCREMENT BY 1000`) | Small wasted ID gaps |
| **Node partition** | Node 1: 0–1B, Node 2: 1B–2B, … | Fixed ceiling per node |
| **Redis INCR** | `INCR shortlink:counter` — ~10x faster than DB | Redis must be durable (`appendonly yes`) |
| **Twitter Snowflake** | Timestamp + node_id + sequence — globally unique | More complex |

### Problem 3: Cache Invalidation

**Current:** 24-hour TTL on Redis cache. If a URL's record is deleted, stale cache returns the deleted URL for up to 24 hours.

**Solution:** On delete, explicitly `Rails.cache.delete("shortlink:decode:#{short_code}")`.

### Problem 4: Hash Collision (Idempotency)

**SHA256 has 2^256 possible values** — collision probability is negligible (birthday paradox requires ~2^128 hashes for 50% collision chance). This is not a practical concern.

### Benchmark Estimates

| Operation | Latency (estimated) | Bottleneck |
|---|---|---|
| Decode (cache hit) | ~1ms | Redis |
| Decode (cache miss) | ~5–10ms | PostgreSQL BTREE index |
| Encode (new URL) | ~10–15ms | PostgreSQL SEQUENCE + INSERT |
| Encode (idempotent) | ~5ms | PostgreSQL index lookup |

---

## Running Tests

```bash
bundle exec rspec                          # All tests
bundle exec rspec spec/lib/               # Base62Encoder unit
bundle exec rspec spec/validators/        # UrlValidator (SSRF, scheme)
bundle exec rspec spec/models/            # ShortUrl model
bundle exec rspec spec/services/          # Business logic
bundle exec rspec spec/requests/          # Integration (full stack)
bundle exec rspec --format documentation  # Human-readable output
```

---

## Project Structure

```
app/
├── controllers/api/v1/
│   └── urls_controller.rb      # Thin: delegates to services
├── models/
│   └── short_url.rb            # Validations, scopes, callbacks
├── serializers/
│   └── short_url_serializer.rb # PORO — explicit JSON shape
├── services/
│   ├── application_service.rb  # Base Service Object
│   ├── service_result.rb       # Result Monad
│   ├── url_encoder_service.rb  # Encode logic (counter + cache)
│   └── url_decoder_service.rb  # Decode logic (read-through cache)
├── validators/
│   └── url_validator.rb        # SSRF protection + scheme validation
lib/
└── base62_encoder.rb           # Pure encoding module (no side effects)
config/initializers/
├── rack_attack.rb              # Rate limiting + UA blocklist
└── redis.rb                    # Connection pool
db/migrate/
└── 20260317000001_create_short_urls.rb  # PostgreSQL SEQUENCE + indexes
```

---

## License

MIT
