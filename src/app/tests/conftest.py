"""
Pytest configuration and fixtures.
"""

import asyncio
import os
from typing import AsyncGenerator
from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker

# Set test environment variables before importing Settings
os.environ.setdefault("DATABASE_URL", "sqlite+aiosqlite:///:memory:")
os.environ.setdefault("JWT_SECRET_KEY", "test_secret_key")
os.environ.setdefault("SECRET_KEY", "test_secret")
os.environ.setdefault("OPENAI_API_KEY", "test_openai_key")
os.environ.setdefault("ENVIRONMENT", "testing")

from ..core.config import Settings
from ..db.session import Base, get_db
from ..main import app


# Test settings override
test_settings = Settings(
    # Use an in-memory SQLite database for fast, hermetic tests
    database_url="sqlite+aiosqlite:///:memory:",
    redis_url="redis://localhost:6379/0",
    jwt_secret_key="test_secret_key",
    jwt_issuer="ai-cloudx-auth",
    jwt_audience="ai-cloudx-api",
    secret_key="test_secret",
    environment="testing",
    debug=True,
    allowed_hosts=["localhost", "127.0.0.1", "testserver"],
    cors_origins=["http://localhost:3000", "http://localhost:8000", "http://testserver"],
)


@pytest.fixture(scope="session")
def event_loop():
    """Create an instance of the default event loop for the test session."""
    loop = asyncio.get_event_loop_policy().new_event_loop()
    yield loop
    loop.close()


@pytest.fixture
async def test_db_session():
    """Create test database session."""
    engine = create_async_engine(
        test_settings.database_url,
        echo=False,
        future=True,
    )

    # Create tables
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    async_session = sessionmaker(
        bind=engine,
        class_=AsyncSession,
        expire_on_commit=False,
    )

    async with async_session() as session:
        yield session

    # Drop tables and dispose
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)
    await engine.dispose()


@pytest.fixture
def client(test_db_session) -> TestClient:
    """Create FastAPI test client with database session override."""

    def override_get_db():
        return test_db_session

    # Mock Redis client
    mock_redis = AsyncMock()
    mock_redis.ping = AsyncMock(return_value=True)

    def override_get_redis():
        return mock_redis

    app.dependency_overrides[get_db] = override_get_db
    from ..core.redis_client import get_redis as redis_dep
    app.dependency_overrides[redis_dep] = override_get_redis

    # Mock get_settings to return test settings
    from ..core import config
    original_get_settings = config.get_settings
    config.get_settings = lambda: test_settings

    client = TestClient(app)

    # Restore original function
    config.get_settings = original_get_settings

    return client


@pytest.fixture
def test_settings_fixture():
    """Provide test settings."""
    return test_settings