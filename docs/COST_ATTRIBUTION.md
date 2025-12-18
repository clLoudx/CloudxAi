# Cost Attribution (PHASE-6.6)

Purpose: Make cost visible and attributable per tenant.

## Cost units

- CPU: millicores × time
- Memory: MB × time
- Storage: artifact size
- Tokens: prompt + response
- Jobs: executions

# Cost Attribution (PHASE-6.6)

Purpose: Make cost visible and attributable per tenant.

## Cost units

- CPU: millicores × time
- Memory: MB × time
- Storage: artifact size
- Tokens: prompt + response
- Jobs: executions

## Cost model example

```python
class CostRecord:
    tenant_id: str
    task_id: str
    cpu_ms: int
    memory_mb_ms: int
    tokens: int
    artifacts_mb: int
```

## Enforcement

- Hard budgets per tenant
- Soft alerts at thresholds
- Automatic throttling
- Kill-switch available
