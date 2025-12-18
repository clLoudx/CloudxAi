import pytest
from unittest.mock import patch, MagicMock
from app.services.audit import AuditService, AuditEvent, AuditEventType
from datetime import datetime
import json


class TestAuditService:
    """Test audit service functionality."""

    def test_audit_event_creation(self):
        """Test that audit events are created correctly."""
        event = AuditEvent(
            event_type=AuditEventType.LOGIN_SUCCESS,
            user_id="123",
            session_id="session-456",
            ip_address="192.168.1.1",
            user_agent="TestAgent/1.0",
            timestamp=datetime(2023, 1, 1, 12, 0, 0),
            request_id="req-789",
            details={"test": "data"}
        )

        assert event.event_type == AuditEventType.LOGIN_SUCCESS
        assert event.user_id == "123"
        assert event.session_id == "session-456"
        assert event.ip_address == "192.168.1.1"
        assert event.user_agent == "TestAgent/1.0"
        assert event.request_id == "req-789"
        assert event.details == {"test": "data"}

    def test_audit_event_to_json(self):
        """Test that audit events serialize to JSON correctly."""
        timestamp = datetime(2023, 1, 1, 12, 0, 0)
        event = AuditEvent(
            event_type=AuditEventType.LOGIN_SUCCESS,
            user_id="123",
            timestamp=timestamp,
            request_id="req-789"
        )

        json_str = event.to_json()
        parsed = json.loads(json_str)

        assert parsed["event_type"] == "login_success"
        assert parsed["user_id"] == "123"
        assert parsed["request_id"] == "req-789"
        assert parsed["timestamp"] == timestamp.isoformat()
        assert parsed["details"] is None

    @pytest.mark.asyncio
    async def test_emit_event_logs_correctly(self):
        """Test that emit_event logs the event correctly."""
        service = AuditService()

        with patch.object(service.logger, 'info') as mock_info:
            await service.emit_event(
                AuditEventType.LOGIN_SUCCESS,
                user_id="123",
                request_id="req-789",
                details={"action": "test"}
            )

            # Verify that info was called once
            assert mock_info.call_count == 1

            # Get the logged message
            logged_message = mock_info.call_args[0][0]

            # Parse the JSON
            parsed = json.loads(logged_message)

            assert parsed["event_type"] == "login_success"
            assert parsed["user_id"] == "123"
            assert parsed["request_id"] == "req-789"
            assert parsed["details"]["action"] == "test"
            assert "timestamp" in parsed

    @pytest.mark.asyncio
    async def test_emit_event_with_minimal_data(self):
        """Test that emit_event works with minimal data."""
        service = AuditService()

        with patch.object(service.logger, 'info') as mock_info:
            await service.emit_event(AuditEventType.LOGOUT)

            logged_message = mock_info.call_args[0][0]
            parsed = json.loads(logged_message)

            assert parsed["event_type"] == "logout"
            assert parsed["user_id"] is None
            assert parsed["session_id"] is None
            assert parsed["ip_address"] is None
            assert parsed["user_agent"] is None
            assert "request_id" in parsed  # Should be auto-generated
            assert "timestamp" in parsed