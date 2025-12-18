"""
Alert Sink Interface

Routes validated alerts to external systems without coupling detection logic to delivery.
"""

from __future__ import annotations

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Any, Dict, List, Optional, Protocol
from datetime import datetime
import asyncio
import logging
import aiohttp
from urllib.parse import urlparse
from aiohttp import ClientError

from .alert_engine import SecurityAlert


# =========================
# Canonical Alert Payload
# =========================


@dataclass(frozen=True)
class AlertEvent:
    """
    Canonical payload sent to all alert sinks.

    This is the single source of truth for alert delivery.
    """
    alert_id: str
    rule_id: str
    severity: str
    timestamp: datetime
    user_id: Optional[str]
    session_id: Optional[str]
    ip_address: Optional[str]
    request_id: Optional[str]
    details: Dict[str, Any]

    @classmethod
    def from_security_alert(cls, alert: SecurityAlert, rule_name: str) -> AlertEvent:
        """Convert SecurityAlert to canonical AlertEvent."""
        import uuid
        return cls(
            alert_id=str(uuid.uuid4()),
            rule_id=rule_name,
            severity=alert.severity,
            timestamp=alert.timestamp,
            user_id=alert.user_id,
            session_id=alert.session_id,
            ip_address=alert.ip_address,
            request_id=alert.request_id,
            details=alert.details,
        )


# =========================
# Delivery Result
# =========================


@dataclass(frozen=True)
class AlertDeliveryResult:
    """Result of attempting to deliver an alert to a sink."""
    sink_name: str
    success: bool
    error_message: Optional[str] = None
    delivery_time_ms: Optional[int] = None


# =========================
# Sink Interface
# =========================


class AlertSink(ABC):
    """
    Abstract base class for alert delivery sinks.

    All sinks must implement this interface.
    """

    @property
    @abstractmethod
    def name(self) -> str:
        """Unique name for this sink."""
        ...

    @abstractmethod
    async def send(self, alert: AlertEvent) -> AlertDeliveryResult:
        """
        Deliver the alert to the external system.

        Must be fail-safe: never raise exceptions.
        """
        ...


# =========================
# Sink Registry
# =========================


class AlertSinkRegistry:
    """
    Manages enabled alert sinks.
    """

    def __init__(self):
        self._sinks: Dict[str, AlertSink] = {}
        self._enabled: List[str] = []

    def register(self, sink: AlertSink) -> None:
        """Register a sink (but don't enable it yet)."""
        self._sinks[sink.name] = sink

    def enable(self, sink_names: List[str]) -> None:
        """Enable specific sinks by name."""
        self._enabled = [name for name in sink_names if name in self._sinks]

    def get_enabled_sinks(self) -> List[AlertSink]:
        """Return all enabled sinks."""
        return [self._sinks[name] for name in self._enabled if name in self._sinks]


# =========================
# Alert Dispatcher
# =========================


class AlertDispatcher:
    """
    Fan-out engine for alert delivery.

    Dispatches alerts to all enabled sinks independently.
    Failures in one sink do not affect others.
    """

    def __init__(self, registry: AlertSinkRegistry):
        self.registry = registry
        self.logger = logging.getLogger(__name__)

    async def dispatch(self, alert: SecurityAlert, rule_name: str) -> List[AlertDeliveryResult]:
        """
        Dispatch alert to all enabled sinks.

        Returns results for all delivery attempts.
        Never raises exceptions.
        """
        alert_event = AlertEvent.from_security_alert(alert, rule_name)
        enabled_sinks = self.registry.get_enabled_sinks()

        if not enabled_sinks:
            self.logger.warning("No alert sinks enabled - alert will not be delivered")
            return []

        results = []
        for sink in enabled_sinks:
            try:
                result = await sink.send(alert_event)
                results.append(result)

                if result.success:
                    self.logger.info(
                        f"Alert {alert_event.alert_id} delivered successfully to {sink.name}"
                    )
                else:
                    self.logger.error(
                        f"Alert {alert_event.alert_id} delivery failed to {sink.name}: {result.error_message}"
                    )

            except Exception as e:
                # This should never happen if sinks are properly implemented
                error_result = AlertDeliveryResult(
                    sink_name=sink.name,
                    success=False,
                    error_message=f"Unexpected sink error: {str(e)}"
                )
                results.append(error_result)
                self.logger.error(
                    f"Unexpected error delivering alert {alert_event.alert_id} to {sink.name}: {str(e)}"
                )

        return results


# =========================
# Logging Sink (Tier-0)
# =========================


class LoggingSink(AlertSink):
    """
    Logs alerts as structured JSON.

    Acts as default safety net and audit trail.
    """

    def __init__(self, logger: Optional[logging.Logger] = None):
        self.logger = logger or logging.getLogger("alerts")

    @property
    def name(self) -> str:
        return "log"

    async def send(self, alert: AlertEvent) -> AlertDeliveryResult:
        """Log the alert as structured JSON."""
        import json
        import time

        start_time = time.time()

        try:
            # Convert to dict for JSON serialization
            alert_dict = {
                "alert_id": alert.alert_id,
                "rule_id": alert.rule_id,
                "severity": alert.severity,
                "timestamp": alert.timestamp.isoformat(),
                "user_id": alert.user_id,
                "session_id": alert.session_id,
                "ip_address": alert.ip_address,
                "request_id": alert.request_id,
                "details": alert.details,
            }

            # Log at appropriate level based on severity
            log_level = {
                "critical": logging.CRITICAL,
                "high": logging.ERROR,
                "medium": logging.WARNING,
                "low": logging.INFO,
            }.get(alert.severity.lower(), logging.INFO)

            self.logger.log(log_level, f"Security Alert: {json.dumps(alert_dict)}")

            delivery_time = int((time.time() - start_time) * 1000)
            return AlertDeliveryResult(
                sink_name=self.name,
                success=True,
                delivery_time_ms=delivery_time
            )

        except Exception as e:
            delivery_time = int((time.time() - start_time) * 1000)
            return AlertDeliveryResult(
                sink_name=self.name,
                success=False,
                error_message=f"Logging failed: {str(e)}",
                delivery_time_ms=delivery_time
            )


# =========================
# Webhook Sink (Tier-0)
# =========================


class WebhookSink(AlertSink):
    """
    Delivers alerts via HTTP POST to configured webhook endpoint.
    """

    def __init__(
        self,
        url: str,
        timeout_seconds: int = 10,
        max_retries: int = 3,
        headers: Optional[Dict[str, str]] = None,
    ):
        self.url = url
        self.timeout_seconds = timeout_seconds
        self.max_retries = max_retries
        self.headers = headers or {"Content-Type": "application/json"}
        self.logger = logging.getLogger(__name__)

        # Validate URL
        parsed = urlparse(url)
        if not parsed.scheme or not parsed.netloc:
            raise ValueError(f"Invalid webhook URL: {url}")

    @property
    def name(self) -> str:
        return "webhook"

    async def send(self, alert: AlertEvent) -> AlertDeliveryResult:
        """POST the alert to the webhook endpoint."""
        import json
        import time

        start_time = time.time()

        try:
            # Convert to dict for JSON serialization
            payload = {
                "alert_id": alert.alert_id,
                "rule_id": alert.rule_id,
                "severity": alert.severity,
                "timestamp": alert.timestamp.isoformat(),
                "user_id": alert.user_id,
                "session_id": alert.session_id,
                "ip_address": alert.ip_address,
                "request_id": alert.request_id,
                "details": alert.details,
            }

            json_payload = json.dumps(payload)

            for attempt in range(self.max_retries):
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.post(
                            self.url,
                            data=json_payload,
                            headers=self.headers,
                            timeout=aiohttp.ClientTimeout(total=self.timeout_seconds)
                        ) as response:
                            if response.status < 400:
                                delivery_time = int((time.time() - start_time) * 1000)
                                return AlertDeliveryResult(
                                    sink_name=self.name,
                                    success=True,
                                    delivery_time_ms=delivery_time
                                )
                            else:
                                error_msg = f"HTTP {response.status}: {await response.text()}"

                except asyncio.TimeoutError:
                    error_msg = f"Timeout after {self.timeout_seconds}s"
                except ClientError as e:
                    error_msg = f"HTTP client error: {str(e)}"

                # If we get here, the attempt failed
                if attempt < self.max_retries - 1:
                    await asyncio.sleep(0.1 * (2 ** attempt))  # Exponential backoff
                    continue

            # All retries failed
            delivery_time = int((time.time() - start_time) * 1000)
            return AlertDeliveryResult(
                sink_name=self.name,
                success=False,
                error_message=f"Failed after {self.max_retries} attempts: {error_msg}",
                delivery_time_ms=delivery_time
            )

        except Exception as e:
            delivery_time = int((time.time() - start_time) * 1000)
            return AlertDeliveryResult(
                sink_name=self.name,
                success=False,
                error_message=f"Webhook preparation failed: {str(e)}",
                delivery_time_ms=delivery_time
            )