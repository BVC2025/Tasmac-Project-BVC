from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog

# Matches AuditLog.entity_id's String(50) column.
ENTITY_ID_MAX_LENGTH = 50


def log_action(
    db: Session,
    *,
    user_id: int | None,
    action: str,
    entity_type: str,
    entity_id: str | int,
    extra_data: dict | None = None,
) -> None:
    entity_id = str(entity_id)
    # entity_id can be a raw scanned code (e.g. an unrecognised refund QR),
    # and real-world QRs are often long URLs. Writing one past the column
    # length made Postgres reject the whole request with a 500, so the app
    # showed "Could not verify refund QR" instead of "not recognized".
    # Keep the full value in extra_data and store a truncated id.
    if len(entity_id) > ENTITY_ID_MAX_LENGTH:
        extra_data = {**(extra_data or {}), "full_entity_id": entity_id}
        entity_id = entity_id[:ENTITY_ID_MAX_LENGTH]

    db.add(
        AuditLog(
            user_id=user_id,
            action=action,
            entity_type=entity_type,
            entity_id=entity_id,
            extra_data=extra_data,
        )
    )
