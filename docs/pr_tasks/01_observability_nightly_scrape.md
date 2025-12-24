# PR Task: observability/nightly-scrape-ci

Owner: SRE
Estimate: 3 person-days (draft PR -> staging-only CI job)

Purpose
-------
Add a staging-only nightly CI job that validates presence and basic format of core observability metrics via PromQL assertions. This PR is draft-only until operators approve running scrapes in staging.

Scope (what this PR should contain)
- CI workflow YAML (staging only, `workflow_dispatch` + schedule optional, to be enabled by operators)
- Minimal test runner that executes PromQL queries against a provided Prometheus endpoint (configurable via CI secrets)
- PromQL assertions covering:
  - `tenant_readiness_state` exists and exposes `tenant` label
  - `tenant_label_rejections_total` exists
  - `tenant_cost_estimate` exists and returns numeric samples
- Documentation: how to configure staging Prometheus endpoint and CI secret names

Acceptance criteria
- CI job runs in staging and completes without errors (no metric scraping in PR pipeline; staging only)
- PromQL assertions pass against staging Prometheus (records logged)
- PR includes README with setup steps for operators

Test cases
- Unit: mock Prometheus responses to validate assertion code paths
- Integration (staging): run the CI job pointing at staging Prometheus and record pass/fail

Reviewer checklist
- [ ] CI job YAML present and marked staging-only
- [ ] PromQL assertions are documented and targeted at stable metric names
- [ ] Secrets/config names are documented; no plaintext credentials in the PR

Risk & rollback
- Risk: accidental run against production if misconfigured. Mitigation: require explicit operator approval and secrets; add guard checks to CI job to abort if env var PRODUCTION=true

Notes
- This PR must not change metric names or labels. It only validates presence and basic format.
