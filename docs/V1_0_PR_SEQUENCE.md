# v1.0 PR Sequence (Draft Only)

This document lists a recommended, ordered set of PRs to prepare CloudxAi for v1.0. These are draft-only planning artifacts—do not create branches or PRs during beta without explicit human authorization.

Principles
----------
- No renames of existing metrics (add new metrics where needed)
- Small, test-covered PRs with clear owners
- CI must validate observability signals for each PR

Proposed PR sequence (each item should be a single PR with tests and docs):

1) PR: observability/nightly-scrape-ci
   - Purpose: add a nightly CI job (draft-only until GA) that scrapes staging Prometheus and verifies presence of core metrics.
   - Tests: PromQL assertions for `tenant_readiness_state`, `tenant_cost_estimate`, `tenant_label_rejections_total`.
   - Owner: SRE

2) PR: cost/aggregation-metrics
   - Purpose: add dual metrics for v1.0 (e.g., `tenant_cost_estimate_rolling`, `tenant_cost_billing_window`) as new metrics while preserving `tenant_cost_estimate`.
   - Tests: unit tests for new metrics module and acceptance tests validating export format.
   - Owner: Platform

3) PR: storage/remote-write-compat
   - Purpose: add remote-write compatibility and retention guidance (docs + optional config). No runtime changes to default behavior.
   - Owner: Platform

4) PR: ci/observability-regression-tests
   - Purpose: add regression tests in CI to ensure alert rules don't regress (linting + sample Prometheus data validation).
   - Owner: SRE

5) PR: scalability/synthetic-tenant-harness
   - Purpose: synthetic tenant generator and load harness for PoC scalability testing (tests & docs only).
   - Owner: Performance

6) PR: docs/migration-guides
   - Purpose: migration notes and compatibility guidance (beta→GA), including deprecation timeline for any future metric renames.
   - Owner: Tech Writing

7) PR: rollout/gradual-enablement-and-telemetry
   - Purpose: rollout playbook for enabling new billing windows or aggregation semantics with canaries and rollbacks (docs only).
   - Owner: Product + SRE

Notes
-----
- Each PR must include clear test plans and PromQL examples. No instrumenting changes to `tenant_readiness_state` semantics are allowed.
- This sequence is a planning artifact. Do not open PRs without human approval.
