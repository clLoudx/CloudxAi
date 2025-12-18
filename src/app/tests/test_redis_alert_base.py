"""
Tests for Redis-backed alert rule base class.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock
import redis.asyncio as redis

from app.security.alerts.redis_base import RedisAlertRule


class MockRedisRule(RedisAlertRule):
    """Mock rule for testing RedisAlertRule base functionality."""

    name = "test_rule"

    def evaluate(self, event):
        return None


class TestRedisAlertRule:
    """Test RedisAlertRule base class functionality."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return MockRedisRule(mock_redis)

    def test_key_normalization(self, rule):
        """Test that keys are properly normalized."""
        key = rule.key("dimension", "value")
        assert key == "alerts:v1:test_rule:dimension:value"

    def test_key_normalization_custom_namespace(self, mock_redis):
        """Test key normalization with custom namespace."""
        rule = MockRedisRule(mock_redis, namespace="custom:v2")
        key = rule.key("test", "key")
        assert key == "custom:v2:test_rule:test:key"

    @pytest.mark.asyncio
    async def test_increment_counter_first_time(self, rule, mock_redis):
        """Test incrementing counter for the first time."""
        # Mock pipeline behavior
        mock_redis.pipeline.return_value.__aenter__.return_value.execute.return_value = [1, -2]
        mock_redis.expire = AsyncMock()

        count = await rule.increment_counter("test:key", 300)

        assert count == 1
        mock_redis.expire.assert_called_once_with("test:key", 300)

    @pytest.mark.asyncio
    async def test_increment_counter_existing(self, rule, mock_redis):
        """Test incrementing existing counter."""
        # Mock pipeline behavior for existing key
        mock_redis.pipeline.return_value.__aenter__.return_value.execute.return_value = [5, 250]
        mock_redis.expire = AsyncMock()

        count = await rule.increment_counter("test:key", 300)

        assert count == 5
        mock_redis.expire.assert_not_called()

    @pytest.mark.asyncio
    async def test_increment_counter_redis_failure(self, rule, mock_redis):
        """Test that Redis failures return 0 (fail closed)."""
        mock_redis.pipeline.side_effect = Exception("Redis error")

        count = await rule.increment_counter("test:key", 300)

        assert count == 0

    @pytest.mark.asyncio
    async def test_check_threshold_below_threshold(self, rule, mock_redis):
        """Test threshold check when below threshold."""
        # Mock increment_counter to return 3 (below threshold of 5)
        rule.increment_counter = AsyncMock(return_value=3)
        mock_redis.exists = AsyncMock(return_value=False)

        result = await rule.check_threshold("test:key", 5, 300)

        assert result is False

    @pytest.mark.asyncio
    async def test_check_threshold_first_alert(self, rule, mock_redis):
        """Test threshold check when crossing threshold for first time."""
        # Mock increment_counter to return 5 (at threshold)
        rule.increment_counter = AsyncMock(return_value=5)
        mock_redis.exists = AsyncMock(return_value=False)
        mock_redis.setex = AsyncMock()

        result = await rule.check_threshold("test:key", 5, 300)

        assert result is True
        mock_redis.setex.assert_called_once_with("test:key:alerted", 300, "1")

    @pytest.mark.asyncio
    async def test_check_threshold_already_alerted(self, rule, mock_redis):
        """Test threshold check when already alerted in this window."""
        # Mock increment_counter to return 7 (above threshold)
        rule.increment_counter = AsyncMock(return_value=7)
        mock_redis.exists = AsyncMock(return_value=True)

        result = await rule.check_threshold("test:key", 5, 300)

        assert result is False

    @pytest.mark.asyncio
    async def test_check_threshold_redis_failure(self, rule, mock_redis):
        """Test that Redis failures in threshold check return False."""
        rule.increment_counter = AsyncMock(side_effect=Exception("Redis error"))

        result = await rule.check_threshold("test:key", 5, 300)

        assert result is False

    @pytest.mark.asyncio
    async def test_mark_once_first_time(self, rule, mock_redis):
        """Test marking an event for the first time."""
        mock_redis.set = AsyncMock(return_value=True)  # SET NX succeeded

        result = await rule.mark_once("test:key", 300)

        assert result is True
        mock_redis.set.assert_called_once_with("test:key", "1", ex=300, nx=True)

    @pytest.mark.asyncio
    async def test_mark_once_already_marked(self, rule, mock_redis):
        """Test marking an event that was already marked."""
        mock_redis.set = AsyncMock(return_value=None)  # SET NX failed

        result = await rule.mark_once("test:key", 300)

        assert result is False

    @pytest.mark.asyncio
    async def test_mark_once_redis_failure(self, rule, mock_redis):
        """Test that Redis failures in mark_once return False."""
        mock_redis.set = AsyncMock(side_effect=Exception("Redis error"))

        result = await rule.mark_once("test:key", 300)

        assert result is False

    @pytest.mark.asyncio
    async def test_get_counter_value_existing(self, rule, mock_redis):
        """Test getting existing counter value."""
        mock_redis.get = AsyncMock(return_value=b"42")

        value = await rule.get_counter_value("test:key")

        assert value == 42

    @pytest.mark.asyncio
    async def test_get_counter_value_nonexistent(self, rule, mock_redis):
        """Test getting value for nonexistent counter."""
        mock_redis.get = AsyncMock(return_value=None)

        value = await rule.get_counter_value("test:key")

        assert value == 0

    @pytest.mark.asyncio
    async def test_get_counter_value_redis_failure(self, rule, mock_redis):
        """Test that Redis failures in get_counter_value return 0."""
        mock_redis.get = AsyncMock(side_effect=Exception("Redis error"))

        value = await rule.get_counter_value("test:key")

        assert value == 0