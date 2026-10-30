from pydantic import BaseModel, ConfigDict, Field


class LoginRequest(BaseModel):
    user_id: str
    password: str


class ForgotPasswordRequest(BaseModel):
    user_id: str = Field(min_length=1, max_length=50)
    message: str | None = Field(default=None, max_length=200)


class ForgotPasswordResponse(BaseModel):
    detail: str


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
