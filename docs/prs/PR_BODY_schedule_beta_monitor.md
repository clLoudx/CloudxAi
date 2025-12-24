Title: Draft PR — Beta: Daily Passive Monitor (feature/schedule-beta-monitor)

This draft PR adds a safe, scheduling-capable GitHub Actions workflow to run the passive beta monitor script daily and upload the observations and incident logs as artifacts. The workflow is intentionally guarded and will only execute when operators explicitly enable it via repository secrets. This PR is draft-only and must not be merged without explicit human approval.

Agent onboarding requirement
--------------------------
This repository includes a mandatory agent onboarding primer at `docs/AGENT_EXECUTION_PRIMER.md`. All automated agents and scripts that run as part of CI/CD or repository automation MUST be provided with and must acknowledge the exact onboarding sentence before performing any implementation work. The required onboarding sentence is:

> “Enter Execution Mode.
> Obey the Enterprise Roadmap.
> Confirm Phase and Scope.
> Produce Tests First.
> Emit Metrics and Events.
> Do Nothing Outside Approved Boundaries.”

Maintainers: see `docs/AGENT_EXECUTION_PRIMER.md` for the full text and usage guidance.

Summary of changes
------------------
- Add GitHub Actions workflow: `.github/workflows/daily-beta-monitor.yml`
  - Runs `python3 scripts/beta_monitor.py` (passive, file-only checks)
  - Uploads `BETA_OBSERVATIONS.md` and `BETA_INCIDENT_LOG.md` as artifacts
  - Trigger types: scheduled (daily) and manual dispatch
  - Safety guard: the job only executes when the repository secret `ENABLE_BETA_MONITOR` is set to the literal value `true`

Rationale
---------
Daily passive monitoring ensures we collect consistent, append-only observations during the beta stabilization window without modifying code, CI, or production systems. The workflow is designed to be safe-by-default and operator-controlled.

Merge requirements (MANDATORY)
----------------------------
- Human approval required before enabling schedule or adding the `ENABLE_BETA_MONITOR` secret
- Do NOT merge unless SRE/Platform reviews and confirms the operator enablement plan
- The workflow must remain guarded; do not remove the `ENABLE_BETA_MONITOR` guard

Reviewer guidance
------------------
- Confirm the workflow uses `workflow_dispatch` and a cron schedule, but only runs when `ENABLE_BETA_MONITOR=='true'`
- Confirm the workflow performs only read-only operations (script-run + artifact upload) and does not push commits
- Confirm the PR body documents operator steps to enable the secret and manual run instructions

Operator activation steps (post-merge, operator-only)
----------------------------------------
1. Add repository secret `ENABLE_BETA_MONITOR` with value `true` to enable scheduled runs.
2. (Optional) Manually dispatch the workflow from the Actions UI to perform an immediate run.
3. Inspect uploaded artifact `beta-observations` for `BETA_OBSERVATIONS.md` and `BETA_INCIDENT_LOG.md`.

Notes
-----
- The passive monitor script `scripts/beta_monitor.py` performs local file checks and appends to the observation file; it does not perform network writes or mutate repo content.
- If you prefer manual-only operation, leave `ENABLE_BETA_MONITOR` unset and run the workflow via `workflow_dispatch` as needed.

Branch: feature/schedule-beta-monitor

Draft PR URL (create via GitHub UI):
https://github.com/clLoudx/CloudxAi/pull/new/feature/schedule-beta-monitor

Labels: `beta-candidate`, `observability`, `ops`, `ci-required`
