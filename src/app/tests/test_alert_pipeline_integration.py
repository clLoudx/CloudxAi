"""
Integration Tests for Alert Pipeline

Tests the complete flow: AlertEngine -> Dispatcher -> Sinks
"""

import pytest
import asyncio
import logging
from unittest.mock import AsyncMock, patch
from datetime import datetime, timezone

from app.security.alerts import (
    AlertEngine,
    AlertRegistry,
    AlertSinkRegistry,
    AlertDispatcher,
    LoggingSink,
    WebhookSink,
    TIER2_RULES,
)
from app.security.alert_engine import AuditEvent


class TestAlertPipelineIntegration:
    """Integration tests for the complete alert pipeline."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock()

    @pytest.fixture
    def alert_engine(self, mock_redis):
        """Create AlertEngine with Tier-2 rules and dispatcher."""
        registry = AlertRegistry()

        # Initialize rules with mock Redis
        for rule_class in TIER2_RULES:
            rule = rule_class(mock_redis)
            registry.register(rule)

        # Create sink registry and dispatcher
        sink_registry = AlertSinkRegistry()
        logging_sink = LoggingSink()
        sink_registry.register(logging_sink)
        sink_registry.enable(["log"])

        dispatcher = AlertDispatcher(sink_registry)

        return AlertEngine(registry.build_engine()._rules, dispatcher)

    @pytest.mark.asyncio
    async def test_brute_force_alert_pipeline(self, alert_engine, mock_redis):
        """Test complete pipeline for brute force detection."""
        # Setup Redis mocks for threshold checking
        # Mock the pipeline operations used by increment_counter
        mock_pipeline = AsyncMock()
        mock_pipeline.__aenter__.return_value.execute.return_value = [6, -2]  # count=6, ttl=-2 (new key)
        mock_pipeline.__aenter__.return_value.incr = AsyncMock()
        mock_pipeline.__aenter__.return_value.ttl = AsyncMock()
        mock_redis.pipeline.return_value = mock_pipeline
        
        # Mock expire for setting TTL
        mock_redis.expire = AsyncMock()
        
        # Mock exists for alert deduplication
        mock_redis.exists = AsyncMock(return_value=False)
        
        # Mock setex for marking alerts
        mock_redis.setex = AsyncMock()

        # Mock the mark_once for alert deduplication
        for rule in alert_engine._rules:
            if hasattr(rule, 'mark_once'):
                rule.mark_once = AsyncMock(return_value=True)
            # Mock check_threshold to return True when count >= threshold
            if hasattr(rule, 'check_threshold'):
                threshold_counts = {}
                async def mock_check_threshold(key, threshold, ttl):
                    if key not in threshold_counts:
                        threshold_counts[key] = 0
                    threshold_counts[key] += 1
                    return threshold_counts[key] >= threshold  # Trigger when threshold reached
                rule.check_threshold = mock_check_threshold
            # Mock get_counter_value to return the count
            if hasattr(rule, 'get_counter_value'):
                async def mock_get_counter_value(key):
                    # Return the count for this key
                    return threshold_counts.get(key, 0)
                rule.get_counter_value = mock_get_counter_value

        # Create multiple login failure events to trigger alert
        events = []
        for i in range(6):
            event = AuditEvent(
                event_type="login_failure",
                user_id="victim_user",
                session_id=None,
                ip_address="192.168.1.100",
                user_agent="MaliciousBot/1.0",
                request_id=f"req-{i}",
                timestamp=datetime.now(timezone.utc),
                details={"reason": "invalid_credentials"}
            )
            events.append(event)

        # Process events and capture alerts
        all_alerts = []
        for event in events:
            alerts = await alert_engine.dispatch(event)
            all_alerts.extend(alerts)

        # Should have triggered an alert
        assert len(all_alerts) >= 1

        brute_force_alerts = [a for a in all_alerts if a.alert_type == "excessive_login_failures"]
        assert len(brute_force_alerts) >= 1

        alert = brute_force_alerts[0]
        assert alert.severity == "high"
        assert alert.user_id == "victim_user"
        assert alert.ip_address == "192.168.1.100"
        assert alert.details["failure_count"] >= 5  # Should trigger when count reaches threshold

    @pytest.mark.asyncio
    async def test_multiple_sinks_delivery(self, mock_redis):
        """Test alert delivery to multiple sinks."""
        # Create alert engine with multiple sinks
        registry = AlertRegistry()

        # Add one rule
        from app.security.alerts.tier2 import ExcessiveLoginFailuresRule
        rule = ExcessiveLoginFailuresRule(mock_redis)
        registry.register(rule)

        # Create sink registry with multiple sinks
        sink_registry = AlertSinkRegistry()

        # Logging sink
        logging_sink = LoggingSink()
        sink_registry.register(logging_sink)

        # Mock webhook sink
        webhook_sink = AsyncMock()
        webhook_sink.name = "webhook"
        webhook_sink.send.return_value = AsyncMock(
            sink_name="webhook",
            success=True,
            delivery_time_ms=50
        )
        sink_registry.register(webhook_sink)

        # Enable both sinks
        sink_registry.enable(["log", "webhook"])

        dispatcher = AlertDispatcher(sink_registry)
        engine = AlertEngine(registry.build_engine()._rules, dispatcher)

        # Setup mocks
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=6)
        rule.mark_once = AsyncMock(return_value=True)
        
        # Mock check_threshold and get_counter_value for the rule
        threshold_counts = {}
        async def mock_check_threshold(key, threshold, ttl):
            if key not in threshold_counts:
                threshold_counts[key] = 0
            threshold_counts[key] += 1
            return threshold_counts[key] >= threshold
        rule.check_threshold = mock_check_threshold
        
        async def mock_get_counter_value(key):
            return threshold_counts.get(key, 0)
        rule.get_counter_value = mock_get_counter_value

        # Trigger alert
        event = AuditEvent(
            event_type="login_failure",
            user_id="test_user",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_credentials"}
        )

        alerts = await engine.dispatch(event)

        # Give async dispatch time to complete
        await asyncio.sleep(0.1)

        # Verify alert was created
        assert len(alerts) == 1

        # Verify webhook sink was called (logging sink is harder to verify in this context)
        webhook_sink.send.assert_called_once()

    @pytest.mark.asyncio
    async def test_sink_failure_does_not_break_engine(self, mock_redis):
        """Test that sink failures don't affect alert engine operation."""
        registry = AlertRegistry()

        from app.security.alerts.tier2 import ExcessiveLoginFailuresRule
        rule = ExcessiveLoginFailuresRule(mock_redis)
        registry.register(rule)

        # Create sink that always fails
        sink_registry = AlertSinkRegistry()
        failing_sink = AsyncMock()
        failing_sink.name = "failing"
        failing_sink.send.side_effect = Exception("Sink failure")
        sink_registry.register(failing_sink)
        sink_registry.enable(["failing"])

        dispatcher = AlertDispatcher(sink_registry)
        engine = AlertEngine(registry.build_engine()._rules, dispatcher)

        # Setup rule mocks
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=6)
        rule.mark_once = AsyncMock(return_value=True)
        
        # Mock check_threshold and get_counter_value for the rule
        threshold_counts = {}
        async def mock_check_threshold(key, threshold, ttl):
            if key not in threshold_counts:
                threshold_counts[key] = 0
            threshold_counts[key] += 1
            return threshold_counts[key] >= threshold
        rule.check_threshold = mock_check_threshold
        
        async def mock_get_counter_value(key):
            return threshold_counts.get(key, 0)
        rule.get_counter_value = mock_get_counter_value

        # Process event - should not raise exception despite sink failure
        event = AuditEvent(
            event_type="login_failure",
            user_id="test_user",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_credentials"}
        )

        # This should not raise an exception
        alerts = await engine.dispatch(event)

        # Alert should still be generated
        assert len(alerts) == 1
        assert alerts[0].alert_type == "excessive_login_failures"

    @pytest.mark.asyncio
    async def test_no_dispatcher_configured(self, mock_redis):
        """Test that engine works without dispatcher configured."""
        registry = AlertRegistry()

        from app.security.alerts.tier2 import ExcessiveLoginFailuresRule
        rule = ExcessiveLoginFailuresRule(mock_redis)
        registry.register(rule)

        # Create engine without dispatcher
        engine = AlertEngine(registry.build_engine()._rules, dispatcher=None)

        # Setup mocks
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=6)
        rule.mark_once = AsyncMock(return_value=True)
        
        # Mock check_threshold and get_counter_value for the rule
        threshold_counts = {}
        async def mock_check_threshold(key, threshold, ttl):
            if key not in threshold_counts:
                threshold_counts[key] = 0
            threshold_counts[key] += 1
            return threshold_counts[key] >= threshold
        rule.check_threshold = mock_check_threshold
        
        async def mock_get_counter_value(key):
            return threshold_counts.get(key, 0)
        rule.get_counter_value = mock_get_counter_value

        event = AuditEvent(
            event_type="login_failure",
            user_id="test_user",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_credentials"}
        )

        # Should work normally
        alerts = await engine.dispatch(event)
        assert len(alerts) == 1