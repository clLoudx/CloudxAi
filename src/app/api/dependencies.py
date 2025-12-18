from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from app.services.auth import verify_access_token
from app.models.user import User
from sqlalchemy.ext.asyncio import AsyncSession
from app.db.session import get_db
from typing import List
from app.services.audit import audit_service, AuditEventType
from typing import Optional

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/v1/auth/login")

async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db)
) -> User:
    """
    Dependency to get the currently authenticated user.
    Raises HTTP 401 if the token is invalid or user not found.
    """
    payload = verify_access_token(token)
    if not payload:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid authentication credentials",
        )

    user_id: str = payload.get("sub")
    if not user_id:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
        )

    user = await db.get(User, int(user_id))
    if not user:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
        )

    return user


def require_roles(*required_roles: str):
    """
    Dependency factory to require specific roles.

    Args:
        *required_roles: Role names that are required

    Returns:
        Dependency function that checks for required roles
    """
    async def role_checker(
        token: str = Depends(oauth2_scheme),
        db: AsyncSession = Depends(get_db)
    ) -> User:
        """
        Check that the current user has at least one of the required roles.
        Raises HTTP 403 if the user doesn't have the required roles.
        """
        payload = verify_access_token(token)
        if not payload:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid authentication credentials",
            )

        user_roles: List[str] = payload.get("roles", [])
        user_id: str = payload.get("sub")

        if not any(role in user_roles for role in required_roles):
            # Audit: Authorization denied
            import asyncio
            asyncio.create_task(audit_service.emit_event(
                AuditEventType.AUTHORIZATION_DENIED,
                user_id=user_id,
                ip_address=None,  # Not available in dependency context
                user_agent=None,  # Not available in dependency context
                request_id=None,  # Not available in dependency context
                details={"required_roles": list(required_roles), "user_roles": user_roles}
            ))

            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail="Insufficient permissions",
            )

        user_id: str = payload.get("sub")
        if not user_id:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid token payload",
            )

        user = await db.get(User, int(user_id))
        if not user or not user.is_active:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found or inactive",
            )

        return user

    return role_checker


# Convenience dependencies for common role checks
require_user = require_roles("user")
require_admin = require_roles("admin")