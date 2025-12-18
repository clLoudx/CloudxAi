"""
Tests for security utilities.
"""

import pytest
from jose import jwt

from ..core.config import Settings
from ..core.security import (
    create_access_token,
    create_refresh_token,
    get_password_hash,
    verify_password,
    verify_token,
)


class TestPasswordHashing:
    """Test password hashing and verification."""

    def test_password_hashing(self):
        """Test password hashing and verification."""
        password = "test_password"
        hashed = get_password_hash(password)
        assert verify_password(password, hashed)
        assert not verify_password("wrong_password", hashed)

    def test_password_hash_uniqueness(self):
        """Test that different passwords produce different hashes."""
        hash1 = get_password_hash("password1")
        hash2 = get_password_hash("password2")
        assert hash1 != hash2

    def test_password_bcrypt_72_byte_limit(self):
        """Test that passwords longer than 72 bytes are truncated."""
        # Create a password longer than 72 bytes
        long_password = "a" * 80  # 80 characters
        
        # Hash the long password (should be truncated to 72 bytes)
        long_hash = get_password_hash(long_password)
        
        # The long password should verify against its hash since it gets truncated during hashing and verification
        assert verify_password(long_password, long_hash)


class TestJWT:
    """Test JWT token creation and verification."""

    @pytest.fixture
    def test_settings(self):
        """Test settings for JWT."""
        return Settings(
            jwt_secret_key="test_secret_key_for_jwt",
            jwt_algorithm="HS256",
            jwt_access_token_expire_minutes=30,
            jwt_refresh_token_expire_days=7,
            jwt_issuer="ai-cloudx-auth",
            jwt_audience="ai-cloudx-api",
        )

    def test_create_access_token(self, test_settings):
        """Test access token creation."""
        data = {"sub": "test_user", "roles": ["admin"]}
        token = create_access_token(data, test_settings)
        assert isinstance(token, str)

        # Decode and verify using our verify_token function
        payload = verify_token(token, "access", test_settings)
        assert payload is not None
        assert payload["sub"] == "test_user"
        assert payload["roles"] == ["admin"]
        assert payload["type"] == "access"
        assert payload["iss"] == "ai-cloudx-auth"
        assert payload["aud"] == "ai-cloudx-api"
        assert "exp" in payload
        assert "iat" in payload
        assert "nbf" in payload

    def test_create_refresh_token(self, test_settings):
        """Test refresh token creation."""
        data = {"sub": "test_user"}
        token = create_refresh_token(data, test_settings)
        assert isinstance(token, str)

        # Decode and verify
        payload = jwt.decode(token, test_settings.jwt_secret_key, algorithms=[test_settings.jwt_algorithm])
        assert payload["sub"] == "test_user"
        assert payload["type"] == "refresh"
        assert "exp" in payload
        assert "jti" in payload  # JTI should be present for replay attack prevention
        assert "sid" in payload  # Session ID should be present for session management

    def test_verify_valid_token(self, test_settings):
        """Test verifying a valid token."""
        data = {"sub": "test_user"}
        token = create_access_token(data, test_settings)
        payload = verify_token(token, "access", test_settings)
        assert payload is not None
        assert payload["sub"] == "test_user"

    def test_verify_invalid_token(self, test_settings):
        """Test verifying an invalid token."""
        payload = verify_token("invalid_token", "access")
        assert payload is None

    def test_verify_invalid_issuer(self, test_settings):
        """Test that tokens with wrong issuer are rejected."""
        data = {"sub": "test_user", "roles": ["user"]}
        # Create token with wrong issuer
        wrong_settings = Settings(
            jwt_secret_key="test_secret_key_for_jwt",
            jwt_algorithm="HS256",
            jwt_access_token_expire_minutes=30,
            jwt_issuer="wrong-issuer",
            jwt_audience="ai-cloudx-api",
        )
        token = create_access_token(data, wrong_settings)
        payload = verify_token(token, "access", test_settings)
        assert payload is None

    def test_verify_invalid_audience(self, test_settings):
        """Test that tokens with wrong audience are rejected."""
        data = {"sub": "test_user", "roles": ["user"]}
        # Create token with wrong audience
        wrong_settings = Settings(
            jwt_secret_key="test_secret_key_for_jwt",
            jwt_algorithm="HS256",
            jwt_access_token_expire_minutes=30,
            jwt_issuer="ai-cloudx-auth",
            jwt_audience="wrong-audience",
        )
        token = create_access_token(data, wrong_settings)
        payload = verify_token(token, "access", test_settings)
        assert payload is None

    def test_verify_missing_trust_claims(self, test_settings):
        """Test that tokens missing trust claims are rejected."""
        # Create a token manually without trust claims
        from jose import jwt
        data = {"sub": "test_user", "roles": ["user"], "exp": 2000000000, "type": "access"}
        token = jwt.encode(data, test_settings.jwt_secret_key, algorithm=test_settings.jwt_algorithm)
        payload = verify_token(token, "access", test_settings)
        assert payload is None