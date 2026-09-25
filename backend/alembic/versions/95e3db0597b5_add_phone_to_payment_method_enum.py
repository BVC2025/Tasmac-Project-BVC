"""add phone to payment_method enum

Revision ID: 95e3db0597b5
Revises: efcac4a8ac76
Create Date: 2026-09-24 12:03:55.679125

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '95e3db0597b5'
down_revision: Union[str, None] = 'efcac4a8ac76'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.execute("ALTER TYPE payment_method ADD VALUE IF NOT EXISTS 'PHONE'")


def downgrade() -> None:
    # PostgreSQL does not support removing a value from an enum type.
    pass
