"""
Global readiness is immutable.
Tenant readiness is isolated.
No tenant may affect another tenant or the system.
"""

# Multi-Tenant Readiness Design Spec

Core contract
---------------
"Global readiness is immutable. Tenant readiness is isolated. No tenant may affect another tenant or the system."

This document specifies how tenant-scoped readiness is added to the platform while preserving the locked global semantics. Follow these rules exactly.

1. Global readiness
   - `/healthz` remains liveness-only.
   - `/readyz` remains the authoritative global readiness contract. It must not be modified.

2. Tenant readiness semantics
   - New endpoints are namespaced under `/tenant/<tenant>/...`.
   - Tenant readiness is a contract scoped to a tenant identifier.
   - Tenant readiness may be toggled for testing via API but defaults to inherited global readiness if unset.

3. Metrics schema
   - tenant_readiness_state{tenant="..."} Gauge: 1=ready,0=not ready
   - tenant_readiness_transitions_total{tenant="..."} Counter: transitions per tenant
   - tenant_readiness_check_duration_seconds{tenant="..."} Histogram (optional, only if enabled)
   - A global guard counter tenant_label_rejections_total counts label-cardinality rejections

4. Cardinality & guards
   - Enforce a hard cap on distinct tenant label values (configurable via `MAX_TENANT_LABELS`, default 100).
   - If the cap would be exceeded by a new tenant label, the operation to create the label must be rejected with HTTP 429 and reason `label_cardinality_limit` and the rejection counter incremented.
   - Agents must use stable tenant identifiers (no generating unique tenant per request).

5. Failure isolation invariants
   - Any tenant failure must not flip global `/readyz` to `not ready`.
   - Tenant endpoints may degrade to `unknown` or `error` but must never mutate global readiness state.
   - Chaos tests are opt-in and must be gated in CI.

6. API
   - GET `/tenant/<tenant>/readyz` — returns JSON {status: "ready"|"not ready"}
   - POST `/tenant/<tenant>/set_ready` — body `{'ready': true|false}` sets tenant readiness (requires API key)
   - Metrics available on `/metrics` with tenant labels.

7. Tests
   - Unit tests verify tenant isolation and cardinality enforcement.
   - Chaos tests (pytest marker `chaos`) simulate failure injection for a tenant and assert no global readiness change.

Change control
---------------
All changes must be additive and provide tests and alerts. Any change that affects `/readyz` or existing metrics is forbidden.

Revision history
-----------------
- 2025-12-23 — Initial spec (Max-Logic locked semantics)