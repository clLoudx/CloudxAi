"""
Health check endpoints for monitoring and load balancing.
Provides liveness and readiness probes.
"""

from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession

from ....db.session import get_db
from ....core.redis_client import get_redis
from ....core.logging import get_logger

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
async def readiness_check(db: AsyncSession = Depends(get_db), redis_client = Depends(get_redis)):
    """
    Readiness probe - checks if the application is ready to serve traffic.
    Includes database and Redis connectivity checks.

    Args:
        db: Database session dependency
        redis_client: Redis client dependency

    Returns:
        dict: Readiness status
    """
    # Handle case where db is an async generator (for testing)
    if hasattr(db, '__aiter__'):
        async for session in db:
            db = session
            break

    try:
        # Simple database query to check connectivity
        await db.execute("SELECT 1")
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