"""Unit-style test for TenantCostMetrics.

This file can be executed both under pytest and directly via python. It
contains simple assertions and a minimal runner so CI can run pytest and
local constrained environments can execute the file for quick checks.
"""
import os
import sys

# Ensure repo root is on sys.path so tests can import local packages when run
# as `python tests/...` (the runner sets sys.path[0] to the tests dir).
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..")))

try:
    from ai_agent.observability.cost_metrics import TenantCostMetrics, CardinalityError
except Exception:
    # If importing the package triggers heavy deps (pydantic, etc.), try a
    # direct-file import so tests can run in constrained environments.
    import importlib.util

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    module_path = os.path.join(repo_root, "ai_agent", "observability", "cost_metrics.py")
    spec = importlib.util.spec_from_file_location("cost_metrics", module_path)
    cost_metrics = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(cost_metrics)
    TenantCostMetrics = cost_metrics.TenantCostMetrics
    CardinalityError = cost_metrics.CardinalityError


def test_update_and_get():
    m = TenantCostMetrics()
    m.update_cost("tenant-a", 12.5)
    assert m.get_cost("tenant-a") == 12.5


def test_cardinality_guard():
    m = TenantCostMetrics()
    # temporarily lower the cap to exercise behavior
    import os

    os.environ.setdefault("MAX_TENANT_LABELS", "2")
    # recreate instance so it picks up new cap
    m2 = TenantCostMetrics()
    m2.update_cost("t1", 1.0)
    m2.update_cost("t2", 2.0)
    try:
        m2.update_cost("t3", 3.0)
        # If no exception, that's a test failure
        raise AssertionError("Expected CardinalityError")
    except CardinalityError:
        pass


if __name__ == "__main__":
    # Run the tests in environments without pytest
    test_update_and_get()
    test_cardinality_guard()
    print("observability cost metrics tests passed")
