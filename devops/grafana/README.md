Tenant Readiness Grafana Dashboard
=================================

This folder contains the Beta Grafana dashboard JSON for tenant-level readiness and cost observability.

Import instructions (Grafana UI):

1. In Grafana, go to Dashboards → Manage → Import.
2. Upload `devops/grafana/dashboards/tenant_readiness_dashboard.json`.
3. Set the data source to your Prometheus instance.
4. Use the `$tenant` dropdown to select a tenant (populated via `label_values(tenant_readiness_state, tenant)`).

PromQL examples used in the dashboard:

- Tenant readiness: `tenant_readiness_state{tenant="$tenant"}`
- Tenant cost estimate: `tenant_cost_estimate{tenant="$tenant"}`
- Cost trend (1h): `increase(tenant_cost_estimate{tenant="$tenant"}[1h])`
- Cardinality rejections (5m): `increase(tenant_label_rejections_total[5m])`
- Global readiness: `readiness_state`

Notes:
- This dashboard is read-only and observational. Do NOT use the dashboard to perform any write operations or change readiness state.
- If cardinality rejections are observed frequently, investigate tenant onboarding patterns and consider increasing `MAX_TENANT_LABELS` only after review.
