# PR Task: storage/remote-write-compat

Owner: Platform
Estimate: 5 person-days

Purpose
-------
Add documentation and optional configuration to support Prometheus remote_write to Cortex/Thanos or other long-term storage. Do not change runtime defaults.

Scope
- Documentation + examples for `prometheus.yml` remote_write config
- Optional integration test harness (local) that verifies remote_write request formatting
- Retention and cost guidance for GA

Acceptance criteria
- Clear docs with examples for remote_write to Cortex/Thanos
- Integration harness that demonstrates the remote_write flow (no production changes)

Reviewer checklist
- [ ] Docs include example `prometheus.yml` snippets and required credentials/roles
- [ ] No runtime behavioral changes by default

Risk & mitigation
- Risk: exposing credentials in examples — Mitigation: use placeholders and document secret management
