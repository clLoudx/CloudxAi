from pydantic import BaseModel
from typing import Optional
from datetime import datetime, timezone


class AgentHealthEvent(BaseModel):
    agent_id: str
    previous_status: Optional[str]
    current_status: str
    timestamp: str
    reason: Optional[str] = None


class AgentDegradedEvent(AgentHealthEvent):
    """Emitted when an agent transitions from HEALTHY -> UNHEALTHY/DEGRADED."""
    pass


class AgentRecoveredEvent(AgentHealthEvent):
    """Emitted when an agent transitions from UNHEALTHY/DEGRADED -> HEALTHY."""
    pass


def now_iso() -> str:
    # timezone-aware UTC ISO timestamp
    return datetime.now(timezone.utc).isoformat()
