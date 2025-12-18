from typing import Protocol, Dict, Optional
from pydantic import BaseModel
from enum import Enum
import asyncio

# Define AgentStatus Enum
class AgentStatus(str, Enum):
    HEALTHY = "healthy"
    UNHEALTHY = "unhealthy"
    UNKNOWN = "unknown"

# Define AgentSpec
class AgentSpec(BaseModel):
    name: str
    version: str
    capabilities: Dict[str, str]

# Define AgentRegistryProtocol
class AgentRegistryProtocol(Protocol):
    async def register_agent(self, agent_id: str, spec: AgentSpec) -> None:
        ...

    async def get_agent(self, agent_id: str) -> Optional[AgentSpec]:
        ...

    async def get_agent_status(self, agent_id: str) -> AgentStatus:
        ...

# Minimal reference implementation
class InMemoryAgentRegistry:
    def __init__(self):
        self._agents: Dict[str, AgentSpec] = {}
        # store status values as-is (may be AgentStatus or HealthStatus)
        self._statuses: Dict[str, object] = {}
        self._lock = asyncio.Lock()

    async def register_agent(self, agent_id: str, spec: AgentSpec) -> None:
        async with self._lock:
            self._agents[agent_id] = spec
            self._statuses[agent_id] = AgentStatus.UNKNOWN

    async def get_agent(self, agent_id: str) -> Optional[AgentSpec]:
        async with self._lock:
            return self._agents.get(agent_id)

    async def get_agent_status(self, agent_id: str) -> AgentStatus:
        async with self._lock:
            return self._statuses.get(agent_id, AgentStatus.UNKNOWN)

    async def update_agent_status(self, agent_id: str, status) -> None:
        async with self._lock:
            # accept and store status values from health monitor (which may
            # be a different Enum type) without strict type checks
            if agent_id in self._statuses:
                self._statuses[agent_id] = status

    async def list_agents(self) -> list[str]:
        async with self._lock:
            return list(self._agents.keys())
