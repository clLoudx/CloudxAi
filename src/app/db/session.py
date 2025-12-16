"""
Database base configuration and session management.
Uses SQLAlchemy async with PostgreSQL.
"""

from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import AsyncAdaptedQueuePool

from ..core.config import get_settings

# Create async engine
engine = create_async_engine(
    get_settings().database_url,
    poolclass=AsyncAdaptedQueuePool,
    pool_size=get_settings().db_pool_size,
    max_overflow=get_settings().db_max_overflow,
    pool_recycle=get_settings().db_pool_recycle,
    echo=get_settings().debug,  # SQL logging in debug mode
    future=True,
)

# Create async session factory
async_session_factory = sessionmaker(
    bind=engine,
    class_=AsyncSession,
    expire_on_commit=False,
)

# Base class for all models
Base = declarative_base()


async def get_db() -> AsyncSession:
    """
    Dependency for FastAPI to get database session.

    Yields:
        AsyncSession: Database session
    """
    async with async_session_factory() as session:
        try:
            yield session
        finally:
            await session.close()


async def create_tables() -> None:
    """
    Create all database tables.
    Called during application startup.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)


async def drop_tables() -> None:
    """
    Drop all database tables.
    Use with caution - only for testing/migrations.
    """
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)