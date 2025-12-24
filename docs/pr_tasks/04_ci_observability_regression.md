# PR Task: ci/observability-regression-tests

Owner: SRE
Estimate: 4 person-days

Purpose
-------
Add regression tests and linting for observability: promtool rule linting, alert rule regression tests, and automated checks that validate core metrics remain present.

Scope
- Add Prometheus rule lint step using `promtool check rules` in CI (staging and PR validation)
- Add sample Prometheus snapshot tests to validate alert expression behavior against canned data
- Integrate with existing observability CI workflow

Acceptance criteria
- promtool lint runs in CI and fails the job if rules are invalid
- Regression tests detect changes in alert behavior (via sample datasets)

Test cases
- Lint: `promtool check rules devops/alerts/tenant_alerts.yaml` passes
- Regression: sample series run against alert rules to ensure expected firing conditions

Reviewer checklist
- [ ] promtool included in CI environment or container
- [ ] Sample datasets are documented and stored in `tests/observability_samples/`

Notes
- These checks are read-only and validate rules; they do not alter alert routing.
