# Roadmap — v1.0 Tenant-Aware Observability & Billing

Goal
----
Deliver a production-grade Tenant-Aware Observability and Cost Attribution platform that supports billing, quota, and fine-grained SLOs while preserving readiness semantics.

Milestones
----------
1. Tenant Observability Hardened (current beta)
   - Complete Grafana dashboards, alert routing, and operational playbooks.
2. Billing-Ready Metrics (v1.0-alpha)
   - Add high-fidelity cost attribution metrics, per-tenant rollups, and export hooks.
   - Ensure cardinality controls and aggregation to prevent label explosion.
3. Quota & Billing Integration (v1.0-beta)
   - Add quota enforcement hooks (read-only initially, then opt-in control plane).
   - Integrate with billing systems for invoicing and chargeback.
4. v1.0 Release
   - Hardened SLOs, dashboards, and runbooks; full production rollout plan.

Risks & Mitigations
-------------------
- Metric cardinality — maintain label caps and aggregation strategies.
- Billing correctness — start with read-only attribution, validate with sample data.
- Operational complexity — provide simple dashboards for non-engineers, and detailed ones for SRE.

Next Steps (initial tasks)
-------------------------
- Design per-tenant rollup storage (time-series downsampling or aggregated exporter).
- Define billing window semantics and currency handling.
- Draft integration plan for external billing provider (Stripe/Cloud billing connector).
- Schedule spike to validate scale and cardinality behavior with synthetic tenants.

Deliverables
------------
- Architecture doc (detailed design)
- Implementation plan with PRs and CI gating
- Test plan and load validation scripts
