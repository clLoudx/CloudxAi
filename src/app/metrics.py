"""
Metrics helpers for the application.

Provide lazy, test-friendly registration helpers so importing modules
does not register Prometheus metrics at import time and cause
duplicate metric registration errors during test collection.

Usage:
    metrics = register_ollama_metrics(registry=None)
    # metrics is a tuple (counter, histogram) or (None, None)
"""
from typing import Optional, Tuple

try:
    from prometheus_client import CollectorRegistry, Counter, Histogram  # type: ignore
    PROMETHEUS_AVAILABLE = True
except Exception:  # pragma: no cover - environment dependent
    CollectorRegistry = None  # type: ignore
    Counter = None  # type: ignore
    Histogram = None  # type: ignore
    PROMETHEUS_AVAILABLE = False


def register_ollama_metrics(registry: Optional[object] = None) -> Tuple[Optional[object], Optional[object]]:
    """Register and return Ollama-related Prometheus metrics.

    If prometheus_client is not installed, returns (None, None).
    If metrics are already registered in the provided registry, returns (None, None)
    and logs a warning via returning None values.

    Args:
        registry: Optional CollectorRegistry to register metrics in.

    Returns:
        (counter, histogram) or (None, None)
    """
    if not PROMETHEUS_AVAILABLE:
        return None, None

    # Allow passing None to use the default registry
    try:
        counter = Counter('ai_ollama_requests_total', 'Total Ollama requests', ['model', 'status'])
        histogram = Histogram('ai_ollama_request_duration_seconds', 'Ollama request latency', ['model'])
        return counter, histogram
    except ValueError:
        # Already registered
        return None, None
