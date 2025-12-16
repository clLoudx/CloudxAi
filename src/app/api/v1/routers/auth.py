from fastapi import APIRouter, Depends, HTTPException, status, Request
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.schemas.user import UserCreate, UserRead
from app.schemas.token import Token
from app.services.auth import (
    create_user,
    authenticate_user,
    create_token_pair,
    rotate_refresh_token,
    logout_current_session,
    logout_all_sessions,
)
from app.api.dependencies import get_current_user
from app.models.user import User
import uuid

router = APIRouter()


@router.post("/register", response_model=UserRead, status_code=status.HTTP_201_CREATED)
async def register(user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    user = await create_user(db, user_in)
    return user


@router.post("/login", response_model=Token)
async def login(request: Request, user_in: UserCreate, db: AsyncSession = Depends(get_db)):
    # Extract request context for audit logging
    request_id = str(uuid.uuid4())
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    user = await authenticate_user(
        db, user_in.email, user_in.password,
        request_id=request_id, ip_address=ip_address, user_agent=user_agent
    )
    if not user:
        raise HTTPException(status_code=401, detail="Invalid credentials")

    return create_token_pair(user, request_id=request_id, ip_address=ip_address, user_agent=user_agent)


@router.post("/refresh", response_model=Token)
async def refresh_token(request: Request, token_in: dict, db: AsyncSession = Depends(get_db)):
    """
    Refresh access token using refresh token.

    Expects JSON body: {"refresh_token": "token_here"}
    """
    # Extract request context for audit logging
    request_id = str(uuid.uuid4())
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    refresh_token_str = token_in.get("refresh_token")
    if not refresh_token_str:
        raise HTTPException(status_code=400, detail="Refresh token required")

    new_tokens = await rotate_refresh_token(
        refresh_token_str, db,
        request_id=request_id, ip_address=ip_address, user_agent=user_agent
    )
    if not new_tokens:
        raise HTTPException(status_code=401, detail="Invalid or expired refresh token")

    return new_tokens


@router.post("/logout")
async def logout(request: Request, token_in: dict):
    """
    Logout current session.

    Expects JSON body: {"refresh_token": "token_here"}
    """
    # Extract request context for audit logging
    request_id = str(uuid.uuid4())
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    refresh_token_str = token_in.get("refresh_token")
    if not refresh_token_str:
        raise HTTPException(status_code=400, detail="Refresh token required")

    success = await logout_current_session(
        refresh_token_str,
        request_id=request_id, ip_address=ip_address, user_agent=user_agent
    )
    if not success:
        raise HTTPException(status_code=400, detail="Invalid refresh token")

    return {"message": "Logged out successfully"}


@router.post("/logout-all")
async def logout_all(request: Request, current_user: User = Depends(get_current_user)):
    """
    Logout all sessions for the current user.
    """
    # Extract request context for audit logging
    request_id = str(uuid.uuid4())
    ip_address = request.client.host if request.client else None
    user_agent = request.headers.get("user-agent")

    success = await logout_all_sessions(
        str(current_user.id),
        request_id=request_id, ip_address=ip_address, user_agent=user_agent
    )
    if not success:
        raise HTTPException(status_code=500, detail="Logout failed")

    return {"message": "All sessions logged out successfully"}