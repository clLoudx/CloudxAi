# PHASE‑6.1 — Production release checklist & runbook

This document captures the release checklist, operational runbooks, observability, rollback procedures, and Go/No‑Go criteria for PHASE‑6.1 (Durable Task Engine using Postgres).

Purpose
-------
PHASE‑6.1 hardens the durable task execution substrate: a Postgres-backed job table, lease-based claiming, optional advisory-lock claim path, and a worker loop with crash/restart recovery. This doc is the gate to merging `phase-6/harden-postgres` into mainline.

1) Release checklist (gate to merge)
-----------------------------------
- Tests
  - [x] Unit tests for sqlite POC (`tests/test_worker_resume.py`) passing locally and in CI.
  - [x] Postgres integration tests added and gated (`tests/test_postgres_integration.py`) — run only when `DATABASE_DSN` secret is present and `psycopg2` is available.
  - [x] New advisory-lock and backoff unit tests (if added) gated by same CI flag.

- CI
  - [x] CI job present to apply migrations and run Postgres integration tests when `DATABASE_DSN` secret is set (`.github/workflows/postgres-integration.yml`).
  - [x] Linting and unit test job green on branch.

- Migrations
  - [x] Migrations live under `migrations/` and are human-reviewed.
  - [ ] (Follow-up) Migration runner made idempotent and records applied migrations (`schema_migrations` table). This must land before applying to production DBs.

- Observability & Metrics
  - [x] Required metrics implemented in code (see Observability section).
  - [x] `/metrics` endpoint is exposed by FastAPI (PHASE‑5) and scraped by Prometheus in staging.

- Runbooks & Documentation
  - [x] This release checklist & runbook merged alongside code changes.
  - [x] README or dev docs explain how to run local Postgres integration tests.

2) Architecture snapshot (PHASE‑6.1 only)
-------------------------------------
- Job lifecycle states: `queued -> running -> completed | failed`.
- Claim semantics:
  - Default: `UPDATE ... RETURNING` pattern that atomically marks a job as `running` and sets `locked_at`/`locked_by`.
  - Optional: `pg_try_advisory_lock(job_id)` variant (enabled via env `USE_ADVISORY_LOCKS=1`) to avoid UPDATE hot spots under extreme contention.
- Lease semantics:
  - Claim sets `locked_at = now()` and worker must complete/fail within `lease_seconds` (configurable per worker).
  - Expired leases (locked_at < now() - lease_seconds) are eligible to be reclaimed.
- Persistence:
  - Production: Postgres job table (durable, transactional). Local tests use file-backed SQLite for determinism.

3) Operational runbooks
----------------------

Worker crash / restart
- Symptoms: worker process dies or container restarts; jobs previously `running` are left in `running` with `locked_at` in the past.
- Recovery steps:
  1. Confirm worker processes have restarted and are healthy (`systemd`, k8s pods, or supervisor logs).
 2. Verify `locked_at` values: expired locks will be reclaimed by new workers automatically.
 3. If jobs remain stuck (locked_at not expired), inspect `locked_by` and worker health. You can force-release a lock by moving the job back to `queued`:

   ```sql
   UPDATE jobs SET status='queued', locked_at = NULL, locked_by = NULL WHERE id = <job_id>;
   ```

4. If multiple jobs stuck, consider temporarily scaling worker pool down to zero, fix underlying issue, then scale back up (drain+resume pattern).

Stuck job / expired lease
- Symptoms: job status remains `running` beyond expected execution time; `locked_at` very old.
- Steps:
  1. Check worker logs for `worker-id` recorded in `locked_by`.
 2. If worker crashed/terminated, wait for lease expiry then new worker will reclaim. To expedite, adjust `locked_at` to a past time or manually requeue the job (see SQL above).
 3. For aborting a long-running job: set `status='failed'` with a failure note (and increase attempts accordingly) or requeue with reduced max_attempts.

Postgres unavailable (DB outage)
- Symptoms: workers raise DB connection errors or retries.
- Steps:
  1. Pause worker fleet (scale down) to avoid retry storms.
 2. Fix DB connectivity (failover, restore, networking).
 3. Once DB is healthy, run a health-check script and then scale workers back up.

High contention / advisory-lock failure
- Symptoms: claim latencies increase; many claim attempts return no rows.
- Steps:
  1. Inspect Postgres locks and active queries (pg_stat_activity, pg_locks).
 2. If advisory-lock path is enabled and contention is high, switch to UPDATE variant or tune worker backoffs. You can toggle `USE_ADVISORY_LOCKS` env var and restart worker pool.
 3. Tune worker backoff parameters (`backoff_base`, `max_backoff`) to reduce hot loops.

How to safely cancel a job
- Safe cancel (preferred): set job status to `failed` with explanatory payload, preserving audit trail.

```sql
UPDATE jobs SET status='failed', updated_at = now() WHERE id = <job_id>;
```

For immediate removal (not recommended): delete the job row, but this loses audit data.

4) Observability & metrics (required)
-----------------------------------
Required metrics (exposed via Prometheus):
- `phase6_task_submitted_total` (Counter) — tasks enqueued
- `phase6_task_running` (Gauge) — number of tasks running
- `phase6_task_completed_total` (Counter) — completed tasks
- `phase6_task_failed_total` (Counter) — failed tasks
- `phase6_task_recovered_total` (Counter) — tasks reclaimed after lease expiry

Recommended additional metrics:
- Claim latency histogram (time to successfully claim a job)
- Job run duration histogram
- DB errors counter for claim/enqueue/complete

Alerting suggestions (example thresholds)
- High failure rate: if `increase(phase6_task_failed_total[5m]) / increase(phase6_task_submitted_total[5m]) > 0.1` → P1 alert
- Many stuck jobs: if count of `jobs` with `status='running'` and `now() - locked_at > 5 * expected_run_time` > N → P1
- DB connectivity errors > 5/min → P1

Logging requirements
- Worker logs must include: worker_id, claimed job id, job type, timestamps for claim/start/complete/fail, exception trace if failed.

5) Rollback plan (critical)
---------------------------
Goal: revert to previous behavior without data loss.

Safe rollback steps (no schema change required)
1. Disable worker fleet (scale to 0) to stop new claims.
2. Revert application code to the previous commit and deploy (this will prevent new claim patterns from running).
3. Start a controlled worker in read-only or debug mode to inspect jobs and replay if needed.

If schema changes were applied and are destructive, rollback requires DB restore from backup. Therefore:
- Do NOT apply non-backwards-compatible migrations without explicit DB backup & a tested restore procedure.
- Always run migrations in staging and verify the migration runner is idempotent before production run.

6) Go / No‑Go criteria (must be true to ship)
-------------------------------------------
Go if all of the following are true:
- Unit tests & CI green on branch.
- Postgres integration tests run in CI (or pass locally when `DATABASE_DSN` is set).
- Migrations present and human-reviewed; migration runner idempotency scheduled as follow-up (required before prod DB apply).
- `/metrics` endpoint scrapes in staging and the required metrics are present.
- Runbooks present and reviewed by at least one ops/engineer reviewer.

No‑Go blocks (examples):
- Missing critical metrics (e.g., no `phase6_task_failed_total`).
- Migration files are destructive or not reversible AND no backup/restore plan exists.
- No tested migration runner for staging/production.

7) How to run Postgres integration tests locally (dev)
-----------------------------------------------------
1. Start a Postgres instance (Docker recommended):

```bash
docker run --rm -e POSTGRES_PASSWORD=pass -e POSTGRES_USER=pguser -e POSTGRES_DB=pgdb -p 5432:5432 -d postgres:15
export DATABASE_DSN="postgres://pguser:pass@localhost:5432/pgdb"
pip install psycopg2-binary
python tools/apply_migrations.py
pytest -q tests/test_postgres_integration.py
```

2. Clean up: tear down the container or drop the `jobs` table if the test script didn't already.

8) Post-release follow-ups
---------------------------
- Make `tools/apply_migrations.py` idempotent and record applied migrations (high priority before applying to production DBs).
- Add advisory-lock integration tests to CI matrix (gated).
- Add step-runner scaffolding (PHASE‑6.2) and resource limiting integration tests.

9) Contact & owners
--------------------
- Code owner(s): backend/worker team (see `CODEOWNERS` if present)
- On‑call for DB: DBAs / platform team
- Release approver(s): one backend lead + one ops/oncall person

10) Commit plan and PR details
-----------------------------
- Branch: `phase-6/harden-postgres`
- Commit message for this doc: `docs: add PHASE-6.1 production release checklist & runbook`
- PR body file added: `PR_BODY_PHASE6_HARDEN.md`

If you approve this doc, I will commit it to the branch and push. After merge, we should immediately follow with the idempotent migration runner PR before applying migrations to any production DB.

----
Last updated: 2025-12-17
