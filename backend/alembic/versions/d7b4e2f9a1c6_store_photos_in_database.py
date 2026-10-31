"""store staff photos and evidence images in the database

Render's free tier has no persistent disk, so files under media/ vanish on
every deploy/restart; the image bytes now live in the database instead.

Revision ID: d7b4e2f9a1c6
Revises: c3e8f1a5d2b7
Create Date: 2026-10-31 15:00:00.000000

"""
from typing import Sequence, Union

from alembic import op


# revision identifiers, used by Alembic.
revision: str = 'd7b4e2f9a1c6'
down_revision: Union[str, None] = 'c3e8f1a5d2b7'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # IF NOT EXISTS: app/db/schema_patches.py also adds these at startup.
    op.execute("ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_data BYTEA")
    op.execute("ALTER TABLE return_transactions ADD COLUMN IF NOT EXISTS evidence_image_data BYTEA")


def downgrade() -> None:
    op.execute("ALTER TABLE return_transactions DROP COLUMN IF EXISTS evidence_image_data")
    op.execute("ALTER TABLE users DROP COLUMN IF EXISTS photo_data")
