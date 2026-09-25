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
    status: Mapped[BottleStatus] = mapped_column(Enum(BottleStatus, name="bottle_status"), default=BottleStatus.ISSUED)

    return_transactions: Mapped[list["ReturnTransaction"]] = relationship(back_populates="bottle")
