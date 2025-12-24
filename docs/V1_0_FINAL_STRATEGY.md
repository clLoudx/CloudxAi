# v1.0 Finalization Strategy — CloudxAi (v0.9.0-beta → v1.0)

This document is the authoritative, additive strategy to finalize CloudxAi from beta to v1.0. It follows the MAX-LOGIC charter: read-only observation during beta, CI as merge authority, and no semantic changes to locked readiness metrics prior to v1.0 GA.

Goals
-----
- Stabilize beta (14–30 days of telemetry) and accumulate high-quality signals
- Validate cardinality and cost metric usefulness at scale
- Harden observability CI and operational playbooks
- Produce a small, test-covered PR sequence that leads to v1.0 without semantic drift

Principles & Invariants
-----------------------
- Readiness is a contract; DO NOT change readiness semantics during beta
- All beta actions must be additive, observational, and reversible
- CI is the only authority for merges; do not bypass
- Chaos testing is opt-in and must be isolated in staging

Phased Timeline (Suggested)
---------------------------
Phase 0 — Beta Stabilization (Days 0–14)
- Run daily passive monitoring (scripts/beta_monitor.py) and append observations
- Generate weekly reports and decide on any immediate operational changes (non-code)
- Collect 14 days of baseline telemetry

Phase 1 — Confidence Accumulation & Hardening (Days 14–30)
- Implement nightlies in staging (draft-only PR to test harness) to scrape metrics and run PromQL assertions (owner: SRE)
- Run synthetic tenant harness at scale to validate MAX_TENANT_LABELS guard behavior (owner: Performance)
- Validate alert routing and reduce false positives

Phase 2 — v1.0 PR Execution (Week 4–8, human approval required)
- Execute PRs per `docs/V1_0_PR_SEQUENCE.md` (owners and estimates below). Each PR must be small, test-covered, and include observability assertions.

Phase 3 — Pre-GA Validation & Signoff (Week 8–10)
- Ensure 14–30 days of telemetry, no major unresolved incidents, CI regression green for rolling window
- Ops dry-run: run incident drill tabletop with SRE/platform/product

Phase 4 — GA Release Mechanics (post-approval)
- Follow release tagging, changelog, and operator playbook per `docs/GA_READINESS_CHECKLIST.md`

v1.0 PR Breakdown, Owners & Estimates (Draft-only)
-----------------------------------------------
Each PR is small and focused. Estimates are high-level (person-days).

1) observability/nightly-scrape-ci (Owner: SRE) — 3d
- Add a staging-only nightly job (draft PR to be human-reviewed) that scrapes Prometheus and runs PromQL checks for core metrics. Tests: PromQL assertions, linting.

2) cost/aggregation-metrics (Owner: Platform) — 5d
- Add new metrics for aggregation (e.g., `tenant_cost_estimate_rolling`, `tenant_cost_billing_window`) while preserving `tenant_cost_estimate`. Include unit tests and docs.

3) storage/remote-write-compat (Owner: Platform) — 5d
- Enable remote-write compatibility and document retention/remote storage recommendations. Add config examples and integration tests using remote-write test harness.

4) ci/observability-regression-tests (Owner: SRE) — 4d
- Add regression tests that validate alert rules do not regress. Include promtool linting and sample data checks.

5) scalability/synthetic-tenant-harness (Owner: Performance) — 7d
- Build harness to simulate N tenants and generate cost & readiness metrics. Validate cardinality guard and scrape/ingestion performance.

6) docs/migration-guides (Owner: Tech Writing) — 3d
- Prepare migration docs, deprecation timelines and compatibility guides.

7) rollout/gradual-enablement (Owner: Product + SRE) — 3d
- Rollout playbook for enabling aggregation semantics, canary steps, and rollback processes.

Testing & CI Expansion Plan
--------------------------
- Unit tests: cover all new metric exporters and cost calculations.
- Integration tests: a staging job that spins up a minimal Prometheus, exports metrics, and runs PromQL assertions.
- Nightly scrape job: staging-only; validates presence/format of `tenant_readiness_state`, `tenant_label_rejections_total`, `tenant_cost_estimate`.
- Load tests: run synthetic harness to validate cardinality enforcement under load.
- Regression: add promtool rule linting and sample rule evaluations.

Observability & Ops Requirements
--------------------------------
- Ensure Grafana dashboard templates include tenant variable and safety backstop panels.
- Ensure alerts are routed by tenant where applicable and that Alertmanager routing is tested in staging.
- Keep the ops runbook (`docs/OPS_RUNBOOK_BETA.md`) updated with exact commands and PromQL samples.

Risk Matrix (Top Risks & Mitigations)
-----------------------------------
- Metric cardinality explosion
  - Impact: high; Mitigation: MAX_TENANT_LABELS guard, alerting, synthetic harness to detect growth
- Metric renames or semantic drift
  - Impact: high; Mitigation: preserve existing names; add new metrics instead of renaming
- CI regression or flaky tests
  - Impact: medium; Mitigation: isolate observability tests in dedicated workflow, add retries for ephemeral failures
- Cost metric misinterpretation
  - Impact: medium; Mitigation: document interpretation, include currency & window in endpoints and dashboards

Rollout & Canary Strategy (Draft)
---------------------------------
Goal: minimize blast radius and validate operational assumptions incrementally.

Stage 0 — Staging-only validation
- Nightly scrapes, synthetic harness runs, alert routing tests

Stage 1 — Canary tenants (opt-in)
- Select small group of tenants (internal or beta customers) to enable additional aggregation metrics; monitor for 7 days

Stage 2 — Gradual expansion (if safe)
- Expand canary cohort to X% of tenants, monitor cardinality/cost signals, and confirm no alert storm

Stage 3 — GA enablement
- Post signoff, perform final doc and changelog publish, tag `v1.0.0`, and follow release mechanics

Communication & Governance
--------------------------
- Draft announcement for internal and external stakeholders (use `BETA_ANNOUNCEMENT.md` as base).
- Weekly stability reports and incident logs are the single source of truth during beta.
- Any hotfix must follow `BETA_INCIDENT_POLICY.md` and be human-approved.

Deliverables (by Phase)
----------------------
- Phase 0: daily observations, weekly report
- Phase 1: nightly staging scrape PR (draft-only), synthetic harness initial runs
- Phase 2: execute v1.0 PRs (with human approval), integration & regression tests
- Phase 3: GA signoff, tag `v1.0.0`, release notes

Operational Checklist Before GA (Signoff criteria)
-------------------------------------------------
1. 14–30 days of telemetry with no unresolved cardinality incidents
2. Nightly staging scrapes green for 7 consecutive days
3. Alert reliability validated in staging; false-positive rate within acceptable bounds
4. Synthetic harness demonstrates cardinality guard under load
5. Migration docs & rollback plans ready
6. Owners and runbooks validated via tabletop drill

Appendix: Quick commands & references (ops)
-----------------------------------------
- Run monitor locally:
  - `python3 scripts/beta_monitor.py`
- Generate weekly report:
  - `python3 scripts/generate_weekly_report.py`
- Promtool lint:
  - `promtool check rules devops/alerts/tenant_alerts.yaml`

Notes on autonomy
-----------------
This strategy is intentionally draft-only and additive. No PRs, branches, or workflows will be created without explicit human authorization. All human approvals, signoffs, and merges are required by policy.
