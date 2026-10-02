import enum

from sqlalchemy import Enum, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base
from app.db.mixins import TimestampMixin


class UserRole(str, enum.Enum):
    STAFF = "staff"
    ADMIN = "admin"


class User(TimestampMixin, Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    full_name: Mapped[str] = mapped_column(String(120))
    user_id: Mapped[str] = mapped_column(String(50), unique=True, index=True)
    phone_number: Mapped[str] = mapped_column(String(15), unique=True, index=True)
    hashed_password: Mapped[str] = mapped_column(String(255))
    role: Mapped[UserRole] = mapped_column(Enum(UserRole, name="user_role"), default=UserRole.STAFF)
    shop_id: Mapped[int | None] = mapped_column(ForeignKey("shops.id"), nullable=True)
    is_active: Mapped[bool] = mapped_column(default=True)
    photo_path: Mapped[str | None] = mapped_column(String(255), nullable=True)

    shop: Mapped["Shop"] = relationship(back_populates="users")

    # The login identifier (user_id) is shown on-screen instead of the phone
    # number, which stays only as internal contact info — so the API/schema
    # layer reads these as plain attributes rather than every route needing
    # its own join/lookup.
    @property
    def shop_name(self) -> str | None:
        return self.shop.name if self.shop else None

    @property
    def has_photo(self) -> bool:
        return self.photo_path is not None
