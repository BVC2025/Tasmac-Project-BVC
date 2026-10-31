from datetime import time

from pydantic import BaseModel, ConfigDict, Field

from app.core.geo import DEFAULT_GEOFENCE_RADIUS_METERS, MAX_GEOFENCE_RADIUS_METERS, MIN_GEOFENCE_RADIUS_METERS


class ShopCreate(BaseModel):
    name: str
    shop_code: str
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    geofence_radius_meters: int = Field(
        default=DEFAULT_GEOFENCE_RADIUS_METERS, ge=MIN_GEOFENCE_RADIUS_METERS, le=MAX_GEOFENCE_RADIUS_METERS
    )
    service_start_time: time | None = None
    service_end_time: time | None = None


class ShopUpdate(BaseModel):
    name: str | None = None
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    is_active: bool | None = None
    geofence_radius_meters: int | None = Field(
        default=None, ge=MIN_GEOFENCE_RADIUS_METERS, le=MAX_GEOFENCE_RADIUS_METERS
    )
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
    geofence_radius_meters: int
    service_start_time: time | None
    service_end_time: time | None

    model_config = ConfigDict(from_attributes=True)
