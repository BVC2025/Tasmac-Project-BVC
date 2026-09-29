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


class LookupManufacturingQrRequest(BaseModel):
    manufacturing_qr_code: str


class LookupManufacturingQrResponse(BaseModel):
    bottle_id: int
    refund_qr_code: str


class CompleteReturnRequest(BaseModel):
    refund_qr_code: str
    manufacturing_qr_code: str
    latitude: float
    longitude: float
    payment_method: PaymentMethod
    customer_identifier: str
    product_barcode: str | None = None


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


class BatchBottleItem(BaseModel):
    refund_qr_code: str
    # Exactly one of these two should be set: manufacturing_qr_code when the
    # scanned second code matched this bottle's own manufacturing QR, or
    # product_barcode when the bottle had none and staff scanned its real
    # manufacturer barcode instead (recorded, not validated against anything).
    manufacturing_qr_code: str | None = None
    product_barcode: str | None = None


class CompleteReturnBatchRequest(BaseModel):
    latitude: float
    longitude: float
    payment_method: PaymentMethod
    customer_identifier: str
    bottles: list[BatchBottleItem]


class CompleteReturnBatchResponse(BaseModel):
    payment_reference: str | None
    payment_status: str
    amount: float
    count: int
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
    product_barcode: str | None
    distance_meters: float | None
    created_at: datetime
    has_evidence_image: bool = False
    payment_method: PaymentMethod | None = None
    payment_amount: float | None = None
    payment_reference: str | None = None
    payment_status: str | None = None
    payment_customer_identifier: str | None = None
