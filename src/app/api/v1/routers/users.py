from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from app.schemas.user import UserRead
from app.api.dependencies import get_current_user, require_admin
from app.models.user import User
from app.db.session import get_db
from sqlalchemy import select

router = APIRouter(prefix="/users", tags=["users"])

@router.get("/me", response_model=UserRead)
async def read_current_user(current_user: User = Depends(get_current_user)):
    """
    Protected route returning the current logged-in user.
    Requires authentication.
    """
    return current_user


@router.get("/admin/users", response_model=list[UserRead])
async def list_all_users(
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(require_admin)
):
    """
    Admin-only route to list all users.
    Requires admin role.
    """
    result = await db.execute(select(User))
    users = result.scalars().all()
    return users