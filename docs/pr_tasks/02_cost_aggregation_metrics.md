# PR Task: cost/aggregation-metrics

Owner: Platform
Estimate: 5 person-days

Purpose
-------
Introduce additive aggregation metrics for v1.0 while preserving the existing `tenant_cost_estimate` metric. The goal is to add rollup-friendly metrics without renaming or mutating existing semantics.

Scope
- Add new metrics (examples):
  - `tenant_cost_estimate_rolling` (e.g., 1h rolling estimate)
  - `tenant_cost_billing_window` (aligned to billing window, e.g., daily)
- Exporters and unit tests for new metrics
- Documentation describing interpretation, currency, and window

Acceptance criteria
- New metrics emitted under new names; `tenant_cost_estimate` remains untouched
- Unit tests cover computation and exporter behavior
- Integration test that confirms metrics appear in a test Prometheus scrape

Test cases
- Unit: validate numerical computations and edge cases (no data, partial data)
- Integration: test exporter exposes metrics at `/metrics` and Prometheus scrape returns numeric samples

Reviewer checklist
- [ ] No changes to `tenant_cost_estimate` semantics or name
- [ ] New metrics documented with windows and currency
- [ ] Tests included and passing in CI

Rollout notes
- Feature should be enabled in staging first. Provide a feature flag or configuration toggle so operators can enable aggregation exporters in staging/GA.

Rollback
- Remove or disable exporters for the added metrics; since no renames happen, rollback is low-risk
