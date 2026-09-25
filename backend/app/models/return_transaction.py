import enum

from sqlalchemy import Enum, ForeignKey, Numeric, String, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.mixins import TimestampMixin


class ReturnStatus(str, enum.Enum):
    PENDING = "pending"
    VERIFIED = "verified"
    REJECTED = "rejected"


class RejectionReason(str, enum.Enum):
    REFUND_QR_DAMAGED = "refund_qr_damaged"
    MANUFACTURING_QR_DAMAGED = "manufacturing_qr_damaged"
    REFUND_QR_INVALID = "refund_qr_invalid"
    MANUFACTURING_QR_INVALID = "manufacturing_qr_invalid"
    QR_ALREADY_USED = "qr_already_used"
    BOTTLE_PHYSICALLY_DAMAGED = "bottle_physically_damaged"
    BOTTLE_BROKEN_CRACKED = "bottle_broken_cracked"
    BOTTLE_TAMPERED = "bottle_tampered"
    BOTTLE_NOT_ELIGIBLE = "bottle_not_eligible"
    OTHER = "other"


class ReturnTransaction(TimestampMixin, Base):
    __tablename__ = "return_transactions"

    id: Mapped[int] = mapped_column(primary_key=True)
    bottle_id: Mapped[int | None] = mapped_column(ForeignKey("bottles.id"), nullable=True)
    shop_id: Mapped[int] = mapped_column(ForeignKey("shops.id"))
    staff_user_id: Mapped[int] = mapped_column(ForeignKey("users.id"))
    customer_phone: Mapped[str | None] = mapped_column(String(15), nullable=True)
    status: Mapped[ReturnStatus] = mapped_column(Enum(ReturnStatus, name="return_status"), default=ReturnStatus.PENDING)
    latitude: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)
    longitude: Mapped[float | None] = mapped_column(Numeric(9, 6), nullable=True)

    rejection_reason: Mapped[RejectionReason | None] = mapped_column(
        Enum(RejectionReason, name="rejection_reason"), nullable=True
    )
    evidence_image_path: Mapped[str | None] = mapped_column(String(255), nullable=True)
    remarks: Mapped[str | None] = mapped_column(Text, nullable=True)

    bottle: Mapped["Bottle"] = relationship(back_populates="return_transactions")
    shop: Mapped["Shop"] = relationship(back_populates="return_transactions")
    staff_user: Mapped["User"] = relationship()
    payment: Mapped["Payment"] = relationship(back_populates="return_transaction", uselist=False)
