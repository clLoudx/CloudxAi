# LIVING CHECKLIST — Phase-by-Phase (Canonical)

This living checklist is authoritative. Every phase must be completed (all boxes checked and evidence attached) before moving to the next.

## Phase 0 — Governance
- [ ] Execution contract approved (docs/ENTERPRISE_ROADMAP.md)
- [ ] Safety rules documented (docs/)
- [ ] Secrets policy defined (.github/, docs/)
- [ ] Decision log enabled (docs/decisions.md)

## Phase 1 — Foundation Acceleration
- [ ] Repo inventory complete (reports/phase1_hygiene_and_map.md)
- [ ] No secrets found (scan evidence attached)
- [ ] No binaries committed (evidence + git status)
- [ ] Architecture understood (docs/architecture_diagram.mmd)

## Phase 2 — System Modeling
- [ ] System diagram exists (docs/architecture_diagram.mmd)
- [ ] Data flows documented (design/system-overview.md)
- [ ] Failure modes listed (design/failure-modes.md)
- [ ] Trust boundaries explicit (design/security-boundaries.md)

## Phase 3 — Core Infrastructure
- [ ] Health endpoints implemented and tested
- [ ] Metrics exposed (/metrics)
- [ ] Structured logs (JSON) enabled
- [ ] Baseline dashboards created

## Phase 4 — Control Plane
- [ ] Signal schema defined
- [ ] Agent lifecycle documented
- [ ] State machine explicit and tested

## Phase 5 — Agent Safety
- [ ] Health handshake implemented
- [ ] Failure recovery tested (chaos tests)
- [ ] Metrics verified
- [ ] Unit + integration tests green

## Phase 6 — Execution Engine
### 6.1 Task Engine
- [ ] Durable queue in Postgres
- [ ] Lease-based claiming + recovery
- [ ] Advisory locks (optional)
- [ ] Backoff & jitter implemented
- [ ] Idempotent migrations
- [ ] Ops runbooks written (runbooks/)

### 6.2 StepRunner
- [ ] Workspace isolation
- [ ] Step API defined
- [ ] Artifact capture & retention policy
- [ ] Deterministic logs

### 6.3 Learning & Feedback (non-autonomous)
- [ ] Metrics-driven analytics
- [ ] No autonomous policy change

### 6.4 Admin Control Plane
- [ ] Kill switch
- [ ] Audit logs
- [ ] Auth + RBAC enforced

### 6.5 Cost & Governance
- [ ] Budgets enforced
- [ ] Rate limiting implemented
- [ ] Alerts configured

## Phase 7 — Hardening
- [ ] Load tests
- [ ] Chaos tests
- [ ] Rollback tested
- [ ] Oncall runbooks approved

## Phase 8 — Operations
- [ ] Incident response process
- [ ] Postmortems
- [ ] Continuous metrics review

---

Instructions for agents and contributors:
- Attach evidence (links to artifacts, test runs, metrics dashboards) whenever you check a box.
- For automated checks, include logs and correlation IDs.
- For manual approvals, include the approver's identity and timestamp.
- No box is considered checked without evidence.
