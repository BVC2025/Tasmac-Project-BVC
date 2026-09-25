import enum

from sqlalchemy import Enum, ForeignKey, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.mixins import TimestampMixin


class PaymentMethod(str, enum.Enum):
    UPI = "upi"
    PHONE = "phone"
    CASH = "cash"
    WALLET = "wallet"


class PaymentStatus(str, enum.Enum):
    PENDING = "pending"
    SUCCESS = "success"
    FAILED = "failed"


class Payment(TimestampMixin, Base):
    __tablename__ = "payments"

    id: Mapped[int] = mapped_column(primary_key=True)
    return_transaction_id: Mapped[int] = mapped_column(ForeignKey("return_transactions.id"), unique=True)
    amount: Mapped[float] = mapped_column(Numeric(6, 2), default=10.00)
    method: Mapped[PaymentMethod] = mapped_column(Enum(PaymentMethod, name="payment_method"), default=PaymentMethod.UPI)
    status: Mapped[PaymentStatus] = mapped_column(Enum(PaymentStatus, name="payment_status"), default=PaymentStatus.PENDING)
    reference_id: Mapped[str | None] = mapped_column(String(100), nullable=True)
    customer_identifier: Mapped[str | None] = mapped_column(String(120), nullable=True)

    return_transaction: Mapped["ReturnTransaction"] = relationship(back_populates="payment")
