import secrets

from sqlalchemy.orm import Session

from app.models.bottle import Bottle

REFUND_PREFIX = "TSM-R"
MANUFACTURING_PREFIX = "TSM-M"
MAX_GENERATION_ATTEMPTS = 5


def _code_in_use(db: Session, candidate: str) -> bool:
    return (
        db.query(Bottle).filter(Bottle.refund_qr_code == candidate).first() is not None
        or db.query(Bottle).filter(Bottle.manufacturing_qr_code == candidate).first() is not None
    )


def generate_unique_code(db: Session, prefix: str) -> str:
    for _ in range(MAX_GENERATION_ATTEMPTS):
        candidate = f"{prefix}-{secrets.token_hex(4)}"
        if not _code_in_use(db, candidate):
            return candidate
    raise RuntimeError("Could not generate a unique QR code")


def new_bottle(db: Session, brand_name: str | None = None) -> Bottle:
    """Not exposed over the API — bottle records are provisioned out-of-band
    (see scripts/generate_bottles.py), never by staff or admin through the app."""
    return Bottle(
        refund_qr_code=generate_unique_code(db, REFUND_PREFIX),
        manufacturing_qr_code=generate_unique_code(db, MANUFACTURING_PREFIX),
        brand_name=brand_name,
    )
