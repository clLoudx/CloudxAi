from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Iterable, List, Optional, Protocol, TYPE_CHECKING
from datetime import datetime, timezone

if TYPE_CHECKING:
    from .alert_sinks import AlertDispatcher


# =========================
# Core Data Structures
# =========================


@dataclass(frozen=True)
class AuditEvent:
    event_type: str
    user_id: Optional[str]
    session_id: Optional[str]
    ip_address: Optional[str]
    user_agent: Optional[str]
    request_id: Optional[str]
    timestamp: datetime
    details: Dict[str, Any]


@dataclass(frozen=True)
class SecurityAlert:
    alert_type: str
    severity: str
    user_id: Optional[str]
    session_id: Optional[str]
    ip_address: Optional[str]
    request_id: Optional[str]
    timestamp: datetime
    details: Dict[str, Any]


# =========================
# Rule Interface
# =========================


class AlertRule(Protocol):
    """
    A deterministic alert rule.
    Must be pure: no side effects beyond Redis usage.
    """

    name: str

    def evaluate(self, event: AuditEvent) -> Optional[SecurityAlert]:
        ...


# =========================
# Alert Engine
# =========================


class AlertEngine:
    """
    Central dispatcher that evaluates audit events against registered rules
    and delivers alerts via the configured dispatcher.
    """

    def __init__(self, rules: Iterable[AlertRule], dispatcher: Optional['AlertDispatcher'] = None):
        self._rules: List[AlertRule] = list(rules)
        self._dispatcher = dispatcher

    async def dispatch(self, event: AuditEvent) -> List[SecurityAlert]:
        alerts: List[SecurityAlert] = []

        for rule in self._rules:
            try:
                alert = await rule.evaluate(event)
                if alert is not None:
                    alerts.append(alert)

                    # Deliver alert via dispatcher if configured
                    if self._dispatcher is not None:
                        # Schedule delivery asynchronously (fire-and-forget)
                        import asyncio
                        asyncio.create_task(
                            self._dispatcher.dispatch(alert, rule.name)
                        )

            except Exception:
                # Alerting must never break request flow
                continue

        return alerts


# =========================
# Registry Helper
# =========================


class AlertRegistry:
    """
    Explicit rule registration to avoid implicit imports.
    """

    def __init__(self) -> None:
        self._rules: List[AlertRule] = []

    def register(self, rule: AlertRule) -> None:
        self._rules.append(rule)

    def build_engine(self) -> AlertEngine:
        return AlertEngine(self._rules)


# =========================
# Utility Factory
# =========================


def make_alert(
    *,
    alert_type: str,
    severity: str,
    event: AuditEvent,
    details: Dict[str, Any],
) -> SecurityAlert:
    return SecurityAlert(
        alert_type=alert_type,
        severity=severity,
        user_id=event.user_id,
        session_id=event.session_id,
        ip_address=event.ip_address,
        request_id=event.request_id,
        timestamp=datetime.now(timezone.utc),
        details=details,
    )