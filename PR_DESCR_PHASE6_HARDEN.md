PR Title: docs(design): PHASE-6.1 hardening — Postgres adapter & worker DSN support

Summary

This PR hardens PHASE-6.1 by adding a Postgres adapter for the job table and making
the worker DSN-aware. The changes are backward-compatible: the default remains the
sqlite-based POC used for deterministic tests. No production Postgres changes are
applied automatically by this PR; migrations live under `migrations/` and an
optional helper `tools/apply_migrations.py` is provided to apply them when ready.

What’s included
- `worker/db_postgres.py`: minimal Postgres-backed job operations
- `worker/db_adapter.py`: DSN-based adapter selecting sqlite or Postgres
- `worker/worker.py`: updated to initialize sqlite schema by default and to use the adapter
- `tools/apply_migrations.py`: optional migration runner for Postgres

Why this matters

This change prepares the codebase for production-grade durability by enabling a
Postgres-backed job table while preserving the simple sqlite POC for tests and
local development. It keeps PHASE-5 untouched and preserves the same job lifecycle
semantics used in tests.

What is NOT included
- No automatic migration execution in CI
- No changes to FastAPI or Controller behavior
- No production Postgres connection is created by default

Testing

Run the existing tests (they use sqlite by default):

    .venv/bin/python -m pytest tests -q

To apply migrations locally against Postgres, set `DATABASE_DSN` and run:

    DATABASE_DSN=postgres://user:pass@host/db python tools/apply_migrations.py

Reviewer checklist
- [ ] Confirm no PHASE-5 files or behaviors were modified
- [ ] Confirm db adapter defers to sqlite for default tests
- [ ] Validate migration SQL in `migrations/0001_create_jobs.sql` is acceptable
- [ ] Approve to allow the team to proceed with Postgres integration
