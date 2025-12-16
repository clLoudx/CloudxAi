"""
Tier-1 Security Alert Rules

Rules implemented here:
- Refresh token replay detection
- JWT trust boundary violations
- Revoked session usage attempts

Tier-1 rules are immediate-signal alerts:
- No aggregation windows
- No counters
- Fire instantly on a single event
"""

from typing import Optional
from datetime import datetime, timezone

from ..alert_engine import AlertRule, SecurityAlert, AuditEvent


class RefreshReplayRule(AlertRule):
    """Alert when a refresh token replay is detected."""

    name = "refresh_replay_detected"

    def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "refresh_replay_detected":
            return None

        return SecurityAlert(
            alert_type="refresh_token_replay",
            severity="critical",
            user_id=event.user_id,
            session_id=event.session_id,
            ip_address=event.ip_address,
            request_id=event.request_id,
            timestamp=datetime.now(timezone.utc),
            details={
                "jti": event.details.get("jti"),
                "user_agent": event.user_agent,
            },
        )


class JWTTrustViolationRule(AlertRule):
    """Alert when JWT trust claims validation fails."""

    name = "jwt_trust_violation"

    def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "jwt_trust_violation":
            return None

        return SecurityAlert(
            alert_type="jwt_trust_violation",
            severity="high",
            user_id=event.user_id,
            session_id=None,
            ip_address=event.ip_address,
            request_id=event.request_id,
            timestamp=datetime.now(timezone.utc),
            details={
                "reason": event.details.get("reason"),
                "issuer": event.details.get("iss"),
                "audience": event.details.get("aud"),
            },
        )


class RevokedSessionUsageRule(AlertRule):
    """Alert when a revoked session attempts to use a token."""

    name = "revoked_session_usage"

    def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "revoked_session_usage":
            return None

        return SecurityAlert(
            alert_type="revoked_session_usage",
            severity="high",
            user_id=event.user_id,
            session_id=event.session_id,
            ip_address=event.ip_address,
            request_id=event.request_id,
            timestamp=datetime.now(timezone.utc),
            details={
                "user_agent": event.user_agent,
            },
        )


# Explicit registry export (used by AlertEngine)
TIER1_RULES = [
    RefreshReplayRule(),
    JWTTrustViolationRule(),
    RevokedSessionUsageRule(),
]