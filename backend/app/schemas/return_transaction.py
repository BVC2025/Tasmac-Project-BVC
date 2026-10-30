from datetime import datetime
from urllib.parse import parse_qs, urlparse

from pydantic import BaseModel, Field, field_validator

from app.models.payment import PaymentMethod
from app.models.return_transaction import RejectionReason, ReturnStatus

# Must match the String(n) column each value is stored in — anything longer
# would make Postgres reject the insert and the request fail with a 500.
CUSTOMER_IDENTIFIER_MAX_LENGTH = 120  # Payment.customer_identifier
PRODUCT_BARCODE_MAX_LENGTH = 64  # ReturnTransaction.product_barcode
MAX_BOTTLES_PER_BATCH = 20


def normalize_customer_identifier(value: str) -> str:
    """A scanned UPI QR is a full payment link (upi://pay?pa=...&pn=...&tr=...),
    often longer than the column. The payee VPA (``pa``) is what identifies the
    customer, so store that."""
    value = value.strip()
    if value.lower().startswith("upi://"):
        vpa = parse_qs(urlparse(value).query).get("pa", [""])[0].strip()
        if vpa:
            value = vpa
    if len(value) > CUSTOMER_IDENTIFIER_MAX_LENGTH:
        raise ValueError(f"Customer UPI ID / phone is too long (max {CUSTOMER_IDENTIFIER_MAX_LENGTH} characters)")
    return value


def validate_product_barcode(value: str | None) -> str | None:
    if value is not None and len(value) > PRODUCT_BARCODE_MAX_LENGTH:
        raise ValueError(f"Product barcode is too long (max {PRODUCT_BARCODE_MAX_LENGTH} characters)")
    return value


class VerifyRefundQrRequest(BaseModel):
    refund_qr_code: str
    latitude: float
    longitude: float


class VerifyRefundQrResponse(BaseModel):
    valid: bool
    bottle_id: int
    brand_name: str | None
    bottle_size: str | None = None
    shop_name: str
    distance_meters: float


class VerifyManufacturingQrRequest(BaseModel):
    refund_qr_code: str
    manufacturing_qr_code: str


class VerifyManufacturingQrResponse(BaseModel):
    valid: bool
    bottle_id: int
    brand_name: str | None = None
    bottle_size: str | None = None


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

    _normalize_customer_identifier = field_validator("customer_identifier")(normalize_customer_identifier)
    _validate_product_barcode = field_validator("product_barcode")(validate_product_barcode)


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
    # A bottle is only refundable when BOTH of its QRs are valid, so the
    # manufacturing QR is mandatory and is checked against the bottle record.
    manufacturing_qr_code: str
    # Legacy field from the old "no manufacturing QR, scan barcode" path; still
    # accepted and recorded so older app builds don't fail validation.
    product_barcode: str | None = None

    _validate_product_barcode = field_validator("product_barcode")(validate_product_barcode)


class CompleteReturnBatchRequest(BaseModel):
    latitude: float
    longitude: float
    payment_method: PaymentMethod
    customer_identifier: str
    bottles: list[BatchBottleItem] = Field(max_length=MAX_BOTTLES_PER_BATCH)

    _normalize_customer_identifier = field_validator("customer_identifier")(normalize_customer_identifier)


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
    # Same as refund_qr_code; kept for older app builds.
    qr_code: str | None
    refund_qr_code: str | None = None
    manufacturing_qr_code: str | None = None
    brand_name: str | None = None
    bottle_size: str | None = None
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
