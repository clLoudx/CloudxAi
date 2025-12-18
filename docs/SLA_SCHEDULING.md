# SLA-aware Scheduling (PHASE-6.5)

This document describes the SLA model, scheduler behavior, and metrics to implement the SLA-aware scheduler.

See `docs/MAX_LOGIC_FINAL_EXTENSION.md` for the full context.

## SLA example

```yaml
task:
  sla:
    priority: low | normal | high | critical
    max_latency_ms: 30000
    deadline: timestamp
    retry_policy: bounded
```

## Required Metrics

- task_sla_violation_total
- task_latency_ms
- task_deadline_miss_total

## Acceptance

- SLAs respected under load tests
- Violations observable
- No starvation
