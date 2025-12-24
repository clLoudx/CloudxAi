# PR Task: docs/migration-guides

Owner: Tech Writing
Estimate: 3 person-days

Purpose
-------
Create migration guides, compatibility notes, and deprecation timelines for any future metric additions or rollups. Ensure customers/operators understand how to interpret both beta and v1.0 metrics.

Scope
- Migration guide describing:
  - Existing metrics and their meaning
  - New aggregation metrics and interpretation
  - Deprecation policy (if any) and timelines (draft-only)
- FAQ and troubleshooting for cost estimation interpretation

Acceptance criteria
- Clear migration guide document in `docs/` with examples and PromQL snippets
- Review and sign-off by Platform & SRE

Reviewer checklist
- [ ] Docs are clear about not renaming existing metrics
- [ ] PromQL examples provided for common queries
