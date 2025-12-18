"""
Redis client for distributed caching and task queues.
"""

import redis.asyncio as redis

from .config import get_settings


class RedisClient:
    """
    Async Redis client with connection pooling.
    """

    def __init__(self):
        self._client: redis.Redis = None

    async def get_client(self) -> redis.Redis:
        """
        Get or create Redis client instance.

        Returns:
            Redis client
        """
        if self._client is None:
            settings = get_settings()
            self._client = redis.from_url(
                settings.redis_url,
                max_connections=settings.redis_pool_size,
                decode_responses=True,
            )
        return self._client

    async def close(self):
        """
        Close Redis connection.
        """
        if self._client:
            await self._client.close()
            self._client = None


# Global Redis client instance
redis_client = RedisClient()


async def get_redis() -> redis.Redis:
    """
    Dependency for FastAPI to get Redis client.

    Yields:
        Redis client
    """
    client = await redis_client.get_client()
    try:
        yield client
    finally:
        pass  # Keep connection open