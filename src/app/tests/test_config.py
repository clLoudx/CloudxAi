"""
Tests for configuration management.
"""

import os
from unittest.mock import patch

import pytest

from ..core.config import Settings, get_settings


class TestSettings:
    """Test configuration loading and validation."""

    def test_default_settings(self):
        """Test loading with default values."""
        with patch.dict(os.environ, {}, clear=True):
            test_settings = Settings()
            assert test_settings.app_name == "AI-Cloudx Agent"
            assert test_settings.debug is False
            assert test_settings.port == 8000

    def test_environment_override(self):
        """Test overriding settings from environment."""
        env_vars = {
            "APP_NAME": "Test App",
            "DEBUG": "true",
            "PORT": "9000",
            "DATABASE_URL": "postgresql://user:pass@localhost:5432/test",
            "JWT_SECRET_KEY": "test_jwt_secret",
            "OPENAI_API_KEY": "test_openai_key",
        }

        with patch.dict(os.environ, env_vars, clear=True):
            test_settings = Settings()
            assert test_settings.app_name == "Test App"
            assert test_settings.debug is True
            assert test_settings.port == 9000
            assert test_settings.database_url == "postgresql://user:pass@localhost:5432/test"
            assert test_settings.jwt_secret_key == "test_jwt_secret"

    def test_jwt_secret_generation(self):
        """Test JWT secret auto-generation in development."""
        env_vars = {
            "ENVIRONMENT": "development",
            "DATABASE_URL": "postgresql://user:pass@localhost:5432/test",
            "OPENAI_API_KEY": "test_key",
        }

        with patch.dict(os.environ, env_vars, clear=True):
            test_settings = Settings()
            assert len(test_settings.jwt_secret_key) == 43  # base64url encoded 32 bytes

    def test_jwt_secret_required_in_production(self):
        """Test JWT secret is required in production."""
        env_vars = {
            "ENVIRONMENT": "production",
            "DATABASE_URL": "postgresql://user:pass@localhost:5432/test",
            "OPENAI_API_KEY": "test_key",
        }

        with patch.dict(os.environ, env_vars, clear=True):
            with pytest.raises(ValueError, match="JWT_SECRET_KEY must be set in production"):
                Settings()

    def test_database_url_validation(self):
        """Test database URL validation."""
        env_vars = {
            "DATABASE_URL": "mysql://user:pass@localhost:3306/test",
            "JWT_SECRET_KEY": "test_secret",
            "OPENAI_API_KEY": "test_key",
        }

        with patch.dict(os.environ, env_vars, clear=True):
            with pytest.raises(ValueError, match="Database URL must be PostgreSQL"):
                Settings()

    def test_cors_origins_list(self):
        """Test CORS origins parsing."""
        env_vars = {
            "CORS_ORIGINS": '["http://example.com", "https://test.com"]',
            "DATABASE_URL": "postgresql://user:pass@localhost:5432/test",
            "JWT_SECRET_KEY": "test_secret",
            "OPENAI_API_KEY": "test_key",
        }

        with patch.dict(os.environ, env_vars, clear=True):
            test_settings = Settings()
            assert test_settings.cors_origins == ["http://example.com", "https://test.com"]