# Beta Incident & Recovery Drill (Paper-Only Simulation)

Purpose
-------
This document simulates a full incident and recovery drill for the beta period. It is paper-only and must not trigger any automated remediation. Use it to validate the runbook and incident policy.

Scenario: Cardinality Explosion (simulated)

Timeline
--------
1) T+0: Alert `TenantLabelCardinalityExceeded` fires in staging for `tenant_label_rejections_total > 0`.
2) T+2m: SRE oncall acknowledges. Initial triage: confirm scope (tenant-local vs global) and collect evidence.
3) T+5m: Ops run `tenant_label_rejections_total` query and `label_values(tenant_readiness_state, tenant)` to enumerate tenant labels.
4) T+10m: Identify a tenant onboarding job that churned labels (e.g., test-tenant-XYZ). Determine whether MAX_TENANT_LABELS was exceeded due to legitimate growth or noisy label keys.
5) T+30m: If impact limited to staging or isolated tenants, follow runbook: notify tenant owner, open issue with `beta` label, document mitigation (rate-limit onboarding or fix label generation).
6) T+2h: If global production impact, escalate per `BETA_INCIDENT_POLICY.md` (hotfix path). Hotfix requires human authorization.

Evidence to collect (paper-only)
- Prometheus query results: `increase(tenant_label_rejections_total[5m])`, `label_values(tenant_readiness_state, tenant)`
- Dashboard snapshots (links)
- CI workflow status (CI green must be preserved)
- Logs from tenant onboarding systems

Recovery playbook (paper-only)
- For tenant-local noisy labels: request tenant owner to stop noisy job; increase MAX_TENANT_LABELS only as a v1.0 planning item (do not change in beta).
- For production-wide cardinality explosion: follow hotfix process in `BETA_INCIDENT_POLICY.md` (create `hotfix/<desc>`, minimal diff, CI green required, tag hotfix). This requires explicit human authorization.

Post-incident
- Draft a post-incident report (append-only) and append to `BETA_INCIDENT_LOG.md` and `BETA_OBSERVATIONS.md`.
- Update runbook if procedural gaps discovered (draft-only; any code changes follow hotfix policy).

Exercise notes
--------------
- This drill should be run as a tabletop with platform, SRE, and product.
- Record time-to-detect, time-to-mitigate, and lessons learned in the post-incident report.
