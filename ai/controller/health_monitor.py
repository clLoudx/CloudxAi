from typing import Dict, Optional
from pydantic import BaseModel
from enum import Enum
import asyncio
import logging
from ai.controller.signals import (
    AgentDegradedEvent,
    AgentRecoveredEvent,
    now_iso,
)

logger = logging.getLogger("health_monitor")

# Define AgentHealth Enum
class HealthStatus(str, Enum):
    HEALTHY = "healthy"
    DEGRADED = "degraded"
    UNHEALTHY = "unhealthy"

# Define AgentHealth model
class AgentHealth(BaseModel):
    status: HealthStatus
    latency_ms: Optional[int]
    last_heartbeat: Optional[str]
    capabilities: Optional[Dict[str, str]]

# HealthMonitor class
class HealthMonitor:
    def __init__(self, agent_registry):
        self.agent_registry = agent_registry
        self._lock = asyncio.Lock()
        # _poll_impl holds the real polling implementation. Tests may assign
        # to `monitor.poll_agent_health` (at instance level); to allow that
        # while keeping exception-handling wrapper intact we store the
        # assigned callable in _poll_impl via __setattr__ and call it from
        # the public `poll_agent_health` wrapper below.
        self._poll_impl = None
        # event handlers: async callables that accept a single event arg
        self._event_handlers: list = []

    def __setattr__(self, name, value):
        # Intercept assignment to `poll_agent_health` and store provided
        # callable in `_poll_impl` so the wrapper remains callable and can
        # handle exceptions consistently.
        if name == "poll_agent_health":
            object.__setattr__(self, "_poll_impl", value)
        else:
            object.__setattr__(self, name, value)

    async def poll_agent_health(self, agent_id: str):
        """
        Public wrapper that executes the underlying poll implementation and
        ensures registry updates on exceptions. Tests may replace the
        implementation by assigning to `monitor.poll_agent_health` which we
        intercept and store in `_poll_impl`.
        """
        impl = getattr(self, "_poll_impl", None)
        # If no custom impl was provided, use the default implementation.
        if impl is None:
            impl = self._default_poll_impl

        try:
            await impl(agent_id)
        except asyncio.TimeoutError:
            logger.error(f"Health check for agent {agent_id} timed out.")
            async with self._lock:
                # store health monitor's HealthStatus value in registry; the
                # registry is a minimal implementation and accepts any enum
                # value for storage.
                await self._handle_status_transition(agent_id, HealthStatus.DEGRADED, reason="timeout")
        except Exception as e:
            logger.exception(f"Health check for agent {agent_id} failed: {e}")
            async with self._lock:
                await self._handle_status_transition(agent_id, HealthStatus.UNHEALTHY, reason=str(e))

    async def _default_poll_impl(self, agent_id: str):
        """The original polling implementation pulled out into a default
        callable so the wrapper can call it or tests can replace the
        implementation with a mock while still letting the wrapper handle
        status updates on exceptions.
        """
        agent = await self.agent_registry.get_agent(agent_id)
        if not agent:
            logger.warning(f"Agent {agent_id} not found in registry.")
            return

        # Simulate health check (replace with actual agent health call)
        health = AgentHealth(
            status=HealthStatus.HEALTHY,
            latency_ms=50,
            last_heartbeat="2025-12-17T12:00:00Z",
            capabilities=agent.capabilities,
        )

        async with self._lock:
            await self._handle_status_transition(agent_id, health.status)

    def register_event_handler(self, handler):
        """Register an async handler to be called with each emitted event."""
        self._event_handlers.append(handler)

    async def _emit_event(self, event):
        # dispatch to handlers without awaiting to avoid blocking the monitor
        for h in list(self._event_handlers):
            try:
                asyncio.create_task(h(event))
            except Exception:
                logger.exception("Failed to schedule event handler")

    async def _handle_status_transition(self, agent_id: str, new_status, reason: Optional[str] = None):
        # Get previous status and update registry, then emit events only on
        # significant transitions between HEALTHY <-> UNHEALTHY/DEGRADED.
        prev = await self.agent_registry.get_agent_status(agent_id)
        # Normalize to string
        prev_s = getattr(prev, "value", str(prev)) if prev is not None else None
        new_s = getattr(new_status, "value", str(new_status))

        # Update registry with new status
        await self.agent_registry.update_agent_status(agent_id, new_status)

        # Only emit for transitions between HEALTHY and UNHEALTHY/DEGRADED
        interested = {HealthStatus.HEALTHY.value, HealthStatus.DEGRADED.value, HealthStatus.UNHEALTHY.value}
        if prev_s in interested and new_s in interested and prev_s != new_s:
            ts = now_iso()
            if prev_s == HealthStatus.HEALTHY.value and new_s != HealthStatus.HEALTHY.value:
                ev = AgentDegradedEvent(
                    agent_id=agent_id,
                    previous_status=prev_s,
                    current_status=new_s,
                    timestamp=ts,
                    reason=reason,
                )
            elif prev_s != HealthStatus.HEALTHY.value and new_s == HealthStatus.HEALTHY.value:
                ev = AgentRecoveredEvent(
                    agent_id=agent_id,
                    previous_status=prev_s,
                    current_status=new_s,
                    timestamp=ts,
                    reason=reason,
                )
            else:
                return

            await self._emit_event(ev)

    async def monitor_agents(self):
        while True:
            agents = await self.agent_registry.list_agents()
            for agent_id in agents:
                asyncio.create_task(self.poll_agent_health(agent_id))
            await asyncio.sleep(60)