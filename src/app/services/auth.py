from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy import select

from app.models.user import User
from app.schemas.user import UserCreate
from app.schemas.token import Token
from app.core.security import (
    get_password_hash,
    verify_password,
    create_access_token,
    create_refresh_token,
    verify_token,
    decode_jwt_token,
)
from app.core.config import get_settings
import redis.asyncio as redis
from typing import Dict, Any, Optional
import uuid
from app.services.audit import audit_service, AuditEventType


async def create_user(db: AsyncSession, user_in: UserCreate) -> User:
    user = User(
        email=user_in.email,
        hashed_password=get_password_hash(user_in.password),
        is_active=True,
        is_superuser=False,
        roles=["user"],  # Default role for new users
    )
    db.add(user)
    await db.commit()
    await db.refresh(user)
    return user


async def authenticate_user(
    db: AsyncSession, email: str, password: str, request_id: Optional[str] = None,
    ip_address: Optional[str] = None, user_agent: Optional[str] = None
) -> User | None:
    result = await db.execute(select(User).where(User.email == email))
    user = result.scalar_one_or_none()

    if not user:
        await audit_service.emit_event(
            AuditEventType.LOGIN_FAILURE,
            user_id=None,  # User not found, so no user_id
            ip_address=ip_address,
            user_agent=user_agent,
            request_id=request_id,
            details={"reason": "user_not_found", "email": email}
        )
        return None

    if not verify_password(password, user.hashed_password):
        await audit_service.emit_event(
            AuditEventType.LOGIN_FAILURE,
            user_id=str(user.id),
            ip_address=ip_address,
            user_agent=user_agent,
            request_id=request_id,
            details={"reason": "invalid_password"}
        )
        return None

    # Login successful
    await audit_service.emit_event(
        AuditEventType.LOGIN_SUCCESS,
        user_id=str(user.id),
        ip_address=ip_address,
        user_agent=user_agent,
        request_id=request_id
    )

    return user


def create_token_pair(user: User, request_id: Optional[str] = None,
                     ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> Token:
    jti = str(uuid.uuid4())
    sid = str(uuid.uuid4())  # Session ID for this login session

    token = Token(
        access_token=create_access_token({"sub": str(user.id), "roles": user.roles}),
        refresh_token=create_refresh_token({"sub": str(user.id), "jti": jti, "sid": sid}),
    )

    # Note: Login success is already logged in authenticate_user
    # Session creation is implicit in the token pair creation

    return token


def verify_access_token(token: str) -> Optional[Dict[str, Any]]:
    return verify_token(token, "access")


async def rotate_refresh_token(refresh_token: str, db: AsyncSession, request_id: Optional[str] = None,
                           ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> Optional[Token]:
    """
    Rotate refresh token to prevent replay attacks.

    Args:
        refresh_token: The refresh token to rotate
        db: Database session
        request_id: Request ID for audit correlation
        ip_address: Client IP for audit logging
        user_agent: Client user agent for audit logging

    Returns:
        New token pair if rotation successful, None otherwise
    """
    settings = get_settings()

    # Decode the refresh token
    payload = decode_jwt_token(refresh_token, settings)
    if not payload or payload.get("type") != "refresh":
        return None

    user_id = payload.get("sub")
    jti = payload.get("jti")
    sid = payload.get("sid")

    if not user_id or not jti or not sid:
        return None

    # Check if token has been used (replay attack prevention)
    redis_client = redis.Redis.from_url(settings.redis_url)
    jti_key = f"refresh_token_jti:{jti}"
    used = await redis_client.exists(jti_key)
    if used:
        # Token already used, revoke all refresh tokens for this user
        await revoke_user_refresh_tokens(user_id, redis_client)

        # Audit: Refresh replay detected
        await audit_service.emit_event(
            AuditEventType.REFRESH_REPLAY_DETECTED,
            user_id=user_id,
            session_id=sid,
            ip_address=ip_address,
            user_agent=user_agent,
            request_id=request_id,
            details={"jti": jti}
        )

        return None

    # Check if session has been revoked
    session_key = f"session:revoked:{sid}"
    session_revoked = await redis_client.exists(session_key)
    if session_revoked:
        return None

    # Check if all user sessions have been revoked
    user_revoke_key = f"user:sessions:revoked:{user_id}"
    user_revoked = await redis_client.exists(user_revoke_key)
    if user_revoked:
        return None

    # Mark this JTI as used
    await redis_client.setex(jti_key, settings.jwt_refresh_token_expire_days * 24 * 3600, "used")

    # Get user from database
    result = await db.execute(select(User).where(User.id == int(user_id)))
    user = result.scalar_one_or_none()
    if not user or not user.is_active:
        return None

    # Create new token pair with new JTI but same session ID
    new_jti = str(uuid.uuid4())
    token = Token(
        access_token=create_access_token({"sub": str(user.id)}),
        refresh_token=create_refresh_token({"sub": str(user.id), "jti": new_jti, "sid": sid}),
    )

    # Audit: Token refresh successful
    await audit_service.emit_event(
        AuditEventType.TOKEN_REFRESH,
        user_id=user_id,
        session_id=sid,
        ip_address=ip_address,
        user_agent=user_agent,
        request_id=request_id,
        details={"old_jti": jti, "new_jti": new_jti}
    )

    return token


async def revoke_user_refresh_tokens(user_id: str, redis_client: redis.Redis) -> None:
    """
    Revoke all refresh tokens for a user by deleting their JTI entries.
    Note: In production, you'd want to track all JTIs per user for efficient revocation.
    For now, this is a placeholder for future implementation.
    """
    # This is a simplified implementation. In production, maintain a set of JTIs per user
    # and delete them all here. For now, we rely on individual JTI expiration.
    pass


async def logout_current_session(refresh_token: str, request_id: Optional[str] = None,
                              ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> bool:
    """
    Logout current session by revoking the session ID.

    Args:
        refresh_token: The refresh token from the current session
        request_id: Request ID for audit correlation
        ip_address: Client IP for audit logging
        user_agent: Client user agent for audit logging

    Returns:
        True if logout successful, False otherwise
    """
    settings = get_settings()

    # Decode the refresh token to get session ID
    payload = decode_jwt_token(refresh_token, settings)
    if not payload or payload.get("type") != "refresh":
        return False

    user_id = payload.get("sub")
    sid = payload.get("sid")
    if not sid:
        return False

    # Mark session as revoked
    redis_client = redis.Redis.from_url(settings.redis_url)
    session_key = f"session:revoked:{sid}"
    await redis_client.setex(session_key, settings.jwt_refresh_token_expire_days * 24 * 3600, "revoked")

    # Audit: Logout current session
    await audit_service.emit_event(
        AuditEventType.LOGOUT,
        user_id=user_id,
        session_id=sid,
        ip_address=ip_address,
        user_agent=user_agent,
        request_id=request_id
    )

    return True


async def logout_all_sessions(user_id: str, request_id: Optional[str] = None,
                           ip_address: Optional[str] = None, user_agent: Optional[str] = None) -> bool:
    """
    Logout all sessions for a user by revoking all their sessions.

    Args:
        user_id: The user ID
        request_id: Request ID for audit correlation
        ip_address: Client IP for audit logging
        user_agent: Client user agent for audit logging

    Returns:
        True if logout successful, False otherwise
    """
    settings = get_settings()
    redis_client = redis.Redis.from_url(settings.redis_url)

    # In a production system, you'd maintain a set of active session IDs per user
    # For now, we'll use a simple approach: mark a global revocation for the user
    # This is less efficient but works for the current implementation
    user_revoke_key = f"user:sessions:revoked:{user_id}"
    await redis_client.setex(user_revoke_key, settings.jwt_refresh_token_expire_days * 24 * 3600, "revoked")

    # Audit: Logout all sessions
    await audit_service.emit_event(
        AuditEventType.LOGOUT_ALL,
        user_id=user_id,
        ip_address=ip_address,
        user_agent=user_agent,
        request_id=request_id
    )

    return True