from fastapi import APIRouter, Depends, HTTPException, status

from app.api.deps import get_current_user
from app.core.geo import GEOFENCE_RADIUS_METERS, haversine_distance_meters
from app.models.user import User
from app.schemas.location import LocationCheckRequest, LocationCheckResponse
from app.services.shop_access import ensure_within_service_window

router = APIRouter(prefix="/location", tags=["location"])


@router.post("/verify", response_model=LocationCheckResponse)
def verify_location(payload: LocationCheckRequest, current_user: User = Depends(get_current_user)):
    shop = current_user.shop

    if shop is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You are not assigned to a shop")

    ensure_within_service_window(shop)

    if shop.latitude is None or shop.longitude is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Your shop has no registered location")

    distance = haversine_distance_meters(
        payload.latitude, payload.longitude, float(shop.latitude), float(shop.longitude)
    )

    return LocationCheckResponse(
        shop_id=shop.id,
        shop_name=shop.name,
        distance_meters=round(distance, 1),
        radius_meters=GEOFENCE_RADIUS_METERS,
        within_range=distance <= GEOFENCE_RADIUS_METERS,
    )
