# Readiness SLOs and Failure Budget

This document defines SLOs for readiness and related enforcement rules.

## Availability SLO
Readiness Availability ≥ 99.9% over rolling 30 days

Measured by PromQL:
```
avg_over_time(readiness_state[30d]) >= 0.999
```
Failure budget: ≤ 43 minutes of 'not ready' per 30 days.

## Transition Stability SLO
Detects flapping and instability:
```
increase(readiness_transitions_total[1h]) <= 10
```

## Latency SLO
Readiness check latency should be low:
```
p95(readiness_check_duration_seconds[5m]) < 0.2
```

## Notes
- readiness_state is a Gauge: 1=ready, 0=not ready
- readiness_transitions_total is a Counter of transitions
- readiness_check_duration_seconds is a Histogram (seconds)
