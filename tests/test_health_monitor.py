import pytest
from ai.controller.health_monitor import HealthMonitor, AgentHealth, HealthStatus
from ai_agent.agent_registry import InMemoryAgentRegistry, AgentSpec
import asyncio

@pytest.mark.asyncio
async def test_health_success():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-1"
    spec = AgentSpec(name="TestAgent", version="1.0", capabilities={"key": "value"})
    await registry.register_agent(agent_id, spec)

    await monitor.poll_agent_health(agent_id)
    status = await registry.get_agent_status(agent_id)

    assert status == HealthStatus.HEALTHY

@pytest.mark.asyncio
async def test_health_timeout():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-2"
    spec = AgentSpec(name="TimeoutAgent", version="1.0", capabilities={})
    await registry.register_agent(agent_id, spec)

    async def mock_poll_agent_health(*args, **kwargs):
        raise asyncio.TimeoutError()

    monitor.poll_agent_health = mock_poll_agent_health

    await monitor.poll_agent_health(agent_id)
    status = await registry.get_agent_status(agent_id)

    assert status == HealthStatus.DEGRADED

@pytest.mark.asyncio
async def test_health_exception():
    registry = InMemoryAgentRegistry()
    monitor = HealthMonitor(registry)

    agent_id = "agent-3"
    spec = AgentSpec(name="ErrorAgent", version="1.0", capabilities={})
    await registry.register_agent(agent_id, spec)

    async def mock_poll_agent_health(*args, **kwargs):
        raise Exception("Simulated failure")

    monitor.poll_agent_health = mock_poll_agent_health

    await monitor.poll_agent_health(agent_id)
    status = await registry.get_agent_status(agent_id)

    assert status == HealthStatus.UNHEALTHY