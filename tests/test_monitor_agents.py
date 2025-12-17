import pytest
import asyncio
from ai.controller.health_monitor import HealthMonitor, HealthStatus
from ai_agent.agent_registry import InMemoryAgentRegistry, AgentSpec

@pytest.mark.asyncio
async def test_monitor_agents_creates_tasks_for_all_agents():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    # register multiple agents
    agent_ids = ["agent-a", "agent-b", "agent-c"]
    for aid in agent_ids:
        await registry.register_agent(aid, AgentSpec(name="A", version="1.0", capabilities={}))

    called = []
    ev = asyncio.Event()

    async def mock_poll(agent_id):
        called.append(agent_id)
        # when we've seen all agents, set the event
        if set(called) >= set(agent_ids):
            ev.set()

    # replace poll implementation; HealthMonitor intercepts assignment
    monitor.poll_agent_health = mock_poll

    # run monitor in background
    monitor_task = asyncio.create_task(monitor.monitor_agents())

    try:
        await asyncio.wait_for(ev.wait(), timeout=1.0)
    finally:
        monitor_task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await monitor_task

    assert set(called) == set(agent_ids)

@pytest.mark.asyncio
async def test_monitor_agents_handles_poll_exceptions_and_updates_registry():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-x"
    await registry.register_agent(agent_id, AgentSpec(name="X", version="1.0", capabilities={}))

    ev = asyncio.Event()

    async def mock_poll_raise(agent_id_arg):
        # raise exception to trigger wrapper's exception handling
        ev.set()
        raise Exception("boom")

    monitor.poll_agent_health = mock_poll_raise

    monitor_task = asyncio.create_task(monitor.monitor_agents())

    try:
        await asyncio.wait_for(ev.wait(), timeout=1.0)
        # allow small moment for exception handling to update status
        await asyncio.sleep(0.05)
    finally:
        monitor_task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await monitor_task

    status = await registry.get_agent_status(agent_id)
    assert status == HealthStatus.UNHEALTHY

@pytest.mark.asyncio
async def test_monitor_agents_skips_unknown_agent_safely():
    # ensure that if monitor finds no agents or an unknown id, it does not crash
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    # no agents registered
    ev = asyncio.Event()

    async def short_sleep_once(agent_id):
        # simply set event so test can cancel monitor after one loop
        ev.set()

    # assign short impl but there are no agents so it should not be called
    monitor.poll_agent_health = short_sleep_once
    monitor_task = asyncio.create_task(monitor.monitor_agents())

    try:
        # give the monitor a short moment to run one loop and reach sleep
        await asyncio.sleep(0.05)
    finally:
        monitor_task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await monitor_task

    # no exception means success; registry remains empty
    assert (await registry.list_agents()) == []
