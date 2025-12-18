import pytest
import asyncio
from ai.bootstrap import bootstrap_monitor

@pytest.mark.asyncio
async def test_bootstrap_registers_handler_only():
    monitor, controller, task = await bootstrap_monitor(start_loop=False)
    assert task is None
    # controller handler should be registered
    assert any(h == controller.handle_agent_health_event for h in monitor._event_handlers)

@pytest.mark.asyncio
async def test_bootstrap_starts_loop_and_registers_handler():
    monitor, controller, task = await bootstrap_monitor(start_loop=True)
    assert task is not None
    # task should be running (not done)
    assert not task.done()
    # handler registered
    assert any(h == controller.handle_agent_health_event for h in monitor._event_handlers)

    # cleanup
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
