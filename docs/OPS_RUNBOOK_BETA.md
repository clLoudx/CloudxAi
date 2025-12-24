# Ops Runbook — v0.9.0-beta (Tenant Observability & Cost Attribution)

Purpose
-------
This runbook provides step-by-step operational procedures to validate, monitor, and respond to incidents during the v0.9.0-beta period. It is read-only with respect to readiness semantics and assumes all changes are observational.

Mandatory invariant
-------------------
"Readiness is a contract. Metrics are evidence. Chaos proves truth. I will not change locked semantics."

Preconditions
-------------
- v0.9.0-beta is deployed and tag pushed
- Prometheus and Grafana are available and scraping metrics
- Alertmanager routing is configured as per `devops/alerts/alertmanager-routing.yaml`

Quick references
----------------
- Dashboard JSON: `devops/grafana/dashboards/tenant_readiness_dashboard.json`
- Grafana README: `devops/grafana/README.md`
- Prometheus rules: `devops/alerts/tenant_alerts.yaml`
- Incident policy: `BETA_INCIDENT_POLICY.md`

Runbook sections
-----------------

1) Import dashboard (one-time)
   - UI method (recommended):
     1. Grafana → Dashboards → Manage → Import
     2. Upload `devops/grafana/dashboards/tenant_readiness_dashboard.json`
     3. Select Prometheus datasource and import
   - API method (automated):
     ```bash
     GRAFANA_URL=https://grafana.example
     API_KEY=REPLACE_ME
     curl -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
       -X POST -d @devops/grafana/dashboards/tenant_readiness_dashboard.json \
       $GRAFANA_URL/api/dashboards/db
     ```

2) Basic validation (after import)
   - Confirm `$tenant` dropdown populated: template query = `label_values(tenant_readiness_state, tenant)`
   - Select a tenant and verify panels render data for:
     - `tenant_readiness_state{tenant="$tenant"}`
     - `tenant_cost_estimate{tenant="$tenant"}`
     - `increase(tenant_cost_estimate{tenant="$tenant"}[1h])`
     - `increase(tenant_label_rejections_total[5m])`
   - Confirm Safety Backstop shows `readiness_state` and `tenant_readiness_state{tenant="$tenant"}`

3) Smoke tests (staging only)
   - Readiness endpoint:
     ```bash
     curl -sS https://<dashboard-host>/tenant/example/readyz
     ```
   - Cost endpoint:
     ```bash
     curl -sS https://<dashboard-host>/tenant/example/cost
     ```
   - Expect 200 responses or 404 for unknown cost; 429 if cardinality rejected. No writes are permitted.

4) Cardinality simulation (staging)
   - Purpose: verify `tenant_label_rejections_total` increments when cap is exceeded
   - Example (simulate 120 tenants against default cap 100):
     ```bash
     for i in $(seq 1 120); do
       curl -s -o /dev/null -w "%{http_code}\n" "https://<dashboard-host>/tenant/test-$i/readyz" &
     done
     wait
     ```
   - Inspect Prometheus or Grafana panel for rejections: `increase(tenant_label_rejections_total[5m])`

5) Alerting verification
   - Lint rules:
     ```bash
     promtool check rules devops/alerts/tenant_alerts.yaml
     promtool check rules devops/alerts/alertmanager-routing.yaml
     ```
   - Trigger a test alert in staging and verify it routes to expected receiver.

6) Incident detection & first response
   - Detection sources: Grafana, Prometheus alerts, SRE pager
   - Initial triage steps (SRE):
     1. Confirm scope: tenant-specific or global
     2. Check `readiness_state` (global) vs `tenant_readiness_state{tenant=...}`
     3. Check `tenant_label_rejections_total` for cardinality issues
     4. Check `tenant_cost_estimate` and cost trend for unexpected spikes
     5. Gather logs, traces, and timeline
   - If issue is tenant-local and observational: open an issue with `beta` label and notify tenant owner

7) Hotfix path (critical only)
   - If immediate code fix required (and severity justifies):
     1. Create `hotfix/<desc>` from `main`
     2. Implement minimal fix and tests
     3. PR to `main`, reviewers: SRE + senior engineer
     4. Merge only after CI green
     5. Tag hotfix (e.g., `v0.9.1-beta-hotfix-1`)
   - Remember: no metric renames, no readiness semantic changes

8) Post-incident
   - Write post-incident report (root cause, fix, follow-ups)
   - Update `BETA_INCIDENT_POLICY.md` if process improvements needed

9) Ops escalation matrix
   - Pager: SRE oncall
   - Secondary: Platform lead
   - Tertiary: Engineering manager

10) Runbook maintenance
    - Update this file for any procedural changes
    - Keep a copy in Confluence/Google Drive for non-dev access

Appendix: Useful PromQL
-----------------------
- Current tenants: `label_values(tenant_readiness_state, tenant)`
- Tenant readiness: `tenant_readiness_state{tenant="$tenant"}`
- Tenant cost: `tenant_cost_estimate{tenant="$tenant"}`
- Cardinality rejections: `increase(tenant_label_rejections_total[5m])`
- Global readiness: `readiness_state`

Contact & ownership
--------------------
- SRE Oncall: @sre-oncall
- Platform: platform-team@example.com
- Product: product-owner@example.com
