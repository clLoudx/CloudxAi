# Read-Only AI Auditors (PHASE-6.7)

Purpose: Use AI only to observe, never to act. Auditors read events, metrics, and logs and generate advisory reports for humans.

## Auditor capabilities

- Read logs
- Read metrics
- Read events
- Detect anomalies
- Generate reports

## Forbidden capabilities

- Execute code
- Modify tasks
- Change configuration
- Trigger actions

## Deployment model

```text
Logs → Metrics → Events
          ↓
     AI Auditor
          ↓
     Human Report
```

Governance

- Auditor outputs are advisory
- Humans decide
- Auditors are stateless
- No feedback loops
