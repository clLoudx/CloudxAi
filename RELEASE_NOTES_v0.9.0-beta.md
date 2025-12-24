# Release Notes — v0.9.0-beta

Release: v0.9.0-beta (Tenant Observability & Cost Attribution)
Date: 2025-12-24

Summary
-------

This beta release introduces tenant-scoped readiness visibility, tenant cost estimation metrics, and supporting dashboards and alerts. All changes are additive and observational; readiness semantics are unchanged and remain the canonical contract.

Key Features
------------
- Tenant readiness endpoints: `/tenant/<tenant>/readyz` and `/tenant/<tenant>/cost` (read-only)
- Metrics: `tenant_readiness_state`, `tenant_readiness_transitions_total`, `tenant_label_rejections_total`, `tenant_cost_estimate`
- Grafana dashboard: `devops/grafana/dashboards/tenant_readiness_dashboard.json`
- Alert routing examples: `devops/alerts/alertmanager-routing.yaml`
- CI workflow for observability tests: `.github/workflows/observability.yml`

Limitations & Known Issues
--------------------------
- Cardinality guard limits the number of tenant labels to `MAX_TENANT_LABELS` (default 100). High tenant cardinality requires operational review.
- Cost estimates are currently best-effort estimates exported by the runtime and are informational only.
- Chaos tests are opt-in and not run by default in CI.

Upgrade & Rollback
------------------
This release is additive. To roll back, revert the merge commit on `main` and redeploy the previous tag.

Contact & Reporting
-------------------
Report issues to the SRE channel or create issues in the repo with the `beta` label.
