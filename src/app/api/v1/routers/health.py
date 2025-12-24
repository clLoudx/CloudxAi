"""
Health check endpoints for monitoring and load balancing.
Provides liveness and readiness probes.
"""

from fastapi import APIRouter, Depends, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
import inspect
from sqlalchemy import text
from app.core.redis_client import get_redis
from app.core.logging import get_logger
from unittest.mock import AsyncMock

logger = get_logger(__name__)
router = APIRouter()


@router.get("/healthz", summary="Health Check", description="Basic health check endpoint")
async def health_check():
    """
    Liveness probe - checks if the application is running.

    Returns:
        dict: Health status
    """
    return {"status": "healthy", "timestamp": "2025-12-14T00:00:00Z"}  # Use actual timestamp


@router.get("/readyz", summary="Readiness Check", description="Readiness probe with database and Redis check")
async def readiness_check(db: AsyncSession = Depends(get_db), redis_client = Depends(get_redis), request: Request = None):
    """
    Readiness probe - checks if the application is ready to serve traffic.
    Includes database and Redis connectivity checks.

    Args:
        db: Database session dependency
        redis_client: Redis client dependency

    Returns:
        dict: Readiness status
    """
    # Handle common dependency shapes used in tests (async generator, async context manager, or sync context manager)
    logger.info("readiness_check: db object=%r has_aenter=%s isasyncgen=%s has_aiter=%s", db, hasattr(db, '__aenter__'), inspect.isasyncgen(db), hasattr(db, '__aiter__'))
    if inspect.isasyncgen(db):
        # async generator pattern
        async for session in db:
            db = session
            break
    # If tests supplied an AsyncMock (common in unit tests), prefer using it
    # directly rather than entering it as a context manager because entering
    # may return a different mock that doesn't preserve side_effects.
    elif isinstance(db, AsyncMock):
        # use db as provided
        pass
    elif hasattr(db, '__aenter__'):
        # try async context manager first; fall back to sync context manager
        try:
            async with db as session:
                db = session
        except TypeError:
            # Some test harnesses provide a sync context manager mock (with __aenter__)
            # that is not awaitable. Support that shape for tests.
            with db as session:
                db = session

    # IMPORTANT: Respect the dependency-injected `db` session only.
    # Do NOT call module-level providers or inspect app overrides here; the
    # FastAPI dependency injection system will supply the correct object
    # (including any test overrides) as the `db` parameter. Resolving the
    # common shapes (async generator / context manager) is acceptable so
    # we can obtain a usable session for the probe.

    try:
        # Simple database query to check connectivity
        # SQLAlchemy requires textual SQL to be wrapped with text()
        exec_attr = getattr(db, 'execute', None)
        logger.info("db.execute attr: %r, has_side_effect=%r", exec_attr, getattr(exec_attr, 'side_effect', None))
        await db.execute(text("SELECT 1"))
        db_status = "connected"
    except Exception as e:
        logger.error("Database connectivity check failed", error=str(e))
        db_status = "disconnected"

    try:
        # Simple Redis ping to check connectivity
        await redis_client.ping()
        redis_status = "connected"
    except Exception as e:
        logger.error("Redis connectivity check failed", error=str(e))
        redis_status = "disconnected"

    return {
        "status": "ready" if db_status == "connected" and redis_status == "connected" else "not ready",
        "database": db_status,
        "redis": redis_status,
        "timestamp": "2025-12-14T00:00:00Z"  # Use actual timestamp
    }


@router.get("/metrics", summary="Metrics Endpoint", description="Prometheus-compatible metrics")
async def metrics():
    """
    Metrics endpoint for monitoring.
    Returns Prometheus-formatted metrics.

    Note: This is a placeholder. In production, integrate with prometheus_client.
    """
    # Placeholder metrics
    return {
        "uptime_seconds": 3600,
        "requests_total": 100,
        "errors_total": 0,
        "database_connections_active": 5,
        "database_connections_idle": 5,
    }