
# Chaos & Readiness Testing — Enterprise Guide

## Purpose

This directory contains **explicit, opt-in chaos tests** that validate the system’s **readiness and health contracts** under failure conditions.

These tests **do not run by default** and **must never execute accidentally** in CI or local development unless explicitly enabled.

Their role is to **prove invariants**, not to simulate production outages implicitly.

---

## Readiness Contract (Invariant)

The system guarantees the following:

| Condition                                    | Expected Result                                     |
| -------------------------------------------- | --------------------------------------------------- |
| Process alive                                | `/healthz` returns `200 OK`                         |
| Critical dependency unavailable (DB / Redis) | `/readyz` returns `200 OK` with `status: not ready` |
| Process dead                                 | No response                                         |

> **Important:**
> Health checks reflect **process liveness**.
> Readiness checks reflect **dependency availability**.

This contract is **non-negotiable** and enforced by tests.

---

## Chaos Tests

### What Chaos Tests Do

Chaos tests intentionally simulate failure conditions such as:

* Database unavailable
* Redis unavailable
* Dependency initialization failures

They verify that:

* The application responds deterministically
* Readiness status is correct
* The service does **not crash**

### What Chaos Tests Do NOT Do

* They do **not** bring down real infrastructure
* They do **not** modify production data
* They do **not** run automatically

---

## Execution Safety (Critical)

### Chaos tests are **opt-in only**

They are marked explicitly using `pytest` markers.

### Marker definition

```ini
# pytest.ini
[pytest]
markers =
    chaos: failure-injection and readiness chaos tests (opt-in only)
```

### Marking chaos tests

```python
import pytest

@pytest.mark.chaos
def test_dashboard_healthz():
    ...
```

---

## How to Run Chaos Tests

### Run ONLY chaos tests

```bash
pytest -m chaos
```

### Run everything EXCEPT chaos tests (default)

```bash
pytest -m "not chaos"
```

### CI / automation (recommended)

Chaos tests **must be excluded** unless explicitly enabled:

```bash
pytest -m "not chaos"
```

---

## Test Scope

Current chaos tests validate:

* Dashboard `/healthz` endpoint availability
* Correct app instantiation (single app instance)
* Deterministic behavior under simulated failure

Future chaos extensions may include:

* DB failure injection
* Redis failure injection
* Network latency simulation (non-blocking)

---

## Extension Rules (For Agents)

When adding new chaos tests:

1. **Always use `@pytest.mark.chaos`**
2. **Never rely on real external services**
3. **Use dependency overrides or mocks only**
4. **Tests must be deterministic**
5. **Document the invariant being validated**

Any chaos test violating these rules must be rejected.

---

## Phase Status

| Item                            | Status     |
| ------------------------------- | ---------- |
| Chaos readiness tests           | ✅ Complete |
| Single app instance enforcement | ✅ Complete |
| Chaos documentation             | ✅ Complete |
| Execution safety (markers)      | ⏳ Ready    |
| SLA / Metrics phase             | 🔜 Next    |

---

## Authoritative Guidance for Agents

> **Chaos is a verification tool, not a stress toy.**
> **If a chaos test is not explicitly marked, it must not exist.**
> **Readiness must never lie.**

---

### ✅ This README closes the Chaos Readiness phase.

If you want, next I can:

* Add **pytest chaos markers** formally
* Start **SLA & readiness metrics**
* Generate **Prometheus alerts**
* Advance to **multi-tenant isolation**

Just say the word.

---

If you need a stricter gating mechanism (e.g., pytest marker `@pytest.mark.chaos`), I can add a recommended marker and CI doc entry to ensure these tests only run under allowed conditions.
