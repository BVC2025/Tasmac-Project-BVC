from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_user
from app.core.security import create_access_token, verify_password
from app.db.session import get_db
from app.models.user import User
from app.schemas.auth import ForgotPasswordRequest, ForgotPasswordResponse, LoginRequest, TokenResponse, UserOut
from app.services import password_reset

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/login", response_model=TokenResponse)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.query(User).filter(User.user_id == payload.user_id).first()

    if user is None or not verify_password(payload.password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid user ID or password")

    if not user.is_active:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="User account is inactive")

    access_token = create_access_token(subject=str(user.id))
    return TokenResponse(access_token=access_token)


@router.post("/forgot-password", response_model=ForgotPasswordResponse, status_code=status.HTTP_202_ACCEPTED)
def forgot_password(payload: ForgotPasswordRequest, db: Session = Depends(get_db)):
    """Queues a password-reset request for an admin to act on. The reply is
    identical whether or not the User ID exists, so this can't be used to
    discover valid accounts."""
    user = db.query(User).filter(User.user_id == payload.user_id.strip()).first()
    if user is not None and user.is_active:
        password_reset.create_request(db, user, payload.message.strip() if payload.message else None)
        db.commit()
    return ForgotPasswordResponse(
        detail="Request sent. Your admin will reset your password and share the new one with you."
    )


@router.get("/me", response_model=UserOut)
def read_current_user(current_user: User = Depends(get_current_user)):
    return current_user
