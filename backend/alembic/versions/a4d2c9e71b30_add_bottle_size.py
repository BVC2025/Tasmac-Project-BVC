"""add bottle_size to bottles

Revision ID: a4d2c9e71b30
Revises: 89550fda02f3
Create Date: 2026-10-30 18:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'a4d2c9e71b30'
down_revision: Union[str, None] = '89550fda02f3'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # IF NOT EXISTS: production may already have had the column added by hand
    # (Neon SQL editor) ahead of this migration running.
    op.execute("ALTER TABLE bottles ADD COLUMN IF NOT EXISTS bottle_size VARCHAR(30)")


def downgrade() -> None:
    op.execute("ALTER TABLE bottles DROP COLUMN IF EXISTS bottle_size")
