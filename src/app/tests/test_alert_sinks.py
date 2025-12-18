"""
Tests for Alert Sink Interface and Implementations
"""

import pytest
import asyncio
import json
import logging
from unittest.mock import AsyncMock, MagicMock, patch
from datetime import datetime, timezone
from aiohttp import ClientError

from app.security.alerts import (
    AlertEvent,
    AlertDeliveryResult,
    AlertSinkRegistry,
    AlertDispatcher,
    LoggingSink,
    WebhookSink,
)
from app.security.alert_engine import SecurityAlert


class TestAlertEvent:
    """Test AlertEvent canonical payload."""

    def test_from_security_alert(self):
        """Test conversion from SecurityAlert to AlertEvent."""
        alert = SecurityAlert(
            alert_type="test_alert",
            severity="high",
            user_id="user123",
            session_id="session456",
            ip_address="192.168.1.1",
            request_id="req789",
            timestamp=datetime(2025, 12, 15, 10, 30, 0, tzinfo=timezone.utc),
            details={"test": "value"}
        )

        alert_event = AlertEvent.from_security_alert(alert, "test_rule")

        assert alert_event.rule_id == "test_rule"
        assert alert_event.severity == "high"
        assert alert_event.user_id == "user123"
        assert alert_event.session_id == "session456"
        assert alert_event.ip_address == "192.168.1.1"
        assert alert_event.request_id == "req789"
        assert alert_event.details == {"test": "value"}
        assert alert_event.alert_id is not None
        assert len(alert_event.alert_id) > 0


class TestAlertSinkRegistry:
    """Test AlertSinkRegistry functionality."""

    def test_register_and_enable(self):
        """Test registering and enabling sinks."""
        registry = AlertSinkRegistry()

        # Create mock sinks
        sink1 = MagicMock()
        sink1.name = "sink1"
        sink2 = MagicMock()
        sink2.name = "sink2"

        registry.register(sink1)
        registry.register(sink2)

        # Enable only sink1
        registry.enable(["sink1"])

        enabled = registry.get_enabled_sinks()
        assert len(enabled) == 1
        assert enabled[0] == sink1

    def test_enable_nonexistent_sink(self):
        """Test enabling a sink that doesn't exist."""
        registry = AlertSinkRegistry()
        registry.enable(["nonexistent"])
        assert len(registry.get_enabled_sinks()) == 0


class TestAlertDispatcher:
    """Test AlertDispatcher fan-out behavior."""

    @pytest.fixture
    def registry(self):
        """Create a registry with mock sinks."""
        registry = AlertSinkRegistry()

        sink1 = AsyncMock()
        sink1.name = "sink1"
        sink1.send.return_value = AlertDeliveryResult(
            sink_name="sink1",
            success=True,
            delivery_time_ms=10
        )

        sink2 = AsyncMock()
        sink2.name = "sink2"
        sink2.send.return_value = AlertDeliveryResult(
            sink_name="sink2",
            success=False,
            error_message="Test failure"
        )

        registry.register(sink1)
        registry.register(sink2)
        registry.enable(["sink1", "sink2"])

        return registry

    @pytest.fixture
    def dispatcher(self, registry):
        """Create dispatcher with test registry."""
        return AlertDispatcher(registry)

    @pytest.fixture
    def test_alert(self):
        """Create a test SecurityAlert."""
        return SecurityAlert(
            alert_type="test_alert",
            severity="high",
            user_id="user123",
            session_id="session456",
            ip_address="192.168.1.1",
            request_id="req789",
            timestamp=datetime.now(timezone.utc),
            details={"test": "value"}
        )

    @pytest.mark.asyncio
    async def test_successful_dispatch(self, dispatcher, test_alert):
        """Test successful dispatch to all enabled sinks."""
        results = await dispatcher.dispatch(test_alert, "test_rule")

        assert len(results) == 2
        assert all(result.success for result in results[:1])  # First sink succeeds
        assert not all(result.success for result in results[1:])  # Second sink fails

    @pytest.mark.asyncio
    async def test_sink_exception_handling(self, dispatcher, test_alert, registry):
        """Test that sink exceptions are handled gracefully."""
        # Make one sink raise an exception
        sinks = registry.get_enabled_sinks()
        sinks[0].send.side_effect = Exception("Test exception")

        results = await dispatcher.dispatch(test_alert, "test_rule")

        assert len(results) == 2
        # First result should be failure due to exception
        assert not results[0].success
        assert "Unexpected sink error" in results[0].error_message

    @pytest.mark.asyncio
    async def test_no_enabled_sinks(self, test_alert):
        """Test dispatch with no enabled sinks."""
        registry = AlertSinkRegistry()
        dispatcher = AlertDispatcher(registry)

        results = await dispatcher.dispatch(test_alert, "test_rule")
        assert len(results) == 0


class TestLoggingSink:
    """Test LoggingSink implementation."""

    @pytest.fixture
    def sink(self):
        """Create LoggingSink with captured logger."""
        logger = logging.getLogger("test_alerts")
        logger.setLevel(logging.DEBUG)
        return LoggingSink(logger)

    @pytest.fixture
    def test_alert_event(self):
        """Create a test AlertEvent."""
        return AlertEvent(
            alert_id="test-123",
            rule_id="test_rule",
            severity="high",
            timestamp=datetime(2025, 12, 15, 10, 30, 0, tzinfo=timezone.utc),
            user_id="user123",
            session_id="session456",
            ip_address="192.168.1.1",
            request_id="req789",
            details={"test": "value"}
        )

    @pytest.mark.asyncio
    async def test_successful_logging(self, sink, test_alert_event):
        """Test successful alert logging."""
        with patch.object(sink.logger, 'log') as mock_log:
            result = await sink.send(test_alert_event)

            assert result.success
            assert result.sink_name == "log"
            assert result.delivery_time_ms is not None

            # Verify log was called with structured JSON
            mock_log.assert_called_once()
            call_args = mock_log.call_args
            logged_message = call_args[0][1]  # Second argument is the message

            # Parse the JSON from the log message
            json_start = logged_message.find('{')
            json_content = logged_message[json_start:]
            logged_data = json.loads(json_content)

            assert logged_data["alert_id"] == "test-123"
            assert logged_data["rule_id"] == "test_rule"
            assert logged_data["severity"] == "high"

    @pytest.mark.asyncio
    async def test_logging_failure_handling(self, sink, test_alert_event):
        """Test graceful handling of logging failures."""
        with patch.object(sink.logger, 'log', side_effect=Exception("Log failure")):
            result = await sink.send(test_alert_event)

            assert not result.success
            assert result.sink_name == "log"
            assert "Logging failed" in result.error_message


class TestWebhookSink:
    """Test WebhookSink implementation."""

    @pytest.fixture
    def test_alert_event(self):
        """Create a test AlertEvent."""
        return AlertEvent(
            alert_id="test-123",
            rule_id="test_rule",
            severity="high",
            timestamp=datetime(2025, 12, 15, 10, 30, 0, tzinfo=timezone.utc),
            user_id="user123",
            session_id="session456",
            ip_address="192.168.1.1",
            request_id="req789",
            details={"test": "value"}
        )

    def test_invalid_url(self):
        """Test that invalid URLs raise ValueError."""
        with pytest.raises(ValueError, match="Invalid webhook URL"):
            WebhookSink("not-a-url")

    @pytest.mark.asyncio
    async def test_successful_webhook_delivery(self, test_alert_event):
        """Test successful webhook delivery."""
        # Mock successful HTTP response
        mock_response = AsyncMock()
        mock_response.status = 200
        mock_response.text = AsyncMock(return_value="OK")

        # Create a proper async context manager class for response
        class MockResponseContext:
            def __init__(self, response):
                self.response = response

            async def __aenter__(self):
                return self.response

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        # Mock the session
        mock_session = MagicMock()
        mock_session.post = MagicMock(return_value=MockResponseContext(mock_response))

        # Create a proper async context manager class for session
        class MockSessionContext:
            def __init__(self, session):
                self.session = session

            async def __aenter__(self):
                return self.session

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        with patch('app.security.alert_sinks.aiohttp.ClientSession', return_value=MockSessionContext(mock_session)):

            sink = WebhookSink("https://example.com/webhook")
            result = await sink.send(test_alert_event)

            assert result.success
            assert result.sink_name == "webhook"
            assert result.delivery_time_ms is not None

            # Verify the POST was made with correct payload
            mock_session.post.assert_called_once()
            call_args = mock_session.post.call_args
            posted_data = call_args[1]['data']
            posted_payload = json.loads(posted_data)

            assert posted_payload["alert_id"] == "test-123"
            assert posted_payload["rule_id"] == "test_rule"

    @pytest.mark.asyncio
    async def test_webhook_http_error(self, test_alert_event):
        """Test webhook delivery with HTTP error response."""
        # Mock HTTP error response
        mock_response = AsyncMock()
        mock_response.status = 500
        mock_response.text = AsyncMock(return_value="Internal Server Error")

        # Create a proper async context manager class for response
        class MockResponseContext:
            def __init__(self, response):
                self.response = response

            async def __aenter__(self):
                return self.response

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        # Mock the session
        mock_session = MagicMock()
        mock_session.post = MagicMock(return_value=MockResponseContext(mock_response))

        # Create a proper async context manager class for session
        class MockSessionContext:
            def __init__(self, session):
                self.session = session

            async def __aenter__(self):
                return self.session

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        with patch('app.security.alert_sinks.aiohttp.ClientSession', return_value=MockSessionContext(mock_session)):

            sink = WebhookSink("https://example.com/webhook")
            result = await sink.send(test_alert_event)

            assert not result.success
            assert result.sink_name == "webhook"
            assert "HTTP 500" in result.error_message
            assert "HTTP 500" in result.error_message

    @pytest.mark.asyncio
    async def test_webhook_timeout_with_retry(self, test_alert_event):
        """Test webhook timeout with retry logic."""
        # Create a proper async context manager class for response that raises TimeoutError
        class MockResponseContext:
            async def __aenter__(self):
                raise asyncio.TimeoutError()

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        # Mock the session
        mock_session = MagicMock()
        mock_session.post = MagicMock(return_value=MockResponseContext())

        # Create a proper async context manager class for session
        class MockSessionContext:
            def __init__(self, session):
                self.session = session

            async def __aenter__(self):
                return self.session

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        with patch('app.security.alert_sinks.aiohttp.ClientSession', return_value=MockSessionContext(mock_session)):

            sink = WebhookSink("https://example.com/webhook", max_retries=2)
            result = await sink.send(test_alert_event)

            assert not result.success
            assert result.sink_name == "webhook"
            assert "Failed after 2 attempts" in result.error_message

            # Should have been called 2 times (max_retries)
            assert mock_session.post.call_count == 2

    @pytest.mark.asyncio
    async def test_webhook_network_error(self, test_alert_event):
        """Test webhook delivery with network error."""
        # Create a proper async context manager class for response that raises ClientError
        class MockResponseContext:
            async def __aenter__(self):
                raise ClientError("Network error")

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        # Mock the session
        mock_session = MagicMock()
        mock_session.post = MagicMock(return_value=MockResponseContext())

        # Create a proper async context manager class for session
        class MockSessionContext:
            def __init__(self, session):
                self.session = session

            async def __aenter__(self):
                return self.session

            async def __aexit__(self, exc_type, exc_val, exc_tb):
                pass

        with patch('app.security.alert_sinks.aiohttp.ClientSession', return_value=MockSessionContext(mock_session)):

            sink = WebhookSink("https://example.com/webhook")
            result = await sink.send(test_alert_event)

            assert not result.success
            assert result.sink_name == "webhook"
            assert "HTTP client error" in result.error_message