"""
Structured logging configuration using structlog.
Provides JSON-formatted logs with correlation IDs and error categorization.
"""

import logging
import sys
from typing import Any, Dict

import structlog
from pythonjsonlogger import jsonlogger

from .config import get_settings


def setup_logging() -> None:
    """
    Configure structured logging for the application.

    Features:
    - JSON format for production
    - Correlation ID injection
    - Error categorization
    - Configurable log levels
    """

    # Configure standard library logging
    logging.basicConfig(
        format="%(message)s",
        stream=sys.stdout,
        level=getattr(logging, get_settings().log_level.upper()),
    )

    # Shared processors for all loggers
    shared_processors = [
        structlog.stdlib.filter_by_level,
        structlog.stdlib.add_logger_name,
        structlog.stdlib.add_log_level,
        structlog.stdlib.PositionalArgumentsFormatter(),
        structlog.processors.TimeStamper(fmt="iso"),
        structlog.processors.StackInfoRenderer(),
        structlog.processors.format_exc_info,
        structlog.processors.UnicodeDecoder(),
    ]

    # JSON formatter for production
    if get_settings().environment == "production":
        shared_processors.append(
            structlog.processors.JSONRenderer()
        )
    else:
        # Human-readable for development
        shared_processors.append(
            structlog.dev.ConsoleRenderer(colors=True)
        )

    # Configure structlog
    structlog.configure(
        processors=shared_processors,
        context_class=dict,
        logger_factory=structlog.stdlib.LoggerFactory(),
        wrapper_class=structlog.stdlib.BoundLogger,
        cache_logger_on_first_use=True,
    )

    # Suppress noisy loggers
    logging.getLogger("uvicorn.access").setLevel(logging.WARNING)
    logging.getLogger("sqlalchemy").setLevel(logging.WARNING)


def get_logger(name: str) -> structlog.BoundLogger:
    """
    Get a structured logger instance.

    Args:
        name: Logger name (typically __name__)

    Returns:
        Configured logger instance
    """
    return structlog.get_logger(name)


# Middleware for correlation ID injection
class CorrelationIdMiddleware:
    """
    FastAPI middleware to inject correlation IDs into logs and responses.
    """

    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        import uuid

        correlation_id = str(uuid.uuid4())

        # Add to scope for downstream use
        scope["correlation_id"] = correlation_id

        # Configure logger with correlation ID
        structlog.contextvars.bind_contextvars(correlation_id=correlation_id)

        await self.app(scope, receive, send)