# v1.0 Planning Pack (Draft)

Purpose
-------
Draft planning pack for v1.0. This document is for planning only and must not be executed or merged during the beta stabilization window.

Scope
-----
- Cost aggregation semantics
- Billing window definition
- Storage backend decisions for cost/time series & rollups
- Scalability testing harness and target SLAs
- Risk matrix and migration notes
- CI expansion plan

Sections
--------

1) Cost aggregation semantics (draft)
   - Input: `tenant_cost_estimate` (rolling estimate per tenant)
   - Goal: define a rolling vs. bucketed billing window. Recommendation: support both in v1.0 via dual metrics:
     - `tenant_cost_estimate_rolling` (observational shorter window, e.g., 1h)
     - `tenant_cost_billing_window` (aligned to billing window, e.g., daily UTC)
   - Migration: provide translation rules and an opt-in flag for early tenants; do not rename existing `tenant_cost_estimate` metric in place.

2) Billing window definition
   - Options: rolling 1h / daily UTC / monthly UTC
   - Recommendation: GA default daily UTC with optional hourly rollups for real-time ops.

3) Storage backend decision
   - Options: Prometheus TSDB (remote-write to Cortex/Thanos), Long term store (ClickHouse), time-series DB (InfluxDB)
   - Recommendation: Prometheus remote-write -> Cortex + object storage for scale; use ClickHouse for aggregated cost rollups if complex queries needed.

4) Scalability testing harness
   - Create a synthetic tenant generator to simulate N tenants and produce cost metrics and readiness checks.
   - Target: validate MAX_TENANT_LABELS enforcement at scale; measure scrape/ingestion cost.

5) Risk matrix
   - Label cardinality explosion — mitigations: cardinality guard, alerting, quota escalation
   - Metric regressions — mitigations: CI observability tests, monotonicity checks

6) Migration notes (beta → GA)
   - Never rename existing metrics; add new metrics and deprecate via docs and alerts
   - Provide translation dashboards and compatibility flags

7) CI expansion plan
   - Add nightly smoke test that scrapes metrics in staging and validates presence/format
   - Add regression tests for alert routing

Owners & Next steps
-------------------
- Platform: platform-team@example.com
- SRE: sre-team@example.com
- Product: product-owner@example.com

This planning pack is a draft-only artifact produced by the MAX-LOGIC autonomous continuation. No changes to code or workflows are performed here.
