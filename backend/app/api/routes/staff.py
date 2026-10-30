import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user, get_current_user
from app.core.security import hash_password
from app.db.session import get_db
from app.models.user import User, UserRole
from app.schemas.staff import PasswordResetRequestOut, ResetPasswordRequest, StaffCreate, StaffOut, StaffUpdate
from app.services import password_reset

router = APIRouter(prefix="/staff", tags=["staff"])

PHOTO_DIR = Path("media/staff_photos")


async def _save_staff_photo(file: UploadFile) -> str:
    PHOTO_DIR.mkdir(parents=True, exist_ok=True)
    suffix = Path(file.filename or "").suffix or ".jpg"
    filename = f"{uuid.uuid4().hex}{suffix}"
    path = PHOTO_DIR / filename
    path.write_bytes(await file.read())
    return f"media/staff_photos/{filename}"


@router.get("", response_model=list[StaffOut], dependencies=[Depends(get_current_admin_user)])
def list_staff(db: Session = Depends(get_db)):
    return db.query(User).order_by(User.id).all()


@router.post("", response_model=StaffOut, status_code=status.HTTP_201_CREATED, dependencies=[Depends(get_current_admin_user)])
def create_staff(payload: StaffCreate, db: Session = Depends(get_db)):
    if db.query(User).filter(User.user_id == payload.user_id).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="User ID already registered")
    if db.query(User).filter(User.phone_number == payload.phone_number).first():
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Phone number already registered")

    user = User(
        full_name=payload.full_name,
        user_id=payload.user_id,
        phone_number=payload.phone_number,
        hashed_password=hash_password(payload.password),
        role=payload.role,
        shop_id=payload.shop_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


# Declared before "/{staff_id}" so the literal path isn't captured as an id.
@router.get(
    "/password-reset-requests",
    response_model=list[PasswordResetRequestOut],
    dependencies=[Depends(get_current_admin_user)],
)
def list_password_reset_requests(db: Session = Depends(get_db)):
    return [
        PasswordResetRequestOut(staff=StaffOut.model_validate(user), requested_at=requested_at, message=message)
        for user, requested_at, message in password_reset.list_open_requests(db)
    ]


@router.post("/{staff_id}/password-reset-requests/dismiss", status_code=status.HTTP_204_NO_CONTENT)
def dismiss_password_reset_request(
    staff_id: int, admin_user: User = Depends(get_current_admin_user), db: Session = Depends(get_db)
):
    if password_reset.open_request(db, staff_id) is not None:
        password_reset.resolve(db, admin_id=admin_user.id, user_id=staff_id, action=password_reset.DISMISSED)
        db.commit()


@router.get("/{staff_id}", response_model=StaffOut, dependencies=[Depends(get_current_admin_user)])
def get_staff(staff_id: int, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")
    return user


@router.patch("/{staff_id}", response_model=StaffOut, dependencies=[Depends(get_current_admin_user)])
def update_staff(staff_id: int, payload: StaffUpdate, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, field, value)

    db.commit()
    db.refresh(user)
    return user


@router.post("/{staff_id}/reset-password", response_model=StaffOut)
def reset_password(
    staff_id: int,
    payload: ResetPasswordRequest,
    admin_user: User = Depends(get_current_admin_user),
    db: Session = Depends(get_db),
):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    user.hashed_password = hash_password(payload.new_password)
    # Also closes any open "forgot password" request from this user.
    password_reset.resolve(db, admin_id=admin_user.id, user_id=user.id, action=password_reset.RESET_BY_ADMIN)
    db.commit()
    db.refresh(user)
    return user


@router.delete("/{staff_id}", response_model=StaffOut, dependencies=[Depends(get_current_admin_user)])
def deactivate_staff(staff_id: int, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    user.is_active = False
    db.commit()
    db.refresh(user)
    return user


@router.post("/{staff_id}/photo", response_model=StaffOut, dependencies=[Depends(get_current_admin_user)])
async def upload_staff_photo(staff_id: int, photo: UploadFile = File(...), db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    user.photo_path = await _save_staff_photo(photo)
    db.commit()
    db.refresh(user)
    return user


@router.get("/{staff_id}/photo")
def get_staff_photo(staff_id: int, current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    # Shown in that staff member's own home-screen header, so the staff
    # member needs to be able to fetch their own photo — not just an admin.
    if staff_id != current_user.id and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this photo")

    user = db.get(User, staff_id)
    if user is None or user.photo_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No photo for this staff member")

    photo_path = Path(user.photo_path)
    if not photo_path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Photo file is missing")

    return FileResponse(photo_path)
