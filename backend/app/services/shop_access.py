from datetime import datetime

from fastapi import HTTPException, status

from app.models.shop import Shop


def ensure_within_service_window(shop: Shop) -> None:
    if shop.service_start_time is None or shop.service_end_time is None:
        return

    now = datetime.now().time()
    if not (shop.service_start_time <= now <= shop.service_end_time):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Service available only between {shop.service_start_time.strftime('%I:%M %p')} "
                f"and {shop.service_end_time.strftime('%I:%M %p')}"
            ),
        )
