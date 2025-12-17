import logging
from typing import Dict
import asyncio
from ai.controller.signals import AgentHealthEvent, AgentDegradedEvent, AgentRecoveredEvent
from prometheus_client import Counter

logger = logging.getLogger("controller")


class Controller:
    def __init__(self):
        # simple in-memory metric counters
        self.metrics: Dict[str, int] = {"degraded": 0, "recovered": 0}
        self.last_event: AgentHealthEvent | None = None

        # Prometheus counters (module-level metrics mirrored here)
        # Namespaced to avoid collisions
        from prometheus_client import REGISTRY

        try:
            self._prom_degraded = Counter(
                "aicloudxagent_agent_degraded_total", "Total number of degraded agent events"
            )
        except ValueError:
            # metric already registered; reuse existing collector
            self._prom_degraded = REGISTRY._names_to_collectors.get("aicloudxagent_agent_degraded_total")

        try:
            self._prom_recovered = Counter(
                "aicloudxagent_agent_recovered_total", "Total number of recovered agent events"
            )
        except ValueError:
            self._prom_recovered = REGISTRY._names_to_collectors.get("aicloudxagent_agent_recovered_total")

    async def handle_agent_health_event(self, event: AgentHealthEvent) -> None:
        """Default handler: structured logging and in-memory metric increment.

        Keep this handler fast and side-effect free.
        """
        try:
            logger.info("AgentHealthEvent", extra={
                "agent_id": event.agent_id,
                "previous_status": event.previous_status,
                "current_status": event.current_status,
                "timestamp": event.timestamp,
            })

            # increment metrics for degraded/recovered
            if isinstance(event, AgentDegradedEvent):
                self.metrics["degraded"] += 1
                try:
                    self._prom_degraded.inc()
                except Exception:
                    logger.exception("Failed to increment prometheus degraded counter")
            elif isinstance(event, AgentRecoveredEvent):
                self.metrics["recovered"] += 1
                try:
                    self._prom_recovered.inc()
                except Exception:
                    logger.exception("Failed to increment prometheus recovered counter")

            self.last_event = event
        except Exception:
            logger.exception("Controller handler failed")
