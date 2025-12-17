from ai.controller.fastapi_app import app
import asyncio


async def _run_lifespan_and_check():
    # use the app's lifespan context to trigger startup/shutdown
    async with app.router.lifespan_context(app):
        task = getattr(app.state, "monitor_task", None)
        assert task is not None
        assert not task.done()

    # after exiting the lifespan, the background task should be done
    task = getattr(app.state, "monitor_task", None)
    assert task is not None
    assert task.done()


def test_fastapi_bootstrap_starts_and_stops_monitor():
    asyncio.run(_run_lifespan_and_check())
