"""
Tests for Tier-2 threshold-based alert rules.
"""

import pytest
from unittest.mock import AsyncMock, MagicMock
import redis.asyncio as redis
from datetime import datetime, timezone

from app.security.alerts.tier2 import (
    ExcessiveLoginFailuresRule,
    RefreshTokenAbuseRule,
    AuthorizationDenialRule,
    MultiAccountProbeRule,
    SessionDriftRule,
)
from app.security.alert_engine import AuditEvent


class TestExcessiveLoginFailuresRule:
    """Test T2-01: Excessive Login Failures detection."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return ExcessiveLoginFailuresRule(mock_redis)

    @pytest.mark.asyncio
    async def test_non_login_failure_event_ignored(self, rule):
        """Test that non-login-failure events are ignored."""
        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_user_threshold_not_exceeded(self, rule, mock_redis):
        """Test that alert is not triggered when user threshold not exceeded."""
        # Mock check_threshold to return False (not exceeded)
        rule.check_threshold = AsyncMock(return_value=False)

        event = AuditEvent(
            event_type="login_failure",
            user_id="123",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_password"}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_user_threshold_exceeded(self, rule, mock_redis):
        """Test that alert is triggered when user threshold exceeded."""
        # Mock check_threshold to return 5 (threshold exceeded)
        rule.check_threshold = AsyncMock(return_value=5)

        event = AuditEvent(
            event_type="login_failure",
            user_id="123",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_password"}
        )

        alert = await rule.evaluate(event)

        assert alert is not None
        assert alert.alert_type == "excessive_login_failures"
        assert alert.severity == "high"
        assert alert.user_id == "123"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["dimension"] == "user"
        assert alert.details["failure_count"] == 5
        assert alert.details["window_seconds"] == 600

    @pytest.mark.asyncio
    async def test_ip_threshold_exceeded(self, rule, mock_redis):
        """Test that alert is triggered when IP threshold exceeded."""
        # Mock check_threshold to return False for user, True for IP
        rule.check_threshold = AsyncMock(side_effect=[False, 10])

        event = AuditEvent(
            event_type="login_failure",
            user_id="123",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"reason": "invalid_password"}
        )

        alert = await rule.evaluate(event)

        assert alert is not None
        assert alert.alert_type == "excessive_login_failures"
        assert alert.severity == "high"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["dimension"] == "ip"
        assert alert.details["failure_count"] == 10


class TestRefreshTokenAbuseRule:
    """Test T2-02: Refresh Token Abuse detection."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return RefreshTokenAbuseRule(mock_redis)

    @pytest.mark.asyncio
    async def test_non_refresh_event_ignored(self, rule):
        """Test that non-refresh events are ignored."""
        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address=None,
            user_agent=None,
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_refresh_without_session_ignored(self, rule):
        """Test that refresh events without session_id are ignored."""
        event = AuditEvent(
            event_type="token_refresh",
            user_id="123",
            session_id=None,
            ip_address=None,
            user_agent=None,
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_threshold_not_exceeded(self, rule, mock_redis):
        """Test that alert is not triggered when threshold not exceeded."""
        # Mock check_threshold to return False
        rule.check_threshold = AsyncMock(return_value=False)

        event = AuditEvent(
            event_type="token_refresh",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            timestamp=datetime.now(timezone.utc),
            request_id="req-1",
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_threshold_exceeded(self, rule, mock_redis):
        """Test that alert is triggered when threshold exceeded."""
        # Mock check_threshold to return 5 (threshold exceeded)
        rule.check_threshold = AsyncMock(return_value=5)

        event = AuditEvent(
            event_type="token_refresh",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            timestamp=datetime.now(timezone.utc),
            request_id="req-1",
            details={}
        )

        alert = await rule.evaluate(event)

        assert alert is not None
        assert alert.alert_type == "refresh_token_abuse"
        assert alert.severity == "high"
        assert alert.user_id == "123"
        assert alert.session_id == "session-456"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["refresh_count"] == 5
        assert alert.details["window_seconds"] == 300


class TestAuthorizationDenialRule:
    """Test T2-03: Authorization Denial detection."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return AuthorizationDenialRule(mock_redis)

    @pytest.mark.asyncio
    async def test_non_denial_event_ignored(self, rule):
        """Test that non-authorization-denial events are ignored."""
        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_user_threshold_not_exceeded(self, rule, mock_redis):
        """Test that alert is not triggered when user threshold not exceeded."""
        rule.check_threshold = AsyncMock(return_value=False)

        event = AuditEvent(
            event_type="authorization_denial",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"resource": "/admin/users", "action": "read"}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_user_threshold_exceeded(self, rule, mock_redis):
        """Test that alert is triggered when user threshold exceeded."""
        rule.check_threshold = AsyncMock(return_value=10)

        event = AuditEvent(
            event_type="authorization_denial",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"resource": "/admin/users", "action": "read"}
        )

        alert = await rule.evaluate(event)

        assert alert is not None
        assert alert.alert_type == "authorization_denial"
        assert alert.severity == "medium"
        assert alert.user_id == "123"
        assert alert.session_id == "session-456"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["dimension"] == "user"
        assert alert.details["denial_count"] == 10
        assert alert.details["resource"] == "/admin/users"
        assert alert.details["action"] == "read"

    @pytest.mark.asyncio
    async def test_ip_threshold_exceeded(self, rule, mock_redis):
        """Test that alert is triggered when IP threshold exceeded."""
        # Only IP check happens since user_id is None
        rule.check_threshold = AsyncMock(return_value=20)

        event = AuditEvent(
            event_type="authorization_denial",
            user_id=None,
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={"resource": "/admin/users", "action": "read"}
        )

        alert = await rule.evaluate(event)

        assert alert is not None
        assert alert.alert_type == "authorization_denial"
        assert alert.severity == "medium"
        assert alert.user_id is None
        assert alert.session_id == "session-456"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["dimension"] == "ip"
        assert alert.details["denial_count"] == 20


class TestMultiAccountProbeRule:
    """Test T2-04: Multi-Account Probe detection."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return MultiAccountProbeRule(mock_redis)

    @pytest.mark.asyncio
    async def test_non_login_event_ignored(self, rule):
        """Test that non-login events are ignored."""
        event = AuditEvent(
            event_type="api_access",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_no_ip_address_ignored(self, rule):
        """Test that events without IP address are ignored."""
        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address=None,
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_threshold_not_exceeded(self, rule, mock_redis):
        """Test that alert is not triggered when threshold not exceeded."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=3)  # Below threshold of 5

        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_threshold_exceeded_first_time(self, rule, mock_redis):
        """Test that alert is triggered when threshold exceeded for first time."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=5)  # At threshold
        rule.mark_once = AsyncMock(return_value=True)  # First time alerting

        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)

        # Verify Redis operations were called
        mock_redis.sadd.assert_called_once()
        mock_redis.expire.assert_called_once()
        mock_redis.scard.assert_called_once()
        rule.mark_once.assert_called_once()

        assert alert is not None
        assert alert.alert_type == "multi_account_probe"
        assert alert.severity == "medium"
        assert alert.user_id is None
        assert alert.session_id is None
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["account_count"] == 5
        assert alert.details["last_account"] == "123"

    @pytest.mark.asyncio
    async def test_threshold_exceeded_already_alerted(self, rule, mock_redis):
        """Test that alert is not triggered again when already alerted in window."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=7)  # Above threshold
        rule.mark_once = AsyncMock(return_value=False)  # Already alerted

        event = AuditEvent(
            event_type="login_success",
            user_id="456",
            session_id="session-789",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-2",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None


class TestSessionDriftRule:
    """Test T2-05: Session Drift detection."""

    @pytest.fixture
    def mock_redis(self):
        """Mock Redis client."""
        return AsyncMock(spec=redis.Redis)

    @pytest.fixture
    def rule(self, mock_redis):
        """Test rule instance."""
        return SessionDriftRule(mock_redis)

    @pytest.mark.asyncio
    async def test_no_session_id_ignored(self, rule):
        """Test that events without session ID are ignored."""
        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id=None,
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_non_success_event_ignored(self, rule):
        """Test that non-success events are ignored."""
        event = AuditEvent(
            event_type="login_failure",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_ip_threshold_not_exceeded(self, rule, mock_redis):
        """Test that IP alert is not triggered when threshold not exceeded."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=2)  # Below threshold of 3

        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None

    @pytest.mark.asyncio
    async def test_ip_threshold_exceeded(self, rule, mock_redis):
        """Test that IP alert is triggered when threshold exceeded."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=3)  # At threshold
        rule.mark_once = AsyncMock(return_value=True)  # First time alerting

        event = AuditEvent(
            event_type="login_success",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)

        # Verify Redis operations were called for IP tracking
        assert mock_redis.sadd.call_count >= 1
        assert mock_redis.expire.call_count >= 1
        assert mock_redis.scard.call_count >= 1
        rule.mark_once.assert_called_once()

        assert alert is not None
        assert alert.alert_type == "session_drift"
        assert alert.severity == "low"
        assert alert.user_id == "123"
        assert alert.session_id == "session-456"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["anomaly_type"] == "multiple_ips"
        assert alert.details["ip_count"] == 3

    @pytest.mark.asyncio
    async def test_user_agent_threshold_exceeded(self, rule, mock_redis):
        """Test that user agent alert is triggered when threshold exceeded."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        # First call for IPs (below threshold), second for user agents (at threshold)
        mock_redis.scard = AsyncMock(side_effect=[2, 5])
        rule.mark_once = AsyncMock(return_value=True)  # First time alerting

        event = AuditEvent(
            event_type="api_access",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
            request_id="req-1",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)

        # Verify Redis operations were called for both IP and UA tracking
        assert mock_redis.sadd.call_count == 2  # Once for IP, once for UA
        assert mock_redis.expire.call_count == 2
        assert mock_redis.scard.call_count == 2
        rule.mark_once.assert_called_once()

        assert alert is not None
        assert alert.alert_type == "session_drift"
        assert alert.severity == "low"
        assert alert.user_id == "123"
        assert alert.session_id == "session-456"
        assert alert.ip_address == "192.168.1.1"
        assert alert.details["anomaly_type"] == "multiple_user_agents"
        assert alert.details["user_agent_count"] == 5

    @pytest.mark.asyncio
    async def test_already_alerted_no_duplicate(self, rule, mock_redis):
        """Test that alerts are not duplicated when already alerted."""
        mock_redis.sadd = AsyncMock()
        mock_redis.expire = AsyncMock()
        mock_redis.scard = AsyncMock(return_value=4)  # Above threshold
        rule.mark_once = AsyncMock(return_value=False)  # Already alerted

        event = AuditEvent(
            event_type="token_refresh",
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.2",
            user_agent="TestAgent",
            request_id="req-2",
            timestamp=datetime.now(timezone.utc),
            details={}
        )

        alert = await rule.evaluate(event)
        assert alert is None