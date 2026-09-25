import random
import time as time_module
import uuid
from pathlib import Path

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session

from app.api.deps import get_current_admin_user, get_current_user
from app.core.geo import GEOFENCE_RADIUS_METERS, haversine_distance_meters
from app.db.session import get_db
from app.models.bottle import Bottle, BottleStatus
from app.models.payment import Payment, PaymentMethod, PaymentStatus
from app.models.return_transaction import RejectionReason, ReturnStatus, ReturnTransaction
from app.models.shop import Shop
from app.models.user import User, UserRole
from app.schemas.return_transaction import (
    CompleteReturnRequest,
    CompleteReturnResponse,
    RejectReturnResponse,
    ReturnTransactionOut,
    VerifyManufacturingQrRequest,
    VerifyManufacturingQrResponse,
    VerifyRefundQrRequest,
    VerifyRefundQrResponse,
)
from app.services.audit import log_action
from app.services.shop_access import ensure_within_service_window

router = APIRouter(prefix="/returns", tags=["returns"])

EVIDENCE_DIR = Path("media/evidence")


def _check_access(current_user: User, latitude: float, longitude: float) -> tuple[Shop, float]:
    shop = current_user.shop
    if shop is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You are not assigned to a shop")

    ensure_within_service_window(shop)

    if shop.latitude is None or shop.longitude is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Your shop has no registered location")

    distance = haversine_distance_meters(latitude, longitude, float(shop.latitude), float(shop.longitude))
    if distance > GEOFENCE_RADIUS_METERS:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail=f"You are {round(distance)}m from {shop.name} — must be within {GEOFENCE_RADIUS_METERS}m to proceed",
        )

    return shop, distance


def _simulate_payment() -> tuple[bool, str]:
    """Stands in for a real UPI/payment gateway call until one is integrated."""
    time_module.sleep(random.uniform(1.0, 2.0))
    success = random.random() < 0.85
    reference_id = f"SIM-{uuid.uuid4().hex[:10].upper()}"
    return success, reference_id


async def _save_evidence_image(file: UploadFile) -> str:
    EVIDENCE_DIR.mkdir(parents=True, exist_ok=True)
    suffix = Path(file.filename or "").suffix or ".jpg"
    filename = f"{uuid.uuid4().hex}{suffix}"
    path = EVIDENCE_DIR / filename
    path.write_bytes(await file.read())
    return f"media/evidence/{filename}"


def _to_out(transaction: ReturnTransaction) -> ReturnTransactionOut:
    distance = None
    if (
        transaction.latitude is not None
        and transaction.longitude is not None
        and transaction.shop.latitude is not None
        and transaction.shop.longitude is not None
    ):
        distance = round(
            haversine_distance_meters(
                float(transaction.latitude),
                float(transaction.longitude),
                float(transaction.shop.latitude),
                float(transaction.shop.longitude),
            ),
            1,
        )

    payment = transaction.payment

    return ReturnTransactionOut(
        id=transaction.id,
        bottle_id=transaction.bottle_id,
        qr_code=transaction.bottle.refund_qr_code if transaction.bottle else None,
        shop_id=transaction.shop_id,
        shop_name=transaction.shop.name,
        staff_user_id=transaction.staff_user_id,
        status=transaction.status,
        rejection_reason=transaction.rejection_reason,
        remarks=transaction.remarks,
        distance_meters=distance,
        created_at=transaction.created_at,
        has_evidence_image=transaction.evidence_image_path is not None,
        payment_method=payment.method if payment else None,
        payment_amount=float(payment.amount) if payment else None,
        payment_reference=payment.reference_id if payment else None,
        payment_status=payment.status.value if payment else None,
    )


@router.post("/verify-refund-qr", response_model=VerifyRefundQrResponse)
def verify_refund_qr(
    payload: VerifyRefundQrRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    shop, distance = _check_access(current_user, payload.latitude, payload.longitude)

    bottle = db.query(Bottle).filter(Bottle.refund_qr_code == payload.refund_qr_code).first()

    if bottle is None:
        log_action(
            db=db, user_id=current_user.id, action="verify_refund_qr", entity_type="bottle",
            entity_id=payload.refund_qr_code, extra_data={"result": "not_found"},
        )
        db.commit()
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Refund QR code not recognized")

    if bottle.status != BottleStatus.ISSUED:
        log_action(
            db=db, user_id=current_user.id, action="verify_refund_qr", entity_type="bottle",
            entity_id=bottle.id, extra_data={"result": "already_used", "status": bottle.status.value},
        )
        db.commit()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"This bottle has already been {bottle.status.value}")

    log_action(
        db=db, user_id=current_user.id, action="verify_refund_qr", entity_type="bottle",
        entity_id=bottle.id, extra_data={"result": "valid"},
    )
    db.commit()

    return VerifyRefundQrResponse(
        valid=True,
        bottle_id=bottle.id,
        brand_name=bottle.brand_name,
        shop_name=shop.name,
        distance_meters=round(distance, 1),
    )


@router.post("/verify-manufacturing-qr", response_model=VerifyManufacturingQrResponse)
def verify_manufacturing_qr(
    payload: VerifyManufacturingQrRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    bottle = db.query(Bottle).filter(Bottle.refund_qr_code == payload.refund_qr_code).first()
    if bottle is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Refund QR code not recognized")

    if bottle.manufacturing_qr_code != payload.manufacturing_qr_code:
        log_action(
            db=db, user_id=current_user.id, action="verify_manufacturing_qr", entity_type="bottle",
            entity_id=bottle.id, extra_data={"result": "mismatch"},
        )
        db.commit()
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Manufacturing QR does not match this bottle")

    log_action(
        db=db, user_id=current_user.id, action="verify_manufacturing_qr", entity_type="bottle",
        entity_id=bottle.id, extra_data={"result": "valid"},
    )
    db.commit()

    return VerifyManufacturingQrResponse(valid=True, bottle_id=bottle.id)


@router.post("/complete", response_model=CompleteReturnResponse, status_code=status.HTTP_201_CREATED)
def complete_return(
    payload: CompleteReturnRequest,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    shop, distance = _check_access(current_user, payload.latitude, payload.longitude)

    bottle = db.query(Bottle).filter(Bottle.refund_qr_code == payload.refund_qr_code).first()
    if bottle is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Refund QR code not recognized")
    if bottle.manufacturing_qr_code != payload.manufacturing_qr_code:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Manufacturing QR does not match this bottle")
    if bottle.status != BottleStatus.ISSUED:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail=f"This bottle has already been {bottle.status.value}")

    payment_success, reference_id = _simulate_payment()

    transaction = ReturnTransaction(
        bottle_id=bottle.id,
        shop_id=shop.id,
        staff_user_id=current_user.id,
        status=ReturnStatus.VERIFIED if payment_success else ReturnStatus.PENDING,
        latitude=payload.latitude,
        longitude=payload.longitude,
    )
    db.add(transaction)
    db.flush()

    payment = Payment(
        return_transaction_id=transaction.id,
        amount=10.00,
        method=payload.payment_method,
        status=PaymentStatus.SUCCESS if payment_success else PaymentStatus.FAILED,
        reference_id=reference_id,
        customer_identifier=payload.customer_identifier,
    )
    db.add(payment)

    if payment_success:
        bottle.status = BottleStatus.RETURNED

    log_action(
        db=db, user_id=current_user.id, action="complete_return", entity_type="return_transaction",
        entity_id=transaction.id,
        extra_data={"bottle_id": bottle.id, "payment_success": payment_success, "reference_id": reference_id},
    )

    db.commit()
    db.refresh(transaction)
    db.refresh(payment)

    if not payment_success:
        raise HTTPException(status_code=status.HTTP_402_PAYMENT_REQUIRED, detail="Payment failed or timed out. Please retry.")

    return CompleteReturnResponse(
        id=transaction.id,
        bottle_id=bottle.id,
        qr_code=bottle.refund_qr_code,
        shop_name=shop.name,
        status=transaction.status,
        payment_status=payment.status.value,
        payment_reference=payment.reference_id,
        amount=float(payment.amount),
        distance_meters=round(distance, 1),
        created_at=transaction.created_at,
    )


@router.post("/reject", response_model=RejectReturnResponse, status_code=status.HTTP_201_CREATED)
async def reject_return(
    reason: RejectionReason = Form(...),
    refund_qr_code: str | None = Form(default=None),
    remarks: str | None = Form(default=None),
    latitude: float | None = Form(default=None),
    longitude: float | None = Form(default=None),
    evidence_image: UploadFile | None = File(default=None),
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    shop = current_user.shop
    if shop is None:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="You are not assigned to a shop")

    bottle = None
    if refund_qr_code:
        bottle = db.query(Bottle).filter(Bottle.refund_qr_code == refund_qr_code).first()

    evidence_path = await _save_evidence_image(evidence_image) if evidence_image is not None else None

    transaction = ReturnTransaction(
        bottle_id=bottle.id if bottle else None,
        shop_id=shop.id,
        staff_user_id=current_user.id,
        status=ReturnStatus.REJECTED,
        latitude=latitude,
        longitude=longitude,
        rejection_reason=reason,
        evidence_image_path=evidence_path,
        remarks=remarks,
    )
    db.add(transaction)
    db.flush()

    log_action(
        db=db, user_id=current_user.id, action="reject_return", entity_type="return_transaction",
        entity_id=transaction.id,
        extra_data={"reason": reason.value, "bottle_id": bottle.id if bottle else None},
    )

    db.commit()
    db.refresh(transaction)

    return RejectReturnResponse(id=transaction.id, status=transaction.status, reason=reason)


@router.get("/mine", response_model=list[ReturnTransactionOut])
def list_my_returns(current_user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    transactions = (
        db.query(ReturnTransaction)
        .filter(ReturnTransaction.staff_user_id == current_user.id)
        .order_by(ReturnTransaction.id.desc())
        .all()
    )
    return [_to_out(t) for t in transactions]


@router.get("", response_model=list[ReturnTransactionOut])
def list_all_returns(admin_user: User = Depends(get_current_admin_user), db: Session = Depends(get_db)):
    transactions = db.query(ReturnTransaction).order_by(ReturnTransaction.id.desc()).all()
    return [_to_out(t) for t in transactions]


@router.get("/{return_id}/evidence-image")
def get_evidence_image(
    return_id: int,
    current_user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    transaction = db.get(ReturnTransaction, return_id)
    if transaction is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Return not found")

    is_owner = transaction.staff_user_id == current_user.id
    if not is_owner and current_user.role != UserRole.ADMIN:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not authorized to view this evidence image")

    if transaction.evidence_image_path is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="No evidence image for this return")

    image_path = Path(transaction.evidence_image_path)
    if not image_path.exists():
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Evidence image file is missing")

    return FileResponse(image_path)
