# Beta Readiness Checklist

This checklist is the gate for the Tenant-Aware Observability & Cost Attribution beta.

Mandatory (CI green required):

- [ ] CI: `observability` workflow green
- [ ] pytest: `tests/test_observability_cost_metrics.py` and `tests/test_tenant_cost_endpoint.py` pass in CI
- [ ] Dashboards load in Grafana (import JSON verify)
- [ ] Alerting configs linted (promtool/alertmanager check)
- [ ] Read-only endpoints verified (no readiness mutation)

Optional (pre-launch):

- [ ] Add SLO-friendly panels
- [ ] Add cost attribution rollups
- [ ] Document chaos test runbook

Do not merge until all Mandatory items are checked and CI is green.
