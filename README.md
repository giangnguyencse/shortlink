## 1. Setup & Installation

### Prerequisites
- Docker & Docker Compose

### Getting Started

1. Clone the repository & start the containers
```bash
git clone <repo-url> && cd shortlink
cp .env.example .env
docker-compose up -build -d
```

2. Prepare the database
```bash
docker-compose exec web bin/rails db:prepare
```

```bash
bundle exec rails db:drop db:create db:migrate
```

3. Run the test suite (RSpec)
```bash
docker-compose exec web bundle exec rails db:test:prepare
```

```bash
docker-compose exec web bundle exec rspec
```

```bash
docker-compose exec web bundle exec rspec spec/services/url_decoder_service_spec.rb
```

4. Some command to use
```bash
docker-compose logs -f web

docker-compose exec web bundle exec rails c
```

## 2. Live Demo
The application is fully deployed and available for testing!

**Base URL:** `https://shortlink-kp07.onrender.com`

- This demo is hosted on Render's Free tier and uses an Upstash Serverless Redis. The free instance will spin down with inactivity. If the service hasn't been accessed recently, **the very first request may be delayed by 50 seconds or more** while the container wakes up. Subsequent requests will be lightning-fast.

You can test the Encode endpoint directly from your terminal

2.1 Encode a URL
```bash
curl -X POST https://shortlink-kp07.onrender.com/api/v1/encode \
  -H "Content-Type: application/json" \
  -d '{"url": "https://github.com/resources/articles?topic=software-development"}'
```

2.1 Decode a short URL
```bash
curl -X POST https://shortlink-kp07.onrender.com/api/v1/decode \
  -H "Content-Type: application/json" \
  -d '{"short_url": "https://shortlink-giangnguyen.onrender.com/Kmmm8g8"}'
```

### Successful Response Example
**Encode API:**
![Encode API Success](./images/demo_encode.png)

**Decode API:**
![Decode API Success](./images/demo_decode.png)


## 3. API Documentation

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

### `POST /api/v1/decode` — Decode a short URL

**Request** (accepts full URL **or** just the code):
```bash
curl -X POST http://localhost:3000/api/v1/decode \
  -H "Content-Type: application/json" \
  -d '{"short_url": "http://localhost:3000/Kmmm1ZE"}'
```

```bash
curl -X POST http://localhost:3000/api/v1/decode \
  -H "Content-Type: application/json" \
  -d '{"short_url": "Kmmm1ZE"}'
```

**Response `200 OK`:**
```json
{
  "data": {
    "original_url": "https://github.com/resources/articles?topic=software-development",
    "short_code": "Kmmm1ZE"
  },
  "meta": { "request_id": "62f3a771-739f-4b26-8886-d4684cc7cfb1" }
}
```


## 4. Architectural Approach & The Collision Problem

The Collision Problem

A naive approach to URL shortening involves generating a random string and checking the database for its existence. Under high concurrency, this leads to Race Conditions, the Birthday Paradox (increased collision probability), and heavy database read/write locks.

The Solution: Standalone Key Generation Service (KGS)

To guarantee 0% collision and O(1) encode speed, this application implements a pre-allocation strategy:

4.1. PostgreSQL Sequence + Base62: A database sequence guarantees atomic, monotonically increasing integers. Base62 ($62^7 \approx 3.5 \text{ Trillion}$ combinations) ensures short, URL-friendly strings.

4.2. In-Memory Key Pool (Redis): The KeyGenerationService fetches ID batches (e.g., 20,000 at a time) using Postgres generate_series, encodes them to Base62, shuffles them (for unpredictability), and stores them in a Redis List (RPUSH).

4.3. O(1) Retrieval: When an /encode request arrives, the service simply pops a key from Redis (LPOP). No database sequences are queried during the hot path.

4.4. Asynchronous Replenishment: When the Redis pool drops below a threshold (e.g., 5,000 keys), an async thread (guarded by a Redis SET NX Distributed Lock) silently fetches the next batch from the DB.

Pros: Zero DB write-locks during key generation, zero collisions, extremely low latency.Cons: If Redis crashes completely, the unassigned keys in the pool are lost (which is acceptable, as sequence gaps do not affect functionality).

IdempotencyIf a user submits the same long URL multiple times, they should receive the same short code. To achieve this without slow full-text B-Tree index scans on VARCHAR(2048), the app computes a SHA256 hash of the URL (url_digest - 64 chars) and places a UNIQUE INDEX on it.

## 5. Security & Attack Vectors mitigated

5.1. SSRF (Server-Side Request Forgery): Malicious users might submit internal IPs (e.g., http://169.254.169.254 or http://10.0.0.1) to probe AWS metadata or internal networks. UrlValidator uses Ruby's Resolv to check DNS and blocks any request targeting private/reserved IP ranges.

5.2. DDoS & Brute Force: Rack::Attack middleware limits API requests per IP (e.g., 10 req/min for encode, 30 req/min for decode) to prevent spamming the database.

5.3. Database Injection: Strong parameters and strict Base62 Regex (/\A[0-9a-zA-Z]+\z/) at the routing/service level prevent SQL injection attempts.

5.4. Hot-Path Row Locking (Click Tracking): Updating click_count in the DB on every decode request causes a Thundering Herd problem via row-level locks. This is mitigated by using Redis INCR (non-blocking) for click tracking.


## 6. Scalability Limitations & Future Evolution

While the current architecture handles moderate to high loads (~10,000 RPS) effectively via L1 Caching and KGS, scaling to 1,000,000+ RPS (Hyper-scale) requires transitioning from a monolithic data layer to a distributed ecosystem.

Here is the step-by-step roadmap to scale the system:

6.1. API & Compute Layer
- Limitation: Ruby/Puma processes consume significant memory per thread.

- Evolution: Containerize the API and deploy via AWS EKS (Kubernetes) or ECS with Horizontal Pod Autoscaling (HPA).

- Edge Offloading: Move Rate Limiting (Rack::Attack) to an API Gateway (Kong) or AWS WAF / Cloudflare. Ruby should not waste CPU cycles rejecting malicious IPs.

6.2. Database Layer (The Write Bottleneck)
- Limitation: A single PostgreSQL instance cannot handle millions of INSERT statements per second, even with KGS mitigating the sequence bottleneck.

- Evolution - Database Sharding: Partition the database based on a Hash of the short_code. Since KeyGenerationService manages ID creation independently, we don't rely on auto-incrementing primary keys across shards, making horizontal DB scaling trivial.

- Evolution - Asynchronous Writes: Introduce Apache Kafka or AWS SQS. The /encode endpoint grabs a key from Redis, validates it, drops the payload into Kafka, and returns 201 Created immediately. Background workers (Consumers) batch-insert the records into PostgreSQL (e.g., 10,000 records per transaction).

6.3. Caching & Read Layer (The Read Bottleneck)
- Limitation: A single Redis instance will hit CPU limits at ~100k OPS. Requests from global users to a central server introduce network latency.

- Evolution - Redis Cluster: Migrate to a Redis Cluster to shard the decode caches and KGS pools across multiple master nodes.

- Evolution - Edge Caching (CDN): For decodes/redirects, integrate AWS CloudFront or Cloudflare Workers. Sync the short_code -> original_url map to the CDN's Edge KV store. Redirects (302) will happen at the edge nearest to the user in < 5ms, without ever hitting the Ruby backend.

6.4. Analytics & Click Tracking
- Limitation: Storing click counts in PostgreSQL (even via batched updates) pollutes the transactional database with heavy write-heavy analytical data.

- Evolution: Use a dedicated OLAP database. Stream click events from Redis/Web nodes to Kafka/Kinesis, and ingest them into ClickHouse or Apache Druid. This decouples the transactional workflow (URL resolution) from the analytical workflow (dashboards).
