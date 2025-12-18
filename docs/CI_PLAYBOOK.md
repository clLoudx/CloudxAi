# CI Playbook — Safe Postgres-backed Integration Tests

Purpose: provide a safe, reviewed, and manual path to run Postgres-backed integration tests in CI or locally. This playbook is intentionally conservative: integration runs are manual, require secrets, and are gated behind the hygiene PR.

Guiding principles

- Tests-first: add unit tests and minimal integration tests that can run in an ephemeral DB.
- Manual gate: Postgres integration runs must be triggered explicitly (workflow_dispatch) or run locally by developers.
- Secrets: use repository secrets (DATABASE_DSN) or the built-in GitHub Actions Postgres service.
- Cleanup: integration runs must not touch production DBs. Always use ephemeral databases.

Quick run (locally, Docker)

1. Start an ephemeral Postgres container:

```bash
docker run --name ci-postgres -e POSTGRES_PASSWORD=pass -e POSTGRES_DB=testdb -p 5432:5432 -d postgres:15
export DATABASE_DSN=postgresql://postgres:pass@127.0.0.1:5432/testdb
pytest tests/test_postgres_integration.py
docker stop ci-postgres && docker rm ci-postgres
```

2. CI best-practices

- Use `workflow_dispatch` to run integration tests on-demand.
- Require the `DATABASE_DSN` secret or use the GitHub Actions Postgres service and a migration step to create a unique schema per run.
- Always run migrations against ephemeral DBs only.
- Ensure rollback scripts exist and are tested.

GitHub Actions (recommended manual workflow)

- The repository includes `.github/workflows/postgres-integration.yml`. This workflow is manual and will only run when triggered.
- It accepts an optional `use_service` boolean. If `use_service=true`, a Postgres service is attached; otherwise the workflow expects `DATABASE_DSN` secret to be set.

Security & safety

- Never store production credentials in CI secrets.
- Review the PR contents before enabling the workflow for full test runs.
- Keep accept/reject human gates when rolling out new migrations.
