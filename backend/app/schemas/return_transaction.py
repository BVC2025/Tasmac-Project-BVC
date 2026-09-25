from datetime import datetime

from pydantic import BaseModel

from app.models.payment import PaymentMethod
from app.models.return_transaction import RejectionReason, ReturnStatus


class VerifyRefundQrRequest(BaseModel):
    refund_qr_code: str
    latitude: float
    longitude: float


class VerifyRefundQrResponse(BaseModel):
    valid: bool
    bottle_id: int
    brand_name: str | None
    shop_name: str
    distance_meters: float


class VerifyManufacturingQrRequest(BaseModel):
    refund_qr_code: str
    manufacturing_qr_code: str


class VerifyManufacturingQrResponse(BaseModel):
    valid: bool
    bottle_id: int


class CompleteReturnRequest(BaseModel):
    refund_qr_code: str
    manufacturing_qr_code: str
    latitude: float
    longitude: float
    payment_method: PaymentMethod
    customer_identifier: str


class CompleteReturnResponse(BaseModel):
    id: int
    bottle_id: int
    qr_code: str
    shop_name: str
    status: ReturnStatus
    payment_status: str
    payment_reference: str | None
    amount: float
    distance_meters: float
    created_at: datetime


class RejectReturnResponse(BaseModel):
    id: int
    status: ReturnStatus
    reason: RejectionReason


class ReturnTransactionOut(BaseModel):
    id: int
    bottle_id: int | None
    qr_code: str | None
    shop_id: int
    shop_name: str
    staff_user_id: int
    status: ReturnStatus
    rejection_reason: RejectionReason | None
    remarks: str | None
    distance_meters: float | None
    created_at: datetime
    has_evidence_image: bool = False
    payment_method: PaymentMethod | None = None
    payment_amount: float | None = None
    payment_reference: str | None = None
    payment_status: str | None = None
