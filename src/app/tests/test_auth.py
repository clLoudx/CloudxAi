"""
Tests for authentication and authorization.
"""

import pytest
from unittest.mock import AsyncMock, patch
from fastapi.testclient import TestClient
import json

from ..main import app
from ..core.security import create_access_token
from ..core.config import Settings
from ..services.audit import AuditEventType


class TestRBAC:
    """Test role-based access control."""

    @pytest.fixture
    def client(self):
        """Test client."""
        return TestClient(app)

    @pytest.fixture
    def test_settings(self):
        """Test settings."""
        return Settings(
            jwt_secret_key="test_secret_key",
            jwt_algorithm="HS256",
            jwt_access_token_expire_minutes=30,
            jwt_refresh_token_expire_days=7,
        )

    def test_user_cannot_access_admin_routes(self, client, test_settings):
        """Test that a user with 'user' role cannot access admin routes."""
        token = create_access_token({"sub": "1", "roles": ["user"]}, test_settings)
        headers = {"Authorization": f"Bearer {token}"}

        response = client.get("/api/v1/users/admin/users", headers=headers)
        assert response.status_code == 403

    def test_missing_role_returns_403(self, client, test_settings):
        """Test that missing required role returns 403."""
        token = create_access_token({"sub": "1", "roles": []}, test_settings)
        headers = {"Authorization": f"Bearer {token}"}

        response = client.get("/api/v1/users/admin/users", headers=headers)
        assert response.status_code == 403

    def test_invalid_token_returns_401(self, client):
        """Test that invalid token returns 401."""
        headers = {"Authorization": "Bearer invalid_token"}

        response = client.get("/api/v1/users/me", headers=headers)
        assert response.status_code == 401


class TestAuditLogging:
    """Test audit logging integration."""

    @pytest.fixture
    def client(self):
        """Test client."""
        return TestClient(app)

    @pytest.fixture
    def test_settings(self):
        """Test settings."""
        return Settings(
            jwt_secret_key="test_secret_key",
            jwt_algorithm="HS256",
            jwt_access_token_expire_minutes=30,
            jwt_refresh_token_expire_days=7,
        )

    @patch('app.services.audit.audit_service.emit_event')
    def test_authorization_denied_logs_event(self, mock_emit, client, test_settings):
        """Test that authorization denied events are logged."""
        # Create token with insufficient roles
        token = create_access_token({"sub": "1", "roles": ["user"]}, test_settings)
        headers = {"Authorization": f"Bearer {token}"}

        # Attempt to access admin route
        response = client.get("/api/v1/users/admin/users", headers=headers)
        assert response.status_code == 403

        # Verify audit event was emitted
        mock_emit.assert_called_once()
        call_args = mock_emit.call_args
        event_type = call_args[0][0]
        kwargs = call_args[1]

        assert event_type == AuditEventType.AUTHORIZATION_DENIED
        assert kwargs["user_id"] == "1"
        assert kwargs["details"]["required_roles"] == ["admin"]
        assert kwargs["details"]["user_roles"] == ["user"]

    @patch('app.services.audit.audit_service.emit_event')
    def test_invalid_token_does_not_log_auth_denied(self, mock_emit, client):
        """Test that invalid tokens don't trigger authorization denied logging."""
        headers = {"Authorization": "Bearer invalid_token"}

        response = client.get("/api/v1/users/admin/users", headers=headers)
        assert response.status_code == 401

        # Should not emit authorization_denied event (token is invalid, not insufficient permissions)
        mock_emit.assert_not_called()