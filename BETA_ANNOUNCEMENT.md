# Beta Announcement — v0.9.0-beta

Audience: Internal SRE/Platform, Early Customer Beta

Subject: Beta release — Tenant Observability & Cost Attribution (v0.9.0-beta)

Body:

Hello team,

We have released v0.9.0-beta which provides tenant-level readiness visibility and cost estimation metrics. This release is observational and does not change global readiness semantics.

What’s included:
- Tenant readiness endpoint: `/tenant/<tenant>/readyz` (read-only)
- Tenant cost endpoint: `/tenant/<tenant>/cost` (read-only)
- Grafana dashboard: `devops/grafana/dashboards/tenant_readiness_dashboard.json`
- Prometheus metrics and alert routing examples

Key constraints:
- Readiness semantics are frozen: do not change `/readyz` behavior.
- This beta is informational; no write operations or tenant-level overrides are allowed.

How to validate:
- Import the Grafana dashboard and pick a tenant to view readiness and cost panels.
- Check alert routing in staging using `promtool`.

How to report issues:
- Open GitHub issues with the `beta` label and tag SRE.

Regards,
Platform Team
