from pydantic import BaseModel, ConfigDict


class LoginRequest(BaseModel):
    user_id: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    full_name: str
    user_id: str
    phone_number: str
    role: str
    shop_id: int | None
    shop_name: str | None
    has_photo: bool
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
