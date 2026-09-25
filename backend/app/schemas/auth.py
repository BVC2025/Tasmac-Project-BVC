from pydantic import BaseModel, ConfigDict


class LoginRequest(BaseModel):
    phone_number: str
    password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"


class UserOut(BaseModel):
    id: int
    full_name: str
    phone_number: str
    role: str
    is_active: bool

    model_config = ConfigDict(from_attributes=True)
