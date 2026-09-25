from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user
from app.core.security import hash_password
from app.db.session import get_db
from app.models.user import User
from app.schemas.staff import ResetPasswordRequest, StaffCreate, StaffOut, StaffUpdate

router = APIRouter(prefix="/staff", tags=["staff"], dependencies=[Depends(get_current_admin_user)])


@router.get("", response_model=list[StaffOut])
def list_staff(db: Session = Depends(get_db)):
    return db.query(User).order_by(User.id).all()


@router.post("", response_model=StaffOut, status_code=status.HTTP_201_CREATED)
def create_staff(payload: StaffCreate, db: Session = Depends(get_db)):
    existing = db.query(User).filter(User.phone_number == payload.phone_number).first()
    if existing:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="Phone number already registered")

    user = User(
        full_name=payload.full_name,
        phone_number=payload.phone_number,
        hashed_password=hash_password(payload.password),
        role=payload.role,
        shop_id=payload.shop_id,
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


@router.get("/{staff_id}", response_model=StaffOut)
def get_staff(staff_id: int, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")
    return user


@router.patch("/{staff_id}", response_model=StaffOut)
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
def reset_password(staff_id: int, payload: ResetPasswordRequest, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    user.hashed_password = hash_password(payload.new_password)
    db.commit()
    db.refresh(user)
    return user


@router.delete("/{staff_id}", response_model=StaffOut)
def deactivate_staff(staff_id: int, db: Session = Depends(get_db)):
    user = db.get(User, staff_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Staff not found")

    user.is_active = False
    db.commit()
    db.refresh(user)
    return user
