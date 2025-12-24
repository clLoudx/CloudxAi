Readiness is a contract.
Metrics are evidence.
Chaos proves truth.
I will not change locked semantics.

Title: Beta: Tenant-Aware Observability & Cost Attribution (feature/tenant-observability-costs)

This PR implements Tenant-Aware Observability & Cost Attribution in an additive, read-only manner.

Scope summary:

- Add `ai_agent/observability/cost_metrics.py` (tenant cost metrics with cardinality guard and Prometheus fallback)
- Add `/tenant/<tenant>/cost` read-only endpoint to `ai-agent/dashboard/app.py` (enforces cardinality guard, does not mutate readiness)
- Add unit tests and direct-run fallbacks: `tests/test_observability_cost_metrics.py`, `tests/test_tenant_cost_endpoint.py`
- Add Grafana dashboard JSON: `devops/grafana/dashboards/tenant_readiness_dashboard.json`
- Add Alertmanager routing example: `devops/alerts/alertmanager-routing.yaml`
- Add CI workflow for observability tests: `.github/workflows/observability.yml`
- Add BETA readiness checklist: `BETA_READY.md`
- Update canonical closure artifact to record coding-phase progress: `PHASE_MULTI_TENANT_READINESS_CLOSED.md`

Merge requirements (MANDATORY):

- CI must be green for all observability tests and sanity checks
- Do NOT merge unless CI is green
- No changes to readiness semantics or metric names introduced by the closed phase

Reviewer guidance:

- Confirm that `/readyz` behavior is unchanged
- Confirm that `/tenant/<tenant>/cost` is read-only and does not affect readiness
- Confirm cardinality guard is enforced (env: MAX_TENANT_LABELS) and that `tenant_label_rejections_total` exists

Labels to apply: `beta-candidate`, `observability`, `tenant-safe`, `ci-required`

Automated checks:

- Observability CI workflow will run tests and report status. Chaos tests are opt-in and not run by default.

This PR was prepared by the local GitHub agent. Please open the PR at the URL below and paste this body (or attach it via the web UI):

https://github.com/clLoudx/CloudxAi/pull/new/feature/tenant-observability-costs

Do not merge without CI green.
