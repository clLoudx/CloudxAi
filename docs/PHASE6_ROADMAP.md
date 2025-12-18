# PHASE 6 — AI Execution & Autonomy Layer (Roadmap)

This document captures the PHASE-6 roadmap, goals, sub-phases, and initial sprint backlog for introducing a production-capable execution layer to the AI Controller and Agent system.

See also: `design/queue-choice.md` (spike artifact) which recommends a queue technology for 6.1.

## Goal

Turn the orchestration-only controller into a production-capable execution platform that supports long-lived tasks, auto-build workflows, deterministic replay, and robust observability. PHASE-6 focuses on engineering controls and auditability rather than model retraining or secrets management.

## Sub-phases

1. 6.1 — Task Execution Engine
2. 6.2 — Auto-Build Mode (non-interactive)
3. 6.3 — Learning & Feedback Loop (non-training)
4. 6.4 — Admin Control Plane
5. 6.5 — Cost & Performance Governance

## Entry checklist

- PHASE-5 merged
- Metrics available and `/metrics` endpoint exposed
- Health handshake stable and tested

## Artifacts produced in this spike

- `docs/PHASE6_ROADMAP.md` (this file)
- `design/queue-choice.md` (queue technology spike and recommendation)
- Draft OpenAPI for task submission + status (artifact to follow)

## Sprint backlog (first 2 sprints)

See the detailed sprint backlog in the central roadmap stored in project management. The first sprints focus on a small spike to choose queue technology, a minimal persistent queue POC, and tests for resume and cancellation.

## Next steps (immediate)

1. Produce `design/queue-choice.md` with spike results (Redis Streams vs Postgres job table vs Celery/RQ)
2. Create an OpenAPI draft for task submission and status
3. Implement minimal POC: submit → run → resume after worker restart

## Governance

All PRs for PHASE‑6 MUST include unit/integration tests, Prometheus metrics, and a runbook describing failure modes and recovery steps.

---
