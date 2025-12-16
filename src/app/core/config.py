"""
Configuration management using Pydantic BaseSettings.
Loads environment variables with validation and type safety.
"""

import secrets
from typing import List, Optional

from pydantic import field_validator
from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    """
    Application settings loaded from environment variables.

    Security Notes:
    - All secrets are loaded from environment, never hardcoded
    - JWT secrets are auto-generated if not provided (dev only)
    - Database URLs contain credentials - ensure secure env handling
    """

    # Application
    app_name: str = "AI-Cloudx Agent"
    app_version: str = "1.0.0"
    debug: bool = False
    environment: str = "development"

    # Server
    host: str = "0.0.0.0"
    port: int = 8000
    workers: int = 1

    # Database
    database_url: str = "postgresql+asyncpg://user:pass@localhost:5432/default_db"
    db_pool_size: int = 10
    db_max_overflow: int = 20
    db_pool_recycle: int = 3600  # 1 hour

    # Redis
    redis_url: str = "redis://localhost:6379/0"
    redis_pool_size: int = 10

    # JWT Authentication
    jwt_secret_key: Optional[str] = None
    jwt_algorithm: str = "HS256"
    jwt_access_token_expire_minutes: int = 30
    jwt_refresh_token_expire_days: int = 7
    jwt_issuer: Optional[str] = None
    jwt_audience: Optional[str] = None

    # OAuth2 (placeholder for future)
    oauth2_client_id: Optional[str] = None
    oauth2_client_secret: Optional[str] = None

    # Security
    secret_key: Optional[str] = None  # For sessions, CSRF, etc.
    allowed_hosts: List[str] = ["localhost", "127.0.0.1"]
    cors_origins: List[str] = ["http://localhost:3000", "http://localhost:8000"]

    # AI/Agent
    openai_api_key: str = "default_openai_key"
    max_tokens_per_request: int = 4000
    rate_limit_requests_per_minute: int = 60

    # Storage (S3 compatible)
    storage_endpoint: Optional[str] = None
    storage_access_key: Optional[str] = None
    storage_secret_key: Optional[str] = None
    storage_bucket: str = "ai-cloudx-agent"

    # Observability
    log_level: str = "INFO"
    sentry_dsn: Optional[str] = None
    prometheus_enabled: bool = True

    # Development
    reload: bool = False

    class Config:
        env_file = ".env"
        case_sensitive = False

    @field_validator("jwt_secret_key", mode="after")
    @classmethod
    def validate_jwt_secret(cls, v, info):
        """Validate JWT secret based on environment."""
        if info.data.get('environment') == "production" and not v:
            raise ValueError("JWT_SECRET_KEY must be set in production")
        if not v:
            return secrets.token_urlsafe(32)
        return v

    @field_validator("secret_key", mode="after")
    @classmethod
    def validate_secret_key(cls, v):
        """Generate secure secret key if not provided."""
        if not v:
            return secrets.token_urlsafe(32)
        return v

    @field_validator("database_url", mode="after")
    @classmethod
    def validate_database_url(cls, v):
        """Validate database URL is PostgreSQL."""
        if not v.startswith("postgresql"):
            raise ValueError("Database URL must be PostgreSQL")
        return v


# Global settings instance - lazy loaded
_settings: Optional[Settings] = None


def get_settings() -> Settings:
    """
    Get application settings, loading from environment on first call.

    Returns:
        Configured Settings instance
    """
    global _settings
    if _settings is None:
        _settings = Settings()
    return _settings