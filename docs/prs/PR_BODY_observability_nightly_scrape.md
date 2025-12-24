Title: Draft PR — observability/nightly-scrape-ci

This draft PR adds a staging-only CI job to validate presence and basic format of core observability metrics via PromQL assertions.

Summary:
- Add `scripts/ci/promql_assertions.py` — Prometheus query/assertion runner (staging-only)
- Add `.github/workflows/staging-nightly-scrape.yml` — workflow with `workflow_dispatch` only by default
- Add documentation for configuring secrets and running the workflow in staging

Merge requirements (MANDATORY):
- Human approval required before enabling schedule or wiring secrets
- CI must be configured to point at staging Prometheus via secrets (STAGING_PROM_URL etc.)
- Do not merge unless operators confirm staging secrets/config are in place

Reviewer guidance:
- Confirm workflow is manual (no schedule) and uses staging secrets; no plaintext credentials
- Confirm `scripts/ci/promql_assertions.py` is safe and exits non-zero on API errors

Labels: `beta-candidate`, `observability`, `staging-only`, `ci-required`

Notes:
- This is a draft PR. Operators should enable schedule only after manual validation in staging. The workflow will upload the JSON results as an artifact for inspection.
