# PR Task: scalability/synthetic-tenant-harness

Owner: Performance
Estimate: 7 person-days

Purpose
-------
Create a synthetic tenant generator and load harness to simulate many tenants, generate readiness and cost metrics, and validate cardinality guard behavior and Prometheus ingest performance.

Scope
- Synthetic tenant generator (configurable N tenants, label churn rates)
- Harness runner that emits metrics over HTTP or pushes to a test Prometheus remote_write endpoint
- Scripts to aggregate results and produce simple dashboards/CSV outputs

Acceptance criteria
- Harness can simulate target scale (e.g., 1k, 5k, 10k tenants) in a controlled environment
- Demonstrated capture of `tenant_label_rejections_total` and validation of correctness
- Performance stats: scrape time, cardinality impact, CPU/memory of Prometheus

Test cases
- Functional: small-scale run validating metric emission
- Scale: stepwise increase to target levels; record metrics and system resource usage

Reviewer checklist
- [ ] Harness includes configuration for label churn and tenant count
- [ ] Results collection and basic visualization scripts included

Notes
- Run harness in staging or dedicated performance environment only. Do NOT run against production Prometheus.
