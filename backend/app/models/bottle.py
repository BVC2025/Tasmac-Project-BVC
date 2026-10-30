import enum

from sqlalchemy import Enum, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.mixins import TimestampMixin


class BottleStatus(str, enum.Enum):
    ISSUED = "issued"
    RETURNED = "returned"
    REDEEMED = "redeemed"


class Bottle(TimestampMixin, Base):
    __tablename__ = "bottles"

    id: Mapped[int] = mapped_column(primary_key=True)
    refund_qr_code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    manufacturing_qr_code: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    brand_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    # e.g. "Quarter 180 ml", "Half 375 ml", "Full 750 ml" — set when the bottle's
    # QR pair is provisioned.
    bottle_size: Mapped[str | None] = mapped_column(String(30), nullable=True)
    status: Mapped[BottleStatus] = mapped_column(Enum(BottleStatus, name="bottle_status"), default=BottleStatus.ISSUED)

    return_transactions: Mapped[list["ReturnTransaction"]] = relationship(back_populates="bottle")
