# PR: PHASE-6 — Harden Postgres job table & DSN-aware worker

Summary
-------
This PR adds a Postgres DB adapter for the durable job table, a DSN-aware
adapter that lazily loads Postgres to avoid introducing new dev-time
dependencies, a migration helper, and CI workflow to run optional Postgres
integration tests when a DATABASE_DSN secret is provided.

Files of interest
- `worker/db_postgres.py` - psycopg2-based Postgres adapter (enqueue/claim/complete/fail/get)
- `worker/db_adapter.py` - DSN-based adapter that selects sqlite or Postgres lazily
- `tools/apply_migrations.py` - minimal migration runner for dev
- `migrations/0001_create_jobs.sql` - initial jobs table schema
- `tests/test_postgres_integration.py` - opt-in integration test (skipped unless DATABASE_DSN & psycopg2)
- `.github/workflows/postgres-integration.yml` - workflow to run migrations + integration tests when secret is set

Checklist
---------
- [x] Unit tests for sqlite POC remain passing (`tests/test_worker_resume.py`) 
- [x] Postgres integration tests added but gated by `DATABASE_DSN` and `psycopg2`
- [x] Lazy-import pattern used to avoid failing local dev without psycopg2
- [x] Migration helper script included and CI workflow added

Review guidance
---------------
- To run Postgres integration tests locally (dev):

```bash
export DATABASE_DSN="postgres://user:pass@host/db"
pip install psycopg2-binary
python tools/apply_migrations.py
pytest -q tests/test_postgres_integration.py
```

- If you prefer to run integration tests in CI, set `DATABASE_DSN` as a repository
  secret and the workflow will apply migrations and run the integration test on
  branch `phase-6/harden-postgres`.

Next steps (suggested)
----------------------
1. Add advisory-lock based claim variant for very high contention workloads.
2. Add exponential backoff retries and jitter for failed claims.
3. Add a configurable lease margin and diagnostics for long-running jobs.
4. Implement PHASE-6.2 step runner (isolated workspaces, resource limits, artifact capture).
