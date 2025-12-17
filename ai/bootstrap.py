import asyncio
from typing import Optional, Tuple
from ai_agent.agent_registry import InMemoryAgentRegistry
from ai.controller.health_monitor import HealthMonitor
from ai.controller.controller import Controller


async def bootstrap_monitor(start_loop: bool = False, registry: Optional[InMemoryAgentRegistry] = None) -> Tuple[HealthMonitor, Controller, Optional[asyncio.Task]]:
    """Create and wire HealthMonitor and Controller.

    If start_loop is True, schedule monitor.monitor_agents() as a background
    task and return it. The caller is responsible for cancelling the task
    during shutdown.
    """
    if registry is None:
        registry = InMemoryAgentRegistry()

    monitor = HealthMonitor(registry)
    controller = Controller()

    # Register controller handler explicitly
    monitor.register_event_handler(controller.handle_agent_health_event)

    task = None
    if start_loop:
        # schedule monitor loop in background
        task = asyncio.create_task(monitor.monitor_agents())

    return monitor, controller, task
