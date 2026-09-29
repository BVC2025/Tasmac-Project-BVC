"""support one payment covering multiple return transactions

Revision ID: 6258cb931fd6
Revises: f32bbb2f245a
Create Date: 2026-09-29 14:54:50.201076

"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '6258cb931fd6'
down_revision: Union[str, None] = 'f32bbb2f245a'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # Both tables are transactional/regenerable data (bottle records, not
    # accounts) and are empty at migration time — no backfill needed.
    op.add_column('return_transactions', sa.Column('payment_id', sa.Integer(), nullable=True))
    op.create_foreign_key(
        'fk_return_transactions_payment_id', 'return_transactions', 'payments', ['payment_id'], ['id']
    )
    op.drop_column('payments', 'return_transaction_id')


def downgrade() -> None:
    op.add_column('payments', sa.Column('return_transaction_id', sa.Integer(), nullable=True))
    op.drop_constraint('fk_return_transactions_payment_id', 'return_transactions', type_='foreignkey')
    op.drop_column('return_transactions', 'payment_id')
