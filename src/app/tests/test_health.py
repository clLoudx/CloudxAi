"""
Tests for health check endpoints.
"""

from unittest.mock import AsyncMock, patch

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

    @patch("app.api.v1.routers.health.get_db")
    def test_readiness_check_db_failure(self, mock_get_db, client: TestClient):
        """Test readiness check with database connection failure."""
        # Mock database session to raise exception
        mock_session = AsyncMock()
        mock_session.execute.side_effect = Exception("Connection failed")
        mock_get_db.return_value.__aenter__.return_value = mock_session

        response = client.get("/api/v1/readyz")
        assert response.status_code == 200  # Still returns 200, but status indicates not ready
        data = response.json()
        assert data["status"] == "not ready"
        assert data["database"] == "disconnected"

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