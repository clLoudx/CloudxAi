"""Tenant-aware cost attribution metrics (underscore package).

This module mirrors the hyphenated-package implementation but lives under
`ai_agent` so it can be imported by tests and the application.
"""
from os import getenv
from threading import Lock

try:
    from prometheus_client import Gauge
    _HAS_PROM = True
except Exception:
    Gauge = None
    _HAS_PROM = False

_DEFAULT_MAX_TENANT_LABELS = int(getenv("MAX_TENANT_LABELS", "100"))


class CardinalityError(Exception):
    pass


class TenantCostMetrics:
    def __init__(self):
        self._lock = Lock()
        self._store = {}  # fallback store: tenant -> cost
        self._seen = set()
        # instance-level cardinality so tests can mutate environment and
        # create a new instance with a different cap.
        self._max_tenant_labels = int(getenv("MAX_TENANT_LABELS", str(_DEFAULT_MAX_TENANT_LABELS)))
        if _HAS_PROM:
            # prometheus metric uses 'tenant' label
            self._g = Gauge(
                "tenant_cost_estimate",
                "Estimated cost for tenant",
                ["tenant"],
            )
        else:
            self._g = None

    def _ensure_cardinality(self, tenant: str):
        # If we have not seen this tenant and we've hit the cap, raise
        if tenant not in self._seen and len(self._seen) >= self._max_tenant_labels:
            raise CardinalityError(
                f"tenant label cap reached ({self._max_tenant_labels})"
            )

    def update_cost(self, tenant: str, amount: float):
        """Update the estimated cost for a tenant.

        Raises CardinalityError if adding the tenant would exceed the cap.
        """
        if tenant is None:
            raise ValueError("tenant must be a string")
        with self._lock:
            self._ensure_cardinality(tenant)
            self._seen.add(tenant)
            self._store[tenant] = float(amount)
            if self._g:
                try:
                    self._g.labels(tenant=tenant).set(float(amount))
                except Exception:
                    # metrics should not crash callers
                    pass

    def get_cost(self, tenant: str) -> float or None:
        """Return the last recorded cost for tenant, or None if unknown."""
        return self._store.get(tenant)

    def get_seen_tenant_count(self) -> int:
        return len(self._seen)


__all__ = ["TenantCostMetrics", "CardinalityError"]
