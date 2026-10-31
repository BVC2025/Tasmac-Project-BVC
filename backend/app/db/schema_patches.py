"""Additive schema changes applied automatically at startup.

Render deploys straight from git, and it is not guaranteed that `alembic
upgrade head` runs before the new code starts serving. New code that reads a
column the database doesn't have yet would break every query on that table,
so the purely additive columns below are ensured here first. Each statement is
idempotent (IF NOT EXISTS), and each one also has a matching Alembic
migration so `alembic upgrade head` stays the source of truth.
"""

import logging

from sqlalchemy import text
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

ADDITIVE_COLUMNS = [
    "ALTER TABLE bottles ADD COLUMN IF NOT EXISTS bottle_size VARCHAR(30)",
    "ALTER TABLE shops ADD COLUMN IF NOT EXISTS geofence_radius_meters INTEGER NOT NULL DEFAULT 150",
    "ALTER TABLE users ADD COLUMN IF NOT EXISTS photo_data BYTEA",
    "ALTER TABLE return_transactions ADD COLUMN IF NOT EXISTS evidence_image_data BYTEA",
]


def ensure_schema(engine: Engine) -> None:
    if engine.dialect.name != "postgresql":
        return  # local SQLite checks create the tables from the models instead
    try:
        with engine.begin() as connection:
            for statement in ADDITIVE_COLUMNS:
                connection.execute(text(statement))
    except Exception:
        # Never stop the API from starting over this; the failure is logged
        # and the matching Alembic migration can still be run by hand.
        logger.exception("Could not apply additive schema changes")
