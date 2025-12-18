# Design Spike: Queue choice for PHASE-6.1

This artifact records the initial spike comparing three queue options for the Task Execution Engine: Redis Streams, Postgres job table (advisory locks), and Celery/RQ.

## Evaluation criteria

- Durability & resume semantics
- Operational simplicity (ops burden)
- Testability in CI
- Support for deduplication and at-least-once vs exactly-once
- Ecosystem maturity and Python support

## Options considered

### Redis Streams

Pros:
- Durable (if Redis AOF/RDB configured) and supports consumer groups for parallel processing
- Good resume semantics via consumer groups and pending entries list (PEL)
- High throughput and low latency
- Many client libraries in Python (aioredis, redis-py)

Cons:
- Requires running Redis (operational dependency)
- Exactly-once semantics require careful idempotency handling

### Postgres job table (advisory locks)

Pros:
- Uses existing relational DB (familiar ops)
- Durability and ACID guarantees
- Easier to inspect and debug (SQL)
- Can implement checkpointing and idempotency with row-based state

Cons:
- Potential contention at scale; requires careful indexing
- Throughput lower than Redis Streams

### Celery / RQ

Pros:
- Mature ecosystem, built-in worker primitives
- RQ is simple and Redis-backed; Celery powerful

Cons:
- Celery adds complexity and heavy dependency; historically operationally heavy
- RQ is simpler but limited features (no streams consumer group semantics)

## Recommendation

For PHASE-6 initial spike (proof-of-concept) we recommend **Postgres job table** for the following reasons:

- PHASE-6 priorities: durability, testability, and operational simplicity. Postgres provides ACID guarantees and is easy to test in CI (using a local Postgres instance or sqlite fallback for unit tests).
- Using Postgres avoids adding a new operational dependency during initial development. Many deployments will already have Postgres available.
- It simplifies pause/resume semantics and makes it easier to build idempotency and deduplication at the SQL layer.

Notes:
- If later throughput requirements demand it, we can migrate to Redis Streams for higher performance while retaining the same task schema and idempotency semantics.

## Non-goals for this spike

- Implementing production-grade HA for the chosen store
- Implementing full worker autoscaling

