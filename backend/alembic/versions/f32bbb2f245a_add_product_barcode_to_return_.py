"""add product barcode to return transactions

Revision ID: f32bbb2f245a
Revises: 23711c00db75
Create Date: 2026-09-29 11:48:59.318509

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'f32bbb2f245a'
down_revision: Union[str, None] = '23711c00db75'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('return_transactions', sa.Column('product_barcode', sa.String(length=64), nullable=True))


def downgrade() -> None:
    op.drop_column('return_transactions', 'product_barcode')
