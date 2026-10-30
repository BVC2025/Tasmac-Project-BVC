"""Staff "forgot password" requests, tracked in the audit log.

A request is open from the moment staff send it until an admin either resets
that user's password or dismisses the request — no extra table needed, and
every step stays in the audit trail.
"""

from datetime import datetime

from sqlalchemy.orm import Session

from app.models.audit_log import AuditLog
from app.models.user import User
from app.services.audit import log_action

REQUESTED = "password_reset_requested"
RESET_BY_ADMIN = "password_reset_by_admin"
DISMISSED = "password_reset_dismissed"


def _latest(db: Session, user_id: int, actions: tuple[str, ...]) -> AuditLog | None:
    return (
        db.query(AuditLog)
        .filter(AuditLog.entity_type == "user", AuditLog.entity_id == str(user_id), AuditLog.action.in_(actions))
        .order_by(AuditLog.id.desc())
        .first()
    )


def open_request(db: Session, user_id: int) -> AuditLog | None:
    """The user's newest request, if no reset/dismissal has come after it.
    Ordered by id rather than timestamp so same-second events still sort."""
    request = _latest(db, user_id, (REQUESTED,))
    if request is None:
        return None
    resolution = _latest(db, user_id, (RESET_BY_ADMIN, DISMISSED))
    if resolution is not None and resolution.id > request.id:
        return None
    return request


def create_request(db: Session, user: User, message: str | None) -> None:
    if open_request(db, user.id) is not None:
        return  # already waiting for an admin; don't pile up duplicates
    log_action(
        db=db, user_id=user.id, action=REQUESTED, entity_type="user", entity_id=user.id,
        extra_data={"message": message} if message else None,
    )


def resolve(db: Session, *, admin_id: int, user_id: int, action: str) -> None:
    log_action(db=db, user_id=admin_id, action=action, entity_type="user", entity_id=user_id)


def list_open_requests(db: Session) -> list[tuple[User, datetime, str | None]]:
    user_ids = {
        int(entity_id)
        for (entity_id,) in db.query(AuditLog.entity_id)
        .filter(AuditLog.action == REQUESTED, AuditLog.entity_type == "user")
        .distinct()
    }
    pending = []
    for user_id in user_ids:
        request = open_request(db, user_id)
        user = db.get(User, user_id)
        if request is not None and user is not None:
            pending.append((user, request.created_at, (request.extra_data or {}).get("message")))
    return sorted(pending, key=lambda item: item[1], reverse=True)
