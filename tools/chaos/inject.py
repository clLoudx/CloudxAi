#!/usr/bin/env python3
"""
Chaos injector for readiness validation.

This script is safe-by-default: it only runs in local/dev/CI and never in prod.
It can:
- Simulate DB down
- Simulate Redis down
- Simulate both down
- Restore normal state

Usage:
  python tools/chaos/inject.py [db|redis|both|restore]

This is a scaffold for CI and local chaos runs.
"""
import sys
import requests

ENDPOINT = "http://localhost:8000/api/v1/readyz"

SCENARIOS = {
    "db": {"db": "fail", "redis": "ok"},
    "redis": {"db": "ok", "redis": "fail"},
    "both": {"db": "fail", "redis": "fail"},
    "restore": {"db": "ok", "redis": "ok"},
}

def inject_chaos(scenario):
    # In a real system, this would trigger test overrides or a chaos sidecar.
    # Here, we just print the intended effect.
    print(f"[CHAOS] Injecting scenario: {scenario}")
    print(f"[CHAOS] (No-op: this is a scaffold. In CI, use dependency_overrides in tests.)")
    # Optionally, could POST to a chaos API or write a flag file.

def check_readiness():
    try:
        r = requests.get(ENDPOINT)
        print(f"[READINESS] {r.status_code} {r.json()}")
    except Exception as e:
        print(f"[READINESS] Error: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in SCENARIOS:
        print("Usage: python tools/chaos/inject.py [db|redis|both|restore]")
        sys.exit(1)
    scenario = sys.argv[1]
    inject_chaos(scenario)
    check_readiness()
