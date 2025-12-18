import pytest
import asyncio
import time
from httpx import AsyncClient
from ai.controller.fastapi_app import app
from ai_agent.agent_registry import InMemoryAgentRegistry, AgentSpec
from ai.controller.health_monitor import HealthMonitor, HealthStatus


@pytest.mark.asyncio
async def test_metrics_endpoint_reports_degraded_and_recovered():
    async with app.router.lifespan_context(app):
        # app.state.monitor and controller are set by lifespan
        monitor: HealthMonitor = app.state.monitor
        registry = monitor.agent_registry

        agent_id = "agent-metrics"
        await registry.register_agent(agent_id, AgentSpec(name="M", version="1.0", capabilities={}))

        # ensure initial HEALTHY
        await registry.update_agent_status(agent_id, HealthStatus.HEALTHY)

        async def fail(agent_id_arg):
            raise Exception("boom")

        monitor.poll_agent_health = fail
        await monitor.poll_agent_health(agent_id)
        # allow event handler to run
        await asyncio.sleep(0.05)

        # check in-memory controller metrics and metrics endpoint contains metric name
        controller = app.state.controller
        assert controller.metrics["degraded"] == 1

        # check metrics endpoint contains the metric name
        from ai.controller.fastapi_app import metrics
        resp = await metrics()
        # Starlette Response has .body as bytes
        text = resp.body.decode()
        assert "aicloudxagent_agent_degraded" in text

        # cause recovery
        await registry.update_agent_status(agent_id, HealthStatus.UNHEALTHY)
        # call default poll impl to set HEALTHY
        await monitor._default_poll_impl(agent_id)
        await asyncio.sleep(0.05)

        controller = app.state.controller
        assert controller.metrics["recovered"] == 1

        resp = await metrics()
        text = resp.body.decode()
        assert "aicloudxagent_agent_recovered" in text


@pytest.mark.asyncio
async def test_metrics_endpoint_non_blocking_with_slow_handler():
    async with app.router.lifespan_context(app):
        monitor: HealthMonitor = app.state.monitor
        registry = monitor.agent_registry

        agent_id = "agent-slow-metrics"
        await registry.register_agent(agent_id, AgentSpec(name="S", version="1.0", capabilities={}))

        # register a slow handler
        ev = asyncio.Event()

        async def slow_handler(event):
            await asyncio.sleep(0.5)
            ev.set()

        monitor.register_event_handler(slow_handler)

        # set initial healthy and trigger degraded
        await registry.update_agent_status(agent_id, HealthStatus.HEALTHY)

        async def fail(agent_id_arg):
            raise Exception("boom")

        monitor.poll_agent_health = fail

        # trigger poll which will schedule slow handler
        await monitor.poll_agent_health(agent_id)

        # immediately request metrics and ensure it returns quickly
        from ai.controller.fastapi_app import metrics
        start = time.monotonic()
        resp = await metrics()
        assert resp.status_code == 200
        elapsed = time.monotonic() - start

        assert elapsed < 0.1

        # ensure slow handler completed eventually
        await asyncio.wait_for(ev.wait(), timeout=1.0)
