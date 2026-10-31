"""add geofence_radius_meters to shops

Revision ID: c3e8f1a5d2b7
Revises: a4d2c9e71b30
Create Date: 2026-10-31 12:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'c3e8f1a5d2b7'
down_revision: Union[str, None] = 'a4d2c9e71b30'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # IF NOT EXISTS: production may already have had the column added by hand
    # (Neon SQL editor) ahead of this migration running.
    op.execute(
        "ALTER TABLE shops ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER NOT NULL DEFAULT 150"
    )


def downgrade() -> None:
    op.execute("ALTER TABLE shops DROP COLUMN IF EXISTS geofence_radius_meters")
