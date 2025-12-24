Architecture overview — CloudxAi
=================================

This document summarizes the main components, how they interact, and where to find critical modules in the repository.

Core components

- API & FastAPI controller: `ai/controller/fastapi_app.py` and `src/app` contain HTTP endpoints and API wiring.
- Worker and background job system: `worker/` contains job runner logic (`worker/runner.py`, `worker/worker.py`) and DB adapters (`worker/db_postgres.py`).
- Agents and orchestration: `ai-agent/` and `ai_agent/` contain agent orchestration, registry and worker glue code.
- StepRunner scaffold: `step_runner/` contains a deterministic runner used to run phased tasks in a reproducible manner.

Data stores and migrations

- Migrations are in `migrations/` (e.g., `0001_create_jobs.sql`). Integration tests that use Postgres are guarded by environment variables and manual workflows.

CI & test locations

- Unit and integration tests live in `tests/` and `ai-agent/tests/` and `step_runner/tests/`.
- CI workflows are in `.github/workflows/` (conservative CI and manual Postgres integration workflows exist).

Where to change behavior

- Business logic and API surface: `src/app/` and `ai/controller/`
- Background job orchestration: `worker/` and `ai-agent/worker/`
- Deployment and infra: `docker/`, `devops/`, and `compose.*.yml` files
