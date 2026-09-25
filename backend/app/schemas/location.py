from pydantic import BaseModel


class LocationCheckRequest(BaseModel):
    latitude: float
    longitude: float


class LocationCheckResponse(BaseModel):
    shop_id: int
    shop_name: str
    distance_meters: float
    radius_meters: int
    within_range: bool
