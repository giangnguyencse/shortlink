# ShortLink — Local Development Setup Guide

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| Ruby | 3.3.0 | [rbenv](https://github.com/rbenv/rbenv) or [rvm](https://rvm.io/) |
| Rails | 7.1 | via Gemfile |
| PostgreSQL | 14+ | Homebrew or Docker |
| Redis | 7+ | Homebrew or Docker |
| Docker (optional) | 24+ | [docker.com](https://www.docker.com) |

---

## Option A: Docker (Recommended — Fastest)

### 1. Clone and configure

```bash
git clone <repo-url>
cd shortlink
cp .env.example .env
```

### 2. Start infrastructure

```bash
docker-compose up -d
```

This starts PostgreSQL (port 5432) and Redis (port 6379).

### 3. Install gems

```bash
bundle install
```

### 4. Setup database

```bash
bundle exec rails db:create db:migrate
```

### 5. Start the server

```bash
bundle exec rails server -p 3000
```

### 6. Verify it works

```bash
# Health check
curl http://localhost:3000/health
# → {"status":"ok","service":"shortlink"}

# Encode a URL
curl -X POST http://localhost:3000/api/v1/encode \
  -H "Content-Type: application/json" \
  -d '{"url": "https://codesubmit.io/library/react"}'

# Decode it (replace <short_code> with the code from above)
curl -X POST http://localhost:3000/api/v1/decode \
  -H "Content-Type: application/json" \
  -d '{"short_url": "http://localhost:3000/<short_code>"}'
```

---

## Option B: Manual Setup

### 1. Install Ruby 3.3.0

```bash
rbenv install 3.3.0
rbenv local 3.3.0
```

### 2. Install and start PostgreSQL

```bash
# macOS
brew install postgresql@14
brew services start postgresql@14

# Create user (if needed)
createuser -s postgres
```

### 3. Install and start Redis

```bash
brew install redis
brew services start redis
```

### 4. Configure environment

```bash
cp .env.example .env
# Edit .env: set DATABASE_URL, REDIS_URL, BASE_URL as needed
```

### 5. Install gems

```bash
bundle install
```

### 6. Setup database

```bash
bundle exec rails db:create
bundle exec rails db:migrate
```

### 7. Start server

```bash
bundle exec rails server -p 3000
```

---

## Running Tests

```bash
# Setup test DB
bundle exec rails db:create db:migrate RAILS_ENV=test

# Run all tests
bundle exec rspec

# With coverage report
COVERAGE=true bundle exec rspec

# Run by layer
bundle exec rspec spec/lib/                  # Base62Encoder
bundle exec rspec spec/validators/           # URL Validator + SSRF
bundle exec rspec spec/models/               # ShortUrl model
bundle exec rspec spec/services/             # Business logic
bundle exec rspec spec/requests/             # Integration (full stack)

# Human-readable output
bundle exec rspec --format documentation
```

---

## Environment Variables

| Variable | Default | Description |
|---|---|---|
| `RAILS_ENV` | `development` | Rails environment |
| `BASE_URL` | `http://localhost:3000` | Base URL for short links |
| `DATABASE_URL` | (see database.yml) | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379/0` | Redis connection string |
| `ENCODE_RATE_LIMIT` | `10` | Max encode requests per minute per IP |
| `DECODE_RATE_LIMIT` | `30` | Max decode requests per minute per IP |
| `THROTTLE_PERIOD` | `60` | Rate limit window in seconds |
| `RAILS_MAX_THREADS` | `5` | Puma thread count |
| `LOG_LEVEL` | `info` | Log level (debug/info/warn/error) |

---

## API Error Codes

| HTTP Status | Meaning |
|---|---|
| `201 Created` | URL encoded successfully |
| `200 OK` | URL decoded successfully |
| `400 Bad Request` | Invalid JSON or missing fields |
| `404 Not Found` | Short code not found |
| `422 Unprocessable Entity` | Validation failed (invalid URL format, etc.) |
| `429 Too Many Requests` | Rate limited — see `Retry-After` header |
| `500 Internal Server Error` | Unexpected server error |

---

## Testing Rate Limiting

```bash
# Run this in a loop to trigger rate limiting (encode limit is 10/min)
for i in {1..12}; do
  curl -s -o /dev/null -w "Request $i: %{http_code}\n" \
    -X POST http://localhost:3000/api/v1/encode \
    -H "Content-Type: application/json" \
    -d '{"url": "https://example.com"}'; \
done
# Requests 11+ will return 429
```
