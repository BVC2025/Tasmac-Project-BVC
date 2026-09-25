from datetime import time

from pydantic import BaseModel, ConfigDict


class ShopCreate(BaseModel):
    name: str
    shop_code: str
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    service_start_time: time | None = None
    service_end_time: time | None = None


class ShopUpdate(BaseModel):
    name: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    is_active: bool | None = None
    service_start_time: time | None = None
    service_end_time: time | None = None


class ShopOut(BaseModel):
    id: int
    name: str
    shop_code: str
    address: str | None
    latitude: float | None
    longitude: float | None
    is_active: bool
    service_start_time: time | None
    service_end_time: time | None

    model_config = ConfigDict(from_attributes=True)
