from fastapi import APIRouter, Depends
from app.schemas.user import UserRead
from app.api.dependencies import get_current_user
from app.db.models import User

router = APIRouter(prefix="/users", tags=["users"])

@router.get("/me", response_model=UserRead)
async def read_current_user(current_user: User = Depends(get_current_user)):
    """
    Protected route returning the current logged-in user.
    """
    return current_user