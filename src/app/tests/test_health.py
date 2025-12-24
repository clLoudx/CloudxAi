"""
Tests for health check endpoints.
"""

from unittest.mock import AsyncMock

import pytest
from fastapi.testclient import TestClient


class TestHealthEndpoints:
    """Test health check endpoints."""

    def test_health_check(self, client: TestClient):
        """Test basic health check endpoint."""
        response = client.get("/api/v1/healthz")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "healthy"
        assert "timestamp" in data

    def test_readiness_check_success(self, client: TestClient):
        """Test readiness check with successful database connection."""
        response = client.get("/api/v1/readyz")
        assert response.status_code == 200
        data = response.json()
        assert data["status"] == "ready"
        assert data["database"] == "connected"
        assert "timestamp" in data

    def test_readiness_check_db_failure(self, client: TestClient):
        """Test readiness check with database connection failure."""
        # Create a session mock that raises when execute is called
        mock_session = AsyncMock()
        mock_session.execute.side_effect = Exception("Connection failed")

        # Import get_db lazily to avoid side-effects during collection
        from app.db.session import get_db

        # Override the TestClient's app dependency so the request handler will use our failing session
        def override_get_db():
            return mock_session

        client.app.dependency_overrides[get_db] = override_get_db

        try:
            response = client.get("/api/v1/readyz")
            assert response.status_code == 200  # Still returns 200, but status indicates not ready
            data = response.json()
            assert data["status"] == "not ready"
            assert data["database"] == "disconnected"
        finally:
            # clean up to avoid affecting other tests
            client.app.dependency_overrides.pop(get_db, None)

    def test_metrics_endpoint(self, client: TestClient):
        """Test metrics endpoint."""
        response = client.get("/api/v1/metrics")
        assert response.status_code == 200
        data = response.json()
        assert "uptime_seconds" in data
        assert "requests_total" in data
        assert "errors_total" in data
        assert "database_connections_active" in data
        assert "database_connections_idle" in data

    def test_root_endpoint(self, client: TestClient):
        """Test root endpoint."""
        response = client.get("/")
        assert response.status_code == 200
        data = response.json()
        assert "message" in data
        assert "version" in data
        assert "environment" in data