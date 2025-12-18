# Bootstrap & Lifecycle Guide

This document explains how the AI orchestration components are wired at startup and shutdown, how the health monitoring signals flow, and how to observe metrics. It is intentionally concise and operational — suitable for maintainers and on-call engineers.

## 1. System Lifecycle Overview

At a high level the system has three orchestration-only components:

- Agent Registry (`InMemoryAgentRegistry`): Holds agent specs and status values.
- HealthMonitor (`HealthMonitor`): Periodically polls agents for health and emits typed events on status transitions.
- Controller (`Controller`): Consumes health events, performs structured logging and increments in-memory + Prometheus metrics.

These components are intentionally separated: the controller never performs inference or task execution. It is orchestration-only.

The FastAPI app (`ai.controller.fastapi_app`) wires these components during the application lifespan.

## 2. Bootstrap Flow (Step-by-Step)

1. `bootstrap_monitor(start_loop=False|True)` (in `ai.bootstrap`) is the idiomatic entrypoint for wiring:
   - Creates/accepts an `InMemoryAgentRegistry` instance.
   - Instantiates `HealthMonitor` and `Controller`.
   - Registers `controller.handle_agent_health_event` as an event handler on the monitor.
   - If `start_loop=True`, schedules `monitor.monitor_agents()` as a background task and returns it to the caller.

2. FastAPI app (`ai.controller.fastapi_app`) uses a lifespan context manager to call `bootstrap_monitor(start_loop=True)` during startup and cancels the scheduled monitor task on shutdown. The monitor, controller, and task are attached to `app.state`.

3. The `monitor.monitor_agents()` loop runs indefinitely until cancelled. It lists agents from the registry, schedules health checking tasks for each agent via `asyncio.create_task(self.poll_agent_health(agent_id))`, and sleeps between rounds.

4. The scheduled monitor task is cancelled at shutdown; the code awaits task cancellation and ignores `asyncio.CancelledError` to ensure graceful shutdown.

## 3. Health & Signals Path

- HealthMonitor polls agents (default poll implementation) and computes a `HealthStatus` (HEALTHY, DEGRADED, UNHEALTHY).
- The HealthMonitor stores the status in the registry and performs *edge-detection*: it only emits a typed event if the agent transitions between HEALTHY and non-HEALTHY states (e.g., HEALTHY -> DEGRADED, UNHEALTHY -> HEALTHY).
- Events are Pydantic models in `ai.controller.signals`: `AgentDegradedEvent` and `AgentRecoveredEvent` (both inherit from `AgentHealthEvent`). Events include `agent_id`, `previous_status`, `current_status`, `timestamp` (UTC), and optional `reason`.
- Event handlers are async callables registered with `HealthMonitor.register_event_handler(handler)`. Handlers are scheduled with `asyncio.create_task(handler(event))` to avoid blocking the monitor.

Important guarantees:

- Edge-triggered: no event spam during stable status.

- Non-blocking dispatch: slow handlers won't block the monitor loop.

- Observability: events contain a timezone-aware ISO8601 UTC timestamp.

## 4. Metrics

Two Prometheus counters are exposed and incremented by the controller:

- `aicloudxagent_agent_degraded_total` — incremented when an `AgentDegradedEvent` is observed.
- `aicloudxagent_agent_recovered_total` — incremented when an `AgentRecoveredEvent` is observed.

The FastAPI app exposes `/metrics` which returns the Prometheus exposition text format. Example:

```bash
curl -s http://localhost:8000/metrics | grep aicloudxagent_agent_degraded
```

Note: The tests mirror in-memory controller metrics for precise assertions (the Prometheus client uses a global registry which can be shared between processes/tests).

## 5. How to Run & Test

Run the FastAPI app (development):

```bash
# run on port 8000
uvicorn ai.controller.fastapi_app:app --reload
```

Run the monitor alone (tests and scripts may prefer this pattern):

```python
from ai.bootstrap import bootstrap_monitor
import asyncio

async def main():
    monitor, controller, task = await bootstrap_monitor(start_loop=True)
    # run for 60 seconds
    await asyncio.sleep(60)
    task.cancel()
    await task

asyncio.run(main())
```

Run tests:

```bash
/your/venv/bin/python -m pytest tests -q
```

Notes about lifecycle and asyncio testing:

- Tests use the FastAPI app's lifespan context via `app.router.lifespan_context(app)` to trigger startup/shutdown.

- Tests avoid brittle textual assertions on Prometheus exposition values; they assert in-memory controller counters for numeric correctness and check `/metrics` exposes metric names.

## 6. Explicit Non-Goals (Important)

- The controller does NOT perform agent task execution, policy enforcement, remediation, or quarantine. Those behaviors are outside the scope of PHASE 5.
- The registry used in PHASE 5 is an in-memory implementation for simplicity and testing. Persistent registries (DB-backed) can be introduced later behind the same protocol.

## 7. Handoff & Next Steps

After PHASE 5, recommended next steps:

1. Add metrics exporter or Prometheus scrape rules to deployment manifests.
2. Introduce persistent agent registry or a pluggable registry implementation.
3. Design PHASE 6 (execution engine, job persistence, safe remediation pathways).

---

If you'd like, I can also:

- Add a short `CONTRIBUTING.md` note for maintainers describing how to safely extend the monitoring event handlers.

- Approve this doc and I'll prepare an atomic commit message and create the PR-ready change set if you want the changes staged/committed.

---

## Appendix A — Prometheus scrape examples

Two minimal examples are provided below to help operators scrape the FastAPI `/metrics` endpoint exposed by the controller app. Adjust `job_name`, `namespace`, `relabel_configs`, and `static_configs` as appropriate for your environment.

### Kubernetes (Service scrape)

If your app is exposed via a `Service` in Kubernetes, a simple `ServiceMonitor` (Prometheus Operator) or a direct scrape config can be used. Example Prometheus scrape config targeting a service named `aicloudxagent` in the `default` namespace:

```yaml
- job_name: 'aicloudxagent'
    kubernetes_sd_configs:
        - role: endpoints
    relabel_configs:
        - source_labels: [__meta_kubernetes_service_name]
            regex: aicloudxagent
            action: keep
        - source_labels: [__meta_kubernetes_namespace]
            regex: default
            action: keep
    metrics_path: /metrics
    scheme: http
    # If your service listens on a port named "http"/"metrics", prometheus will auto-discover it.
    # static_configs may be used for simple single-node setups.
```

If you use the Prometheus Operator, a `ServiceMonitor` would look like:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
    name: aicloudxagent-servicemonitor
    labels:
        release: prometheus
spec:
    selector:
        matchLabels:
            app: aicloudxagent
    namespaceSelector:
        matchNames:
            - default
    endpoints:
        - port: http
            path: /metrics
            interval: 30s
```

### Docker Compose (static scrape)

For a local docker-compose setup where the app is reachable at `http://localhost:8000/metrics`, add a `static_configs` block:

```yaml
- job_name: 'aicloudxagent-local'
    metrics_path: /metrics
    static_configs:
        - targets: ['host.docker.internal:8000'] # or ['localhost:8000'] depending on your platform
```

Notes:

- The FastAPI app exposes `/metrics` by default at the server port you run it on (e.g., 8000). Ensure your ingress/service/port mapping makes that endpoint reachable to Prometheus.
- If your deployment uses TLS/HTTPS, set `scheme: https` and configure TLS settings or use a sidecar that exposes plaintext metrics to Prometheus.
- For containerized deployments, prefer scraping via a Kubernetes `Service` + `ServiceMonitor` (if using Prometheus Operator) instead of host-level ports.

---


