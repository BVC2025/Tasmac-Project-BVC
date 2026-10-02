from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import HTTPException, status

from app.models.shop import Shop

IST = ZoneInfo("Asia/Kolkata")


def ensure_within_service_window(shop: Shop) -> None:
    if shop.service_start_time is None or shop.service_end_time is None:
        return

    # The server runs in UTC, but admins enter service hours as local (IST)
    # wall-clock time — compare against IST "now", not the server's raw UTC.
    now = datetime.now(IST).time()
    if not (shop.service_start_time <= now <= shop.service_end_time):
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=(
                f"Service available only between {shop.service_start_time.strftime('%I:%M %p')} "
                f"and {shop.service_end_time.strftime('%I:%M %p')}"
            ),
        )
