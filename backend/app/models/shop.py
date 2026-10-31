from datetime import time

from sqlalchemy import Numeric, String, Time
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.geo import DEFAULT_GEOFENCE_RADIUS_METERS
from app.db.base import Base
from app.db.mixins import TimestampMixin


class Shop(TimestampMixin, Base):
    __tablename__ = "shops"

    id: Mapped[int] = mapped_column(primary_key=True)
    name: Mapped[str] = mapped_column(String(150))
    shop_code: Mapped[str] = mapped_column(String(30), unique=True, index=True)
    address: Mapped[str | None] = mapped_column(String(255), nullable=True)
    latitude: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)
    longitude: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)
    is_active: Mapped[bool] = mapped_column(default=True)
    # How far (metres) from latitude/longitude staff may be and still count
    # as "at the shop". Set by admin per shop.
    geofence_radius_meters: Mapped[int] = mapped_column(
        default=DEFAULT_GEOFENCE_RADIUS_METERS, server_default=str(DEFAULT_GEOFENCE_RADIUS_METERS)
    )

    # Null start/end = no time-of-day restriction for this shop
    service_start_time: Mapped[time | None] = mapped_column(Time, nullable=True)
    service_end_time: Mapped[time | None] = mapped_column(Time, nullable=True)

    users: Mapped[list["User"]] = relationship(back_populates="shop")
    return_transactions: Mapped[list["ReturnTransaction"]] = relationship(back_populates="shop")
