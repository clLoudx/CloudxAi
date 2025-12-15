"""
Main FastAPI application entry point.
Configures the application with all core components.
"""

import asyncio
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse

from .api.v1.routers.health import router as health_router
from .api.v1.routers.auth import router as auth_router
from .core.config import get_settings
from .core.logging import CorrelationIdMiddleware, get_logger, setup_logging
from .core.redis_client import redis_client
from .db.session import create_tables

# Setup logging before anything else
setup_logging()
logger = get_logger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """
    Application lifespan context manager.
    Handles startup and shutdown events.
    """
    logger.info("Starting AI-Cloudx Agent", version=get_settings().app_version)

    # Startup: Create database tables
    try:
        await create_tables()
        logger.info("Database tables created successfully")
    except Exception as e:
        logger.error("Failed to create database tables", error=str(e))
        raise

    yield

    # Shutdown: Cleanup resources
    logger.info("Shutting down AI-Cloudx Agent")
    await redis_client.close()


# Create FastAPI application
app = FastAPI(
    title=get_settings().app_name,
    version=get_settings().app_version,
    description="Enterprise-grade AI-powered development platform",
    lifespan=lifespan,
    docs_url="/docs" if get_settings().debug else None,  # Disable docs in production
    redoc_url="/redoc" if get_settings().debug else None,
    openapi_url="/openapi.json" if get_settings().debug else None,
)

# Security middleware
if get_settings().environment != "testing":
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=get_settings().allowed_hosts)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=get_settings().cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Correlation ID middleware
app.add_middleware(CorrelationIdMiddleware)

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    """
    Global exception handler for unhandled errors.
    Logs errors and returns appropriate response.
    """
    logger.error(
        "Unhandled exception",
        error=str(exc),
        path=request.url.path,
        method=request.method,
        exc_info=True,
    )

    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error", "correlation_id": getattr(request.state, "correlation_id", None)},
    )


# Include routers
app.include_router(
    health_router,
    prefix="/api/v1",
    tags=["Health"],
)
app.include_router(
    auth_router,
    prefix="/api/v1/auth",
    tags=["Authentication"],
)


@app.get("/", summary="Root Endpoint", description="Basic root endpoint")
async def root():
    """
    Root endpoint returning application info.
    """
    return {
        "message": f"Welcome to {get_settings().app_name}",
        "version": get_settings().app_version,
        "environment": get_settings().environment,
    }


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "main:app",
        host=get_settings().host,
        port=get_settings().port,
        reload=get_settings().reload,
        workers=get_settings().workers,
        log_level=get_settings().log_level.lower(),
    )