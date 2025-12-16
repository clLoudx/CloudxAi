"""
Tier-2 Security Alert Rules

Rules implemented here:
- T2-01: Excessive Login Failures (brute force detection)
- T2-02: Refresh Token Abuse (token replay abuse detection)
- T2-03: Authorization Denial (repeated unauthorized access attempts)
- T2-04: Multi-Account Probe (rapid account enumeration)
- T2-05: Session Drift (anomalous session behavior)

Tier-2 rules are threshold-based anomaly detection rules that use Redis
counters and sliding windows for behavioral analysis.
"""

from typing import Optional
from datetime import datetime, timezone

from ..alert_engine import AlertRule, SecurityAlert, AuditEvent
from .redis_base import RedisAlertRule


class ExcessiveLoginFailuresRule(RedisAlertRule):
    """T2-01: Detect excessive login failures indicating brute force attempts."""

    name = "excessive_login_failures"

    def __init__(self, redis_client):
        super().__init__(redis_client)
        self.user_threshold = 5  # 5 failures per user in 10 minutes
        self.ip_threshold = 10   # 10 failures per IP in 10 minutes
        self.window_seconds = 600  # 10 minutes

    async def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "login_failure":
            return None

        # Check per-user threshold
        if event.user_id:
            user_key = self.key("user", event.user_id)
            user_triggered = await self.check_threshold(user_key, self.user_threshold, self.window_seconds)
            if user_triggered:
                user_count = await self.get_counter_value(user_key)
                return SecurityAlert(
                    alert_type="excessive_login_failures",
                    severity="high",
                    user_id=event.user_id,
                    session_id=event.session_id,
                    ip_address=event.ip_address,
                    request_id=event.request_id,
                    timestamp=datetime.now(timezone.utc),
                    details={
                        "dimension": "user",
                        "failure_count": user_count,
                        "window_seconds": self.window_seconds,
                        "last_failure_reason": event.details.get("reason", "unknown"),
                    },
                )        # Check per-IP threshold
        if event.ip_address:
            ip_key = self.key("ip", event.ip_address)
            ip_triggered = await self.check_threshold(ip_key, self.ip_threshold, self.window_seconds)
            if ip_triggered:
                ip_count = await self.get_counter_value(ip_key)
                return SecurityAlert(
                    alert_type="excessive_login_failures",
                    severity="high",
                    user_id=event.user_id,
                    session_id=event.session_id,
                    ip_address=event.ip_address,
                    request_id=event.request_id,
                    timestamp=datetime.now(timezone.utc),
                    details={
                        "dimension": "ip",
                        "failure_count": ip_count,
                        "window_seconds": self.window_seconds,
                        "sample_user": event.user_id or event.details.get("email"),
                    },
                )

        return None


class RefreshTokenAbuseRule(RedisAlertRule):
    """T2-02: Detect refresh token abuse indicating replay attacks or theft."""

    name = "refresh_token_abuse"

    def __init__(self, redis_client):
        super().__init__(redis_client)
        self.threshold = 5  # 5 refreshes per session in 5 minutes
        self.window_seconds = 300  # 5 minutes

    async def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "token_refresh":
            return None

        if not event.session_id:
            return None

        session_key = self.key("session", event.session_id)
        refresh_count = await self.check_threshold(session_key, self.threshold, self.window_seconds)

        if refresh_count:
            return SecurityAlert(
                alert_type="refresh_token_abuse",
                severity="high",
                user_id=event.user_id,
                session_id=event.session_id,
                ip_address=event.ip_address,
                request_id=event.request_id,
                timestamp=datetime.now(timezone.utc),
                details={
                    "refresh_count": refresh_count,
                    "window_seconds": self.window_seconds,
                    "user_agent": event.user_agent,
                },
            )

        return None


class AuthorizationDenialRule(RedisAlertRule):
    """T2-03: Detect repeated authorization denials indicating privilege escalation attempts."""

    name = "authorization_denial"

    def __init__(self, redis_client):
        super().__init__(redis_client)
        self.user_threshold = 10  # 10 denials per user in 15 minutes
        self.ip_threshold = 20    # 20 denials per IP in 15 minutes
        self.window_seconds = 900  # 15 minutes

    async def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type != "authorization_denial":
            return None

        # Check per-user threshold
        if event.user_id:
            user_key = self.key("user", event.user_id)
            user_count = await self.check_threshold(user_key, self.user_threshold, self.window_seconds)
            if user_count:
                return SecurityAlert(
                    alert_type="authorization_denial",
                    severity="medium",
                    user_id=event.user_id,
                    session_id=event.session_id,
                    ip_address=event.ip_address,
                    request_id=event.request_id,
                    timestamp=datetime.now(timezone.utc),
                    details={
                        "dimension": "user",
                        "denial_count": user_count,
                        "window_seconds": self.window_seconds,
                        "resource": event.details.get("resource"),
                        "action": event.details.get("action"),
                    },
                )

        # Check per-IP threshold
        if event.ip_address:
            ip_key = self.key("ip", event.ip_address)
            ip_count = await self.check_threshold(ip_key, self.ip_threshold, self.window_seconds)
            if ip_count:
                return SecurityAlert(
                    alert_type="authorization_denial",
                    severity="medium",
                    user_id=event.user_id,
                    session_id=event.session_id,
                    ip_address=event.ip_address,
                    request_id=event.request_id,
                    timestamp=datetime.now(timezone.utc),
                    details={
                        "dimension": "ip",
                        "denial_count": ip_count,
                        "window_seconds": self.window_seconds,
                        "sample_resource": event.details.get("resource"),
                    },
                )

        return None


class MultiAccountProbeRule(RedisAlertRule):
    """T2-04: Detect rapid attempts to access multiple accounts indicating enumeration."""

    name = "multi_account_probe"

    def __init__(self, redis_client):
        super().__init__(redis_client)
        self.threshold = 5  # 5 different accounts accessed in 10 minutes
        self.window_seconds = 600  # 10 minutes

    async def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if event.event_type not in ("login_success", "login_failure"):
            return None

        if not event.ip_address:
            return None

        # Track unique accounts accessed from this IP
        accounts_key = self.key("accounts", event.ip_address)
        account_id = event.user_id or event.details.get("email", "unknown")

        # Use Redis set to track unique accounts
        try:
            # Add account to set and get set size
            await self.redis.sadd(accounts_key, account_id)
            await self.redis.expire(accounts_key, self.window_seconds)
            account_count = await self.redis.scard(accounts_key)

            if account_count >= self.threshold:
                # Check if we've already alerted for this IP in the window
                alert_key = self.key("alerted", event.ip_address)
                if await self.mark_once(alert_key, self.window_seconds):
                    return SecurityAlert(
                        alert_type="multi_account_probe",
                        severity="medium",
                        user_id=None,  # No specific user targeted
                        session_id=None,
                        ip_address=event.ip_address,
                        request_id=event.request_id,
                        timestamp=datetime.now(timezone.utc),
                        details={
                            "account_count": account_count,
                            "window_seconds": self.window_seconds,
                            "last_account": account_id,
                        },
                    )
        except Exception:
            # Fail-safe: don't let Redis errors break the application
            pass

        return None


class SessionDriftRule(RedisAlertRule):
    """T2-05: Detect anomalous session behavior across multiple IPs or user agents."""

    name = "session_drift"

    def __init__(self, redis_client):
        super().__init__(redis_client)
        self.ip_threshold = 3     # 3 different IPs in 30 minutes
        self.ua_threshold = 5    # 5 different user agents in 30 minutes
        self.window_seconds = 1800  # 30 minutes

    async def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        if not event.session_id:
            return None

        # Only check on successful operations to avoid false positives from failed attempts
        if event.event_type not in ("login_success", "token_refresh", "api_access"):
            return None

        try:
            # Track unique IPs for this session
            if event.ip_address:
                ips_key = self.key("ips", event.session_id)
                await self.redis.sadd(ips_key, event.ip_address)
                await self.redis.expire(ips_key, self.window_seconds)
                ip_count = await self.redis.scard(ips_key)

                if ip_count >= self.ip_threshold:
                    alert_key = self.key("ip_alerted", event.session_id)
                    if await self.mark_once(alert_key, self.window_seconds):
                        return SecurityAlert(
                            alert_type="session_drift",
                            severity="low",
                            user_id=event.user_id,
                            session_id=event.session_id,
                            ip_address=event.ip_address,
                            request_id=event.request_id,
                            timestamp=datetime.now(timezone.utc),
                            details={
                                "anomaly_type": "multiple_ips",
                                "ip_count": ip_count,
                                "window_seconds": self.window_seconds,
                            },
                        )

            # Track unique user agents for this session
            if event.user_agent:
                ua_key = self.key("user_agents", event.session_id)
                await self.redis.sadd(ua_key, event.user_agent)
                await self.redis.expire(ua_key, self.window_seconds)
                ua_count = await self.redis.scard(ua_key)

                if ua_count >= self.ua_threshold:
                    alert_key = self.key("ua_alerted", event.session_id)
                    if await self.mark_once(alert_key, self.window_seconds):
                        return SecurityAlert(
                            alert_type="session_drift",
                            severity="low",
                            user_id=event.user_id,
                            session_id=event.session_id,
                            ip_address=event.ip_address,
                            request_id=event.request_id,
                            timestamp=datetime.now(timezone.utc),
                            details={
                                "anomaly_type": "multiple_user_agents",
                                "user_agent_count": ua_count,
                                "window_seconds": self.window_seconds,
                            },
                        )

        except Exception:
            # Fail-safe: don't let Redis errors break the application
            pass

        return None


# Explicit registry export (used by AlertEngine)
TIER2_RULES = [
    ExcessiveLoginFailuresRule,
    RefreshTokenAbuseRule,
    AuthorizationDenialRule,
    MultiAccountProbeRule,
    SessionDriftRule,
]