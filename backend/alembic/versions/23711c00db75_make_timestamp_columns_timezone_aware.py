"""make timestamp columns timezone aware

Revision ID: 23711c00db75
Revises: 95e3db0597b5
Create Date: 2026-09-25 17:52:13.879189

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '23711c00db75'
down_revision: Union[str, None] = '95e3db0597b5'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


TABLES = ["payments", "return_transactions", "shops", "bottles", "users"]


def upgrade() -> None:
    # Existing values are naive UTC wall-clock times (Postgres NOW() on these
    # servers runs in UTC); reinterpret them as UTC rather than shifting them.
    for table in TABLES:
        for column in ("created_at", "updated_at"):
            op.alter_column(
                table,
                column,
                type_=sa.DateTime(timezone=True),
                postgresql_using=f"{column} AT TIME ZONE 'UTC'",
            )


def downgrade() -> None:
    for table in TABLES:
        for column in ("created_at", "updated_at"):
            op.alter_column(
                table,
                column,
                type_=sa.DateTime(timezone=False),
                postgresql_using=f"{column} AT TIME ZONE 'UTC'",
            )
