# Threat Model & Attack Surface — Enterprise Execution System

## Core Threat Categories

| Threat             | Vector                | Mitigation                     |
| ------------------ | --------------------- | ------------------------------ |
| Task Escalation    | Malicious job payload | Isolated workspace, no secrets |
| Data Exfiltration  | Network access        | Network disabled by default    |
| Infinite Execution | Hung worker           | Lease + timeout + kill         |
| DB Corruption      | Bad migration         | Idempotent migrations          |
| Agent Drift        | Self-decision         | Phase + human gates            |
| Supply Chain       | Dependency poisoning  | Pinned deps, review            |
| Log Leakage        | Secrets in logs       | Redaction + scanning           |

## Attack Surface Map

```text
API → Control Plane → Queue → Worker → StepRunner → Artifacts
                    ↑                         ↓
                 Governance               Observability
```

Rule: Every arrow must be logged, measured, and auditable.
