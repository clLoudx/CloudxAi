from fastapi import FastAPI
from ai.bootstrap import bootstrap_monitor
import asyncio
from contextlib import asynccontextmanager
from starlette.responses import Response
from prometheus_client import generate_latest, CONTENT_TYPE_LATEST


@asynccontextmanager
async def lifespan(app: FastAPI):
    # bootstrap monitor and start background loop
    monitor, controller, task = await bootstrap_monitor(start_loop=True)
    app.state.monitor = monitor
    app.state.controller = controller
    app.state.monitor_task = task
    try:
        yield
    finally:
        task = getattr(app.state, "monitor_task", None)
        if task is not None:
            task.cancel()
            try:
                await task
            except asyncio.CancelledError:
                pass


app = FastAPI(lifespan=lifespan)


@app.get("/")
async def root():
    return {"status": "ok"}


@app.get("/metrics")
async def metrics():
    # Return Prometheus exposition format
    data = generate_latest()
    return Response(content=data, media_type=CONTENT_TYPE_LATEST)
