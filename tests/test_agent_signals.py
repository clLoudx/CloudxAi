import pytest
import asyncio
from ai.controller.health_monitor import HealthMonitor, HealthStatus
from ai_agent.agent_registry import InMemoryAgentRegistry, AgentSpec
from ai.controller.signals import AgentDegradedEvent, AgentRecoveredEvent

@pytest.mark.asyncio
async def test_emit_degraded_event_on_exception():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-deg"
    await registry.register_agent(agent_id, AgentSpec(name="D", version="1.0", capabilities={}))

    # set initial status to HEALTHY
    await registry.update_agent_status(agent_id, HealthStatus.HEALTHY)

    events = []
    ev = asyncio.Event()

    async def handler(event):
        events.append(event)
        ev.set()

    monitor.register_event_handler(handler)

    async def mock_fail(agent_id_arg):
        raise Exception("boom")

    monitor.poll_agent_health = mock_fail

    await monitor.poll_agent_health(agent_id)

    await asyncio.wait_for(ev.wait(), timeout=1.0)

    assert len(events) == 1
    assert isinstance(events[0], AgentDegradedEvent)
    assert events[0].agent_id == agent_id
    assert events[0].previous_status == HealthStatus.HEALTHY.value
    assert events[0].current_status != HealthStatus.HEALTHY.value

@pytest.mark.asyncio
async def test_emit_recovered_event_on_repair():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-rec"
    await registry.register_agent(agent_id, AgentSpec(name="R", version="1.0", capabilities={}))

    # set initial status to UNHEALTHY
    await registry.update_agent_status(agent_id, HealthStatus.UNHEALTHY)

    events = []
    ev = asyncio.Event()

    async def handler(event):
        events.append(event)
        ev.set()

    monitor.register_event_handler(handler)

    # call default poll which will set HEALTHY
    await monitor.poll_agent_health(agent_id)

    await asyncio.wait_for(ev.wait(), timeout=1.0)

    assert len(events) == 1
    assert isinstance(events[0], AgentRecoveredEvent)
    assert events[0].agent_id == agent_id
    assert events[0].previous_status == HealthStatus.UNHEALTHY.value
    assert events[0].current_status == HealthStatus.HEALTHY.value

@pytest.mark.asyncio
async def test_no_event_on_unknown_to_healthy():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-new"
    await registry.register_agent(agent_id, AgentSpec(name="N", version="1.0", capabilities={}))

    events = []

    async def handler(event):
        events.append(event)

    monitor.register_event_handler(handler)

    # previous is UNKNOWN by default; default poll will set HEALTHY, but we
    # do not emit for UNKNOWN->HEALTHY transitions
    await monitor.poll_agent_health(agent_id)

    # give small time for any event (there should be none)
    await asyncio.sleep(0.05)

    assert len(events) == 0
