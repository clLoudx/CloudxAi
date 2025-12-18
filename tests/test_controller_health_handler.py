import pytest
import asyncio
import time
from ai.controller.health_monitor import HealthMonitor, HealthStatus
from ai_agent.agent_registry import InMemoryAgentRegistry, AgentSpec
from ai.controller.controller import Controller

@pytest.mark.asyncio
async def test_handler_invoked_on_degraded_and_recovered():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)
    controller = Controller()

    agent_id = "agent-ctl"
    await registry.register_agent(agent_id, AgentSpec(name="C", version="1.0", capabilities={}))

    # subscribe controller handler
    monitor.register_event_handler(controller.handle_agent_health_event)

    # cause degraded event
    await registry.update_agent_status(agent_id, HealthStatus.HEALTHY)

    async def fail(agent_id_arg):
        raise Exception("boom")

    monitor.poll_agent_health = fail

    ev = asyncio.Event()

    async def watch():
        # wait until controller.last_event is set
        while controller.last_event is None:
            await asyncio.sleep(0.01)
        ev.set()

    asyncio.create_task(watch())
    await monitor.poll_agent_health(agent_id)
    await asyncio.wait_for(ev.wait(), timeout=1.0)

    assert controller.metrics["degraded"] == 1

    # cause recovery via default poll
    # reset last_event and set registry unhealthy
    controller.last_event = None
    await registry.update_agent_status(agent_id, HealthStatus.UNHEALTHY)

    # use default poll to set HEALTHY by calling the monitor's internal default
    await monitor._default_poll_impl(agent_id)

    # wait for controller to receive recovered event
    ev2 = asyncio.Event()

    async def watch2():
        while controller.last_event is None or controller.last_event.current_status != HealthStatus.HEALTHY.value:
            await asyncio.sleep(0.01)
        ev2.set()

    asyncio.create_task(watch2())
    await asyncio.wait_for(ev2.wait(), timeout=1.0)

    assert controller.metrics["recovered"] == 1

@pytest.mark.asyncio
async def test_handler_not_invoked_on_unknown_to_healthy():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)
    controller = Controller()

    agent_id = "agent-new-ctl"
    await registry.register_agent(agent_id, AgentSpec(name="N", version="1.0", capabilities={}))

    monitor.register_event_handler(controller.handle_agent_health_event)

    # default state is UNKNOWN -> HEALTHY; should not emit
    await monitor.poll_agent_health(agent_id)

    await asyncio.sleep(0.05)

    assert controller.metrics["degraded"] == 0
    assert controller.metrics["recovered"] == 0

@pytest.mark.asyncio
async def test_handler_does_not_block_monitor_loop():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)
    controller = Controller()

    agent_id = "agent-slow"
    await registry.register_agent(agent_id, AgentSpec(name="S", version="1.0", capabilities={}))

    # register a slow handler to simulate a blocking handler
    ev = asyncio.Event()

    async def slow_handler(event):
        await asyncio.sleep(0.2)
        ev.set()

    monitor.register_event_handler(slow_handler)
    monitor.register_event_handler(controller.handle_agent_health_event)

    # set initial healthy
    await registry.update_agent_status(agent_id, HealthStatus.HEALTHY)

    start = time.monotonic()
    async def fail(agent_id_arg):
        raise Exception("boom")
    monitor.poll_agent_health = fail

    await monitor.poll_agent_health(agent_id)
    elapsed = time.monotonic() - start

    # ensure poll returned quickly (< 0.05s) despite slow handler
    assert elapsed < 0.05

    # ensure slow handler eventually ran
    await asyncio.wait_for(ev.wait(), timeout=1.0)
