"""
Security utilities for authentication and authorization.
Implements JWT tokens with refresh flow and password hashing.
"""

import secrets
from datetime import datetime, timedelta, timezone
from typing import Any, Dict, Optional
import hashlib
import bcrypt
from jose import JWTError, jwt

from .config import Settings, get_settings


def verify_password(plain_password: str, hashed_password: bytes) -> bool:
    """
    Verify a password against its hash.

    Args:
        plain_password: Plain text password
        hashed_password: Hashed password as bytes

    Returns:
        True if password matches
    """
    try:
        # Deterministic pre-hash: compute a fixed digest of the password
        # Encoding must be deterministic (UTF-8). Use SHA-256 to produce
        # a fixed-size digest that fits bcrypt's input constraints.
        password_bytes = plain_password.encode('utf-8')
        prehash = hashlib.sha256(password_bytes).digest()
        return bcrypt.checkpw(prehash, hashed_password)
    except ValueError:
        return False


def get_password_hash(password: str) -> bytes:
    """
    Hash a password using bcrypt.

    Note: bcrypt has a 72-byte limit on passwords. Passwords longer than 72 bytes
    will be truncated before hashing. This is a bcrypt limitation, not a security
    flaw - longer passwords are still secure but only the first 72 bytes are used.

    Args:
        password: Plain text password

    Returns:
        Hashed password as bytes
    """
    # Deterministic pre-hash: compute a fixed digest of the password
    # Use UTF-8 encoding and SHA-256 to derive a fixed-length input for bcrypt.
    password_bytes = password.encode('utf-8')
    prehash = hashlib.sha256(password_bytes).digest()

    # Generate salt and hash the deterministic prehash. Keep bcrypt's
    # salt randomness and cost factor unchanged.
    salt = bcrypt.gensalt()
    hashed = bcrypt.hashpw(prehash, salt)
    return hashed


def create_access_token(data: Dict[str, Any], settings: Optional[Settings] = None, expires_delta: Optional[timedelta] = None) -> str:
    """
    Create JWT access token.

    Args:
        data: Data to encode in token
        settings: Optional settings override

    Returns:
        JWT token string
    """
    if settings is None:
        settings = get_settings()
    to_encode = data.copy()
    if expires_delta:
        expire = datetime.now(timezone.utc) + expires_delta
    else:
        expire = datetime.now(timezone.utc) + timedelta(minutes=settings.jwt_access_token_expire_minutes)

    to_encode.update({"exp": expire, "type": "access"})
    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    return encoded_jwt


def create_refresh_token(data: Dict[str, Any], settings: Optional[Settings] = None) -> str:
    """
    Create JWT refresh token.

    Args:
        data: Data to encode in token
        settings: Optional settings override

    Returns:
        JWT token string
    """
    if settings is None:
        settings = get_settings()
    to_encode = data.copy()
    expire = datetime.now(timezone.utc) + timedelta(days=settings.jwt_refresh_token_expire_days)
    to_encode.update({"exp": expire, "type": "refresh"})
    encoded_jwt = jwt.encode(to_encode, settings.jwt_secret_key, algorithm=settings.jwt_algorithm)
    return encoded_jwt


def verify_token(token: str, token_type: str = "access", settings: Optional[Settings] = None) -> Optional[Dict[str, Any]]:
    """
    Verify and decode JWT token.

    Args:
        token: JWT token string
        token_type: Expected token type
        settings: Optional settings override

    Returns:
        Decoded payload or None if invalid
    """
    if settings is None:
        settings = get_settings()
    try:
        payload = jwt.decode(token, settings.jwt_secret_key, algorithms=[settings.jwt_algorithm])
        if payload.get("type") != token_type:
            return None
        return payload
    except JWTError:
        return None


def generate_secure_token(length: int = 32) -> str:
    """
    Generate a secure random token.

    Args:
        length: Token length in bytes

    Returns:
        Hex-encoded token
    """
    return secrets.token_hex(length)


# OAuth2 placeholder (for future expansion)
class OAuth2Provider:
    """
    Placeholder for OAuth2 integration.
    To be implemented with specific providers (GitHub, Google, etc.)
    """

    def __init__(self, client_id: str, client_secret: str):
        self.client_id = client_id
        self.client_secret = client_secret

    async def get_user_info(self, code: str) -> Dict[str, Any]:
        """Exchange code for user info. To be implemented."""
        raise NotImplementedError("OAuth2 integration not yet implemented")