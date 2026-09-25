from pydantic import BaseModel, ConfigDict

from app.models.user import UserRole


class StaffCreate(BaseModel):
    full_name: str
    phone_number: str
    password: str
    role: UserRole = UserRole.STAFF
    shop_id: int | None = None


class StaffUpdate(BaseModel):
    full_name: str | None = None
    role: UserRole | None = None
    shop_id: int | None = None
    is_active: bool | None = None


class ResetPasswordRequest(BaseModel):
    new_password: str


class StaffOut(BaseModel):
    id: int
    full_name: str
    phone_number: str
    role: UserRole
    shop_id: int | None
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
