"""add user_id login field and photo to users

Revision ID: 89550fda02f3
Revises: 6258cb931fd6
Create Date: 2026-10-02 11:55:09.955071

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '89550fda02f3'
down_revision: Union[str, None] = '6258cb931fd6'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("users", sa.Column("user_id", sa.String(length=50), nullable=True))
    op.add_column("users", sa.Column("photo_path", sa.String(length=255), nullable=True))

    # Backfill existing accounts so login keeps working — their phone number
    # becomes their user_id until an admin sets a proper one for them.
    op.execute("UPDATE users SET user_id = phone_number WHERE user_id IS NULL")

    op.alter_column("users", "user_id", nullable=False)
    op.create_index(op.f("ix_users_user_id"), "users", ["user_id"], unique=True)


def downgrade() -> None:
    op.drop_index(op.f("ix_users_user_id"), table_name="users")
    op.drop_column("users", "photo_path")
    op.drop_column("users", "user_id")
