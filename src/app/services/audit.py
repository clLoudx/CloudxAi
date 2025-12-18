from enum import Enum
from typing import Optional, Dict, Any
from pydantic import BaseModel
import json
import logging
import uuid
from datetime import datetime


class AuditEventType(str, Enum):
    """Audit event types for security telemetry."""
    LOGIN_SUCCESS = "login_success"
    LOGIN_FAILURE = "login_failure"
    TOKEN_REFRESH = "token_refresh"
    REFRESH_REPLAY_DETECTED = "refresh_replay_detected"
    LOGOUT = "logout"
    LOGOUT_ALL = "logout_all"
    AUTHORIZATION_DENIED = "authorization_denied"


class AuditEvent(BaseModel):
    """Structured audit event for security telemetry."""
    event_type: AuditEventType
    user_id: Optional[str] = None
    session_id: Optional[str] = None
    ip_address: Optional[str] = None
    user_agent: Optional[str] = None
    timestamp: datetime
    request_id: str
    details: Optional[Dict[str, Any]] = None

    def to_json(self) -> str:
        """Convert audit event to JSON string for logging."""
        return json.dumps({
            "event_type": self.event_type.value,
            "user_id": self.user_id,
            "session_id": self.session_id,
            "ip_address": self.ip_address,
            "user_agent": self.user_agent,
            "timestamp": self.timestamp.isoformat(),
            "request_id": self.request_id,
            "details": self.details
        }, default=str)


class AuditService:
    """Service for emitting structured audit events."""

    def __init__(self):
        self.logger = logging.getLogger("security.audit")
        # Configure logger to output JSON to stdout
        handler = logging.StreamHandler()
        handler.setFormatter(logging.Formatter('%(message)s'))
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)

    async def emit_event(
        self,
        event_type: AuditEventType,
        user_id: Optional[str] = None,
        session_id: Optional[str] = None,
        ip_address: Optional[str] = None,
        user_agent: Optional[str] = None,
        request_id: Optional[str] = None,
        details: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Emit a structured audit event.

        Args:
            event_type: The type of security event
            user_id: User ID if known
            session_id: Session ID if available
            ip_address: Client IP address
            user_agent: Client user agent string
            request_id: Request ID for correlation
            details: Additional event-specific details
        """
        if request_id is None:
            request_id = str(uuid.uuid4())

        event = AuditEvent(
            event_type=event_type,
            user_id=user_id,
            session_id=session_id,
            ip_address=ip_address,
            user_agent=user_agent,
            timestamp=datetime.utcnow(),
            request_id=request_id,
            details=details
        )

        # Log as JSON to stdout for structured logging
        self.logger.info(event.to_json())


# Global audit service instance
audit_service = AuditService()